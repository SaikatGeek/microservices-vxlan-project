#!/bin/bash
# Deletes everything provision.sh builds. It does not ask first.
# It only touches resources whose Name tag matches config.sh — nothing else.
#
# No -e on purpose: it must keep going even when things are half deleted.
# "Already gone" counts as success here, not failure.
set -uo pipefail
source "$(dirname "$0")/config.sh"

FAILED=0

# ============================================================
# del <what> <aws command...>
#   NotFound            → already deleted, fine
#   DependencyViolation → something still holds it, wait and retry
# ============================================================
del() {
    local what="$1"; shift
    local n=1 out rc

    while : ; do
        out=$("$@" 2>&1) && rc=0 || rc=$?

        if [ "$rc" -eq 0 ]; then
            echo "  deleted  $what"
            return 0
        fi

        case "$out" in
            *NotFound*|*does\ not\ exist*|*InvalidVpcID*|*InvalidSubnetID*)
                echo "  gone     $what"
                return 0
                ;;
            *DependencyViolation*|*Throttl*|*RequestLimitExceeded*|*InvalidParameterValue*)
                if [ "$n" -ge 6 ]; then break; fi
                echo "  retry $n/6  $what — dependency still holding" >&2
                sleep $(( n * 3 ))
                n=$(( n + 1 ))
                ;;
            *)
                break
                ;;
        esac
    done

    echo "  FAILED   $what" >&2
    echo "$out" >&2
    FAILED=1
    return 1
}

echo "=== teardown: everything tagged for '$VPC_NAME' in $REGION ==="

# ============================================================
# 1. Instances — first. The SG and subnets are held by them.
# ============================================================
# every state except terminated / shutting-down
INSTANCE_IDS=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$NODE1_NAME,$NODE2_NAME,$NODE3_NAME" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text 2>/dev/null)

if [ -n "$INSTANCE_IDS" ] && [ "$INSTANCE_IDS" != "None" ]; then
    echo "instance  $INSTANCE_IDS"
    # $INSTANCE_IDS is unquoted on purpose: several IDs come back separated
    # by tabs, and bash has to split them.
    del "instance $INSTANCE_IDS" \
        aws ec2 terminate-instances --instance-ids $INSTANCE_IDS --output text

    # Skip this wait and the SG delete below fails with DependencyViolation.
    # terminate-instances returns at once; it does not wait for the end.
    echo "  waiting for terminated (30-60 seconds)..."
    aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS
    echo "  terminated"
else
    echo "instance  none"
fi

# ============================================================
# 2. Key pair — in AWS and the local file
# ============================================================
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
    del "key pair $KEY_NAME" aws ec2 delete-key-pair --key-name "$KEY_NAME"
else
    echo "  gone     key pair $KEY_NAME"
fi

if [ -f "$KEY_FILE" ]; then
    rm -f "$KEY_FILE"
    echo "  deleted  $KEY_FILE"
fi

# ============================================================
# Find the VPC — everything below is looked up inside it
# ============================================================
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=$VPC_NAME" \
    --query 'Vpcs[0].VpcId' --output text 2>/dev/null)

if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
    echo "vpc       none — nothing else to delete"
    echo "=== teardown done ==="
    exit $FAILED
fi
echo "vpc       $VPC_ID"

# ============================================================
# 3. Security group
#    The default SG cannot be deleted and does not need to be. Only ours.
# ============================================================
SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)

if [ "$SG_ID" != "None" ] && [ -n "$SG_ID" ]; then
    del "sg $SG_ID" aws ec2 delete-security-group --group-id "$SG_ID"
else
    echo "  gone     sg $SG_NAME"
fi

# ============================================================
# 4. Route table — associations first, then the table
# ============================================================
RTB_ID=$(aws ec2 describe-route-tables \
    --filters "Name=tag:Name,Values=$RTB_NAME" "Name=vpc-id,Values=$VPC_ID" \
    --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null)

if [ "$RTB_ID" != "None" ] && [ -n "$RTB_ID" ]; then
    echo "rtb       $RTB_ID"

    # Main==false — the VPC's main association can never be removed.
    # The query is in single quotes because JMESPath backticks would
    # otherwise be command substitution in bash.
    ASSOC_IDS=$(aws ec2 describe-route-tables \
        --route-table-ids "$RTB_ID" \
        --query 'RouteTables[0].Associations[?Main==`false`].RouteTableAssociationId' \
        --output text 2>/dev/null)

    for A in $ASSOC_IDS; do
        [ "$A" = "None" ] && continue
        del "assoc $A" aws ec2 disassociate-route-table --association-id "$A"
    done

    del "rtb $RTB_ID" aws ec2 delete-route-table --route-table-id "$RTB_ID"
else
    echo "  gone     rtb $RTB_NAME"
fi

# ============================================================
# 5. Internet gateway — detach, then delete
# ============================================================
IGW_ID=$(aws ec2 describe-internet-gateways \
    --filters "Name=tag:Name,Values=$IGW_NAME" \
    --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null)

if [ "$IGW_ID" != "None" ] && [ -n "$IGW_ID" ]; then
    echo "igw       $IGW_ID"

    ATTACHED_TO=$(aws ec2 describe-internet-gateways \
        --internet-gateway-ids "$IGW_ID" \
        --query 'InternetGateways[0].Attachments[0].VpcId' --output text 2>/dev/null)

    if [ "$ATTACHED_TO" != "None" ] && [ -n "$ATTACHED_TO" ]; then
        del "igw detach from $ATTACHED_TO" \
            aws ec2 detach-internet-gateway \
                --internet-gateway-id "$IGW_ID" --vpc-id "$ATTACHED_TO"
    fi

    del "igw $IGW_ID" aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID"
else
    echo "  gone     igw $IGW_NAME"
fi

# ============================================================
# 6. Subnets
# ============================================================
for SUBNET_NAME in "$SUBNET1_NAME" "$SUBNET2_NAME" "$SUBNET3_NAME"; do
    SUBNET_ID=$(aws ec2 describe-subnets \
        --filters "Name=tag:Name,Values=$SUBNET_NAME" "Name=vpc-id,Values=$VPC_ID" \
        --query 'Subnets[0].SubnetId' --output text 2>/dev/null)

    if [ "$SUBNET_ID" != "None" ] && [ -n "$SUBNET_ID" ]; then
        del "subnet $SUBNET_NAME ($SUBNET_ID)" \
            aws ec2 delete-subnet --subnet-id "$SUBNET_ID"
    else
        echo "  gone     subnet $SUBNET_NAME"
    fi
done

# ============================================================
# 7. VPC — last
# ============================================================
del "vpc $VPC_ID" aws ec2 delete-vpc --vpc-id "$VPC_ID"

echo
if [ "$FAILED" -eq 0 ]; then
    echo "=== teardown clean ==="
else
    echo "=== teardown finished with errors — see the FAILED lines above ===" >&2
    echo "To see what is left:" >&2
    echo "  aws ec2 describe-vpcs --filters \"Name=tag:Name,Values=$VPC_NAME\" --output table" >&2
fi
exit $FAILED
