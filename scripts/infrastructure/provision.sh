#!/bin/bash
# Builds the AWS side: VPC, three subnets in three AZs, internet gateway,
# route table, security group, key pair and three EC2 nodes.
#
# Run it from the lab container. Safe to run again: every step first looks
# for the resource by its Name tag and reuses it if it is already there.
set -euo pipefail
source "$(dirname "$0")/config.sh"

# ============================================================
# helpers
# ============================================================

# ssh_node <ip> <command>
ssh_node() {
    ssh -i "$KEY_FILE" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        -o ConnectTimeout=10 \
        "$SSH_USER@$1" "$2"
}

# node_ready <instance-id>  →  prints the public IP once SSH works
node_ready() {
    local PUB i

    aws ec2 wait instance-running --instance-ids "$1"

    PUB=$(aws ec2 describe-instances --instance-ids "$1" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

    if [ "$PUB" = "None" ]; then
        echo "No public IP. Check map-public-ip-on-launch on the subnet." >&2
        exit 1
    fi

    for i in 1 2 3 4 5 6 7 8 9 10; do
        if ssh_node "$PUB" true 2>/dev/null; then
            echo "$PUB"
            return 0
        fi
        echo "  sshd not ready ($i/10)" >&2
        sleep 10
    done

    echo "SSH never came up: ssh -i $KEY_FILE $SSH_USER@$PUB" >&2
    exit 1
}

# get_nic <public-ip>  →  prints the NIC name (eth0 / ens5 / enX0 ...)
# The name changes between instance families, so it is always detected,
# never hard-coded.
get_nic() {
    local nic
    nic=$(ssh_node "$1" 'ip route get 1.1.1.1 | awk "{print \$5; exit}"')

    # SSH can succeed and still return nothing. Stop here, or the vxlan
    # step later gets 'dev' with no name after it and the error points
    # at VXLAN instead of the real cause.
    if [ -z "$nic" ]; then
        echo "Could not read the NIC name on $1" >&2
        return 1
    fi

    echo "$nic"
}

# add_ingress <protocol> <port> <cidr>
# Adds one security group rule. If it already exists, that is fine.
# A brand-new SG is not visible to every AWS endpoint straight away and
# can return NotFound, so those errors are retried with a backoff.
add_ingress() {
    local proto="$1" port="$2" cidr="$3"
    local n=1 out rc

    while : ; do
        out=$(aws ec2 authorize-security-group-ingress \
                --group-id "$SG_ID" \
                --protocol "$proto" \
                --port "$port" \
                --cidr "$cidr" 2>&1) && rc=0 || rc=$?

        if [ "$rc" -eq 0 ]; then
            echo "  added   $proto/$port from $cidr"
            return 0
        fi

        case "$out" in
            *Duplicate*)
                echo "  exists  $proto/$port from $cidr"
                return 0
                ;;
            *NotFound*|*Throttl*|*RequestLimitExceeded*|*Unavailable*)
                if [ "$n" -ge 6 ]; then break; fi
                echo "  retry $n/6 — $proto/$port (sg not visible yet)" >&2
                sleep $(( n * 2 ))
                n=$(( n + 1 ))
                ;;
            *)
                break
                ;;
        esac
    done

    echo "FAILED  $proto/$port from $cidr" >&2
    echo "$out" >&2
    return 1
}

# ============================================================
# 1. VPC
# ============================================================
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=$VPC_NAME" \
    --query 'Vpcs[0].VpcId' \
    --output text)

if [ "$VPC_ID" = "None" ]; then
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block "$VPC_CIDR" \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$VPC_NAME}]" \
        --query 'Vpc.VpcId' \
        --output text)
    echo "vpc created  $VPC_ID"
else
    echo "vpc reused   $VPC_ID"
fi

# ============================================================
# 2. Subnets — one per AZ
#    The vpc-id filter matters: without it, an old subnet with the same
#    name in another VPC could be picked up.
# ============================================================
SUBNET1=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=$SUBNET1_NAME" "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[0].SubnetId' --output text)
if [ "$SUBNET1" = "None" ]; then
    SUBNET1=$(aws ec2 create-subnet \
        --vpc-id "$VPC_ID" \
        --cidr-block "$SUBNET1_CIDR" \
        --availability-zone "$AZ1" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$SUBNET1_NAME}]" \
        --query 'Subnet.SubnetId' --output text)
    echo "subnet created  $SUBNET1  $SUBNET1_CIDR  $AZ1"
else
    echo "subnet reused   $SUBNET1  $SUBNET1_CIDR  $AZ1"
fi

SUBNET2=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=$SUBNET2_NAME" "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[0].SubnetId' --output text)
if [ "$SUBNET2" = "None" ]; then
    SUBNET2=$(aws ec2 create-subnet \
        --vpc-id "$VPC_ID" \
        --cidr-block "$SUBNET2_CIDR" \
        --availability-zone "$AZ2" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$SUBNET2_NAME}]" \
        --query 'Subnet.SubnetId' --output text)
    echo "subnet created  $SUBNET2  $SUBNET2_CIDR  $AZ2"
else
    echo "subnet reused   $SUBNET2  $SUBNET2_CIDR  $AZ2"
fi

SUBNET3=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=$SUBNET3_NAME" "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[0].SubnetId' --output text)
if [ "$SUBNET3" = "None" ]; then
    SUBNET3=$(aws ec2 create-subnet \
        --vpc-id "$VPC_ID" \
        --cidr-block "$SUBNET3_CIDR" \
        --availability-zone "$AZ3" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$SUBNET3_NAME}]" \
        --query 'Subnet.SubnetId' --output text)
    echo "subnet created  $SUBNET3  $SUBNET3_CIDR  $AZ3"
else
    echo "subnet reused   $SUBNET3  $SUBNET3_CIDR  $AZ3"
fi

# ============================================================
# 3. Internet gateway + attach
# ============================================================
IGW_ID=$(aws ec2 describe-internet-gateways \
    --filters "Name=tag:Name,Values=$IGW_NAME" \
    --query 'InternetGateways[0].InternetGatewayId' --output text)
if [ "$IGW_ID" = "None" ]; then
    IGW_ID=$(aws ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$IGW_NAME}]" \
        --query 'InternetGateway.InternetGatewayId' --output text)
    echo "igw created  $IGW_ID"
else
    echo "igw reused   $IGW_ID"
fi

# Checked on its own: an IGW existing and an IGW attached to the VPC
# are two different things.
ATTACHED_TO=$(aws ec2 describe-internet-gateways \
    --internet-gateway-ids "$IGW_ID" \
    --query 'InternetGateways[0].Attachments[0].VpcId' --output text)
if [ "$ATTACHED_TO" = "None" ]; then
    aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
    echo "igw attached to $VPC_ID"
else
    echo "igw already attached to $ATTACHED_TO"
fi

# ============================================================
# 4. Route table + default route + associations
# ============================================================
RTB_ID=$(aws ec2 describe-route-tables \
    --filters "Name=tag:Name,Values=$RTB_NAME" "Name=vpc-id,Values=$VPC_ID" \
    --query 'RouteTables[0].RouteTableId' --output text)
if [ "$RTB_ID" = "None" ]; then
    RTB_ID=$(aws ec2 create-route-table \
        --vpc-id "$VPC_ID" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$RTB_NAME}]" \
        --query 'RouteTable.RouteTableId' --output text)
    echo "rtb created  $RTB_ID"
else
    echo "rtb reused   $RTB_ID"
fi

# 0.0.0.0/0 → IGW  (adding it twice gives RouteAlreadyExists)
DEFAULT_ROUTE=$(aws ec2 describe-route-tables \
    --route-table-ids "$RTB_ID" \
    --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].GatewayId | [0]" \
    --output text)
if [ "$DEFAULT_ROUTE" = "None" ]; then
    aws ec2 create-route \
        --route-table-id "$RTB_ID" \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id "$IGW_ID"
    echo "route created  0.0.0.0/0 -> $IGW_ID"
else
    echo "route exists   0.0.0.0/0 -> $DEFAULT_ROUTE"
fi

for SUBNET in "$SUBNET1" "$SUBNET2" "$SUBNET3"; do
    ASSOC=$(aws ec2 describe-route-tables \
        --route-table-ids "$RTB_ID" \
        --query "RouteTables[0].Associations[?SubnetId=='$SUBNET'].RouteTableAssociationId | [0]" \
        --output text)
    if [ "$ASSOC" = "None" ]; then
        aws ec2 associate-route-table --route-table-id "$RTB_ID" --subnet-id "$SUBNET" >/dev/null
        echo "assoc created  $SUBNET"
    else
        echo "assoc exists   $SUBNET"
    fi
    # Setting the same value again is fine, AWS does not complain.
    aws ec2 modify-subnet-attribute --subnet-id "$SUBNET" --map-public-ip-on-launch
done

aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[].[SubnetId,CidrBlock,AvailabilityZone,MapPublicIpOnLaunch]' \
    --output table

# ============================================================
# 5. Security group + ingress rules
#    SG names are unique inside a VPC, so search by name + vpc-id.
# ============================================================
SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[0].GroupId' --output text)

if [ "$SG_ID" = "None" ]; then
    SG_ID=$(aws ec2 create-security-group \
        --group-name "$SG_NAME" \
        --description "$SG_DESC" \
        --vpc-id "$VPC_ID" \
        --query 'GroupId' --output text)
    echo "sg created  $SG_ID"
else
    echo "sg reused   $SG_ID"
fi

add_ingress tcp  22        0.0.0.0/0      # ssh from the lab
add_ingress udp  4789      "$VPC_CIDR"    # vxlan between nodes
add_ingress icmp -1        "$VPC_CIDR"    # ping inside the VPC
add_ingress tcp  80        "$VPC_CIDR"    # gateway
add_ingress tcp  8080-8085 "$VPC_CIDR"    # app services
add_ingress tcp  8500      "$VPC_CIDR"    # discovery

aws ec2 describe-security-groups --group-ids "$SG_ID" \
    --query 'SecurityGroups[0].IpPermissions[].[IpProtocol,FromPort,ToPort,IpRanges[0].CidrIp]' \
    --output table

# ============================================================
# 6. Key pair
#    AWS hands over the private key only once. So check both: is it in
#    AWS, and is the local file there?
# ============================================================
mkdir -p "$(dirname "$KEY_FILE")"

KEY_IN_AWS=no
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
    KEY_IN_AWS=yes
fi

if [ "$KEY_IN_AWS" = "yes" ] && [ -s "$KEY_FILE" ]; then
    echo "key reused   $KEY_NAME  ($KEY_FILE)"
else
    if [ "$KEY_IN_AWS" = "yes" ]; then
        echo "key $KEY_NAME in AWS but $KEY_FILE missing — recreating"
        aws ec2 delete-key-pair --key-name "$KEY_NAME"
    fi
    # Write to a temp file first, then move. If the aws call fails,
    # an existing key file is not damaged.
    TMP_KEY=$(mktemp)
    aws ec2 create-key-pair --key-name "$KEY_NAME" \
        --query 'KeyMaterial' --output text > "$TMP_KEY"
    mv "$TMP_KEY" "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    echo "key created  $KEY_NAME  ($KEY_FILE)"
fi

# ============================================================
# 7. AMI lookup
#    describe-images exits 0 even when nothing matched, so set -e will
#    not catch it. Check by hand.
# ============================================================
AMI_ID=$(aws ec2 describe-images \
    --owners "$AMI_OWNER" \
    --filters "$AMI_FILTER" \
    --query 'sort_by(Images,&CreationDate)[-1].ImageId' \
    --output text)

if [ "$AMI_ID" = "None" ] || [ -z "$AMI_ID" ]; then
    echo "no AMI matched: $AMI_FILTER" >&2
    exit 1
fi
echo "ami          $AMI_ID"

# ============================================================
# 8. Instances
#    Terminated instances still come back with their tag, hence the
#    state filter.
# ============================================================
launch_node() {
    local NAME="$1" SUBNET="$2" IP="$3"
    local INSTANCE_ID

    INSTANCE_ID=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$NAME" \
                "Name=instance-state-name,Values=pending,running" \
        --query 'Reservations[0].Instances[0].InstanceId' --output text)

    if [ "$INSTANCE_ID" = "None" ]; then
        INSTANCE_ID=$(aws ec2 run-instances \
            --image-id "$AMI_ID" \
            --instance-type "$INSTANCE_TYPE" \
            --subnet-id "$SUBNET" \
            --private-ip-address "$IP" \
            --key-name "$KEY_NAME" \
            --security-group-ids "$SG_ID" \
            --count 1 \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME}]" \
            --query 'Instances[0].InstanceId' --output text)
        echo "instance created  $INSTANCE_ID" >&2
    else
        echo "instance reused   $INSTANCE_ID" >&2
    fi

    echo "$INSTANCE_ID"
}

# Launch all three first, then wait. They boot in parallel, so the
# waiting does not add up.
NODE1_ID=$(launch_node "$NODE1_NAME" "$SUBNET1" "$NODE1_IP")
NODE2_ID=$(launch_node "$NODE2_NAME" "$SUBNET2" "$NODE2_IP")
NODE3_ID=$(launch_node "$NODE3_NAME" "$SUBNET3" "$NODE3_IP")

# ============================================================
# 9. All three running and accepting SSH
# ============================================================
NODE1_PUB=$(node_ready "$NODE1_ID")
NODE2_PUB=$(node_ready "$NODE2_ID")
NODE3_PUB=$(node_ready "$NODE3_ID")

# ============================================================
# 10. NIC names — read inside each instance
# ============================================================
NODE1_NIC=$(get_nic "$NODE1_PUB")
NODE2_NIC=$(get_nic "$NODE2_PUB")
NODE3_NIC=$(get_nic "$NODE3_PUB")

# ============================================================
echo
echo "======================================"
echo " vpc        $VPC_ID"
echo " subnets    $SUBNET1  $SUBNET2  $SUBNET3"
echo " igw        $IGW_ID"
echo " rtb        $RTB_ID"
echo " sg         $SG_ID"
echo
echo " node1      $NODE1_ID"
echo "            public $NODE1_PUB   private $NODE1_IP   nic $NODE1_NIC"
echo " node2      $NODE2_ID"
echo "            public $NODE2_PUB   private $NODE2_IP   nic $NODE2_NIC"
echo " node3      $NODE3_ID"
echo "            public $NODE3_PUB   private $NODE3_IP   nic $NODE3_NIC"
echo "======================================"
echo
echo "ssh -i $KEY_FILE $SSH_USER@$NODE1_PUB"
echo "ssh -i $KEY_FILE $SSH_USER@$NODE2_PUB"
echo "ssh -i $KEY_FILE $SSH_USER@$NODE3_PUB"
echo
echo "Next: bash scripts/infrastructure/verify.sh"
