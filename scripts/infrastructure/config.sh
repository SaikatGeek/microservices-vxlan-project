# Every name, address and size used by the scripts, in one place.
# The other scripts load it with:  source "$(dirname "$0")/config.sh"

# region
REGION=ap-southeast-1

# vpc
VPC_CIDR=10.0.0.0/16
VPC_NAME=mdc-vpc

# subnets, one per availability zone
SUBNET1_CIDR=10.0.1.0/24    AZ1=ap-southeast-1a    SUBNET1_NAME=mdc-subnet-dc1
SUBNET2_CIDR=10.0.2.0/24    AZ2=ap-southeast-1b    SUBNET2_NAME=mdc-subnet-dc2
SUBNET3_CIDR=10.0.3.0/24    AZ3=ap-southeast-1c    SUBNET3_NAME=mdc-subnet-dc3

# gateway + routing
IGW_NAME=mdc-igw
RTB_NAME=mdc-rtb

# security group
SG_NAME="mdc-sg"
SG_DESC="MDC lab SG"

# key pair
KEY_NAME=mdc-key
KEY_FILE=$HOME/.ssh/mdc-key.pem

# instances
AMI_OWNER=099720109477
AMI_FILTER="Name=name,Values=*ubuntu*24.04*amd64*server*"
INSTANCE_TYPE=t2.micro
SSH_USER=ubuntu
NODE1_NAME=dc1-node    NODE1_IP=10.0.1.10
NODE2_NAME=dc2-node    NODE2_IP=10.0.2.10
NODE3_NAME=dc3-node    NODE3_IP=10.0.3.10

# ============================================================
# overlay — one DC = one VNI = one /16 = one bridge = one docker network
#
# All three VNIs exist on all three hosts. VNI 200 is DC1's layer-2
# segment, stretched to every host. Traffic between DCs is routed at
# layer 3 inside whichever host the packet is already on, so there is
# no extra hop.
# ============================================================
DC1_VNI=200    DC1_CIDR=10.20.0.0/16    DC1_GW=10.20.1.1    DC1_BRIDGE=br-dc1    DC1_NET=dc1-net
DC2_VNI=300    DC2_CIDR=10.30.0.0/16    DC2_GW=10.30.1.1    DC2_BRIDGE=br-dc2    DC2_NET=dc2-net
DC3_VNI=400    DC3_CIDR=10.40.0.0/16    DC3_GW=10.40.1.1    DC3_BRIDGE=br-dc3    DC3_NET=dc3-net

# The task lists DC2 and DC3 as 10.300.0.0/16 and 10.400.0.0/16.
# An IPv4 octet cannot go above 255, so those are not valid addresses.
# We use 10.30.0.0/16 and 10.40.0.0/16 instead.
# See architecture/network-topology.md.

# 1500 - 50 bytes of VXLAN overhead
# (20 outer IP + 8 outer UDP + 8 VXLAN header + 14 inner Ethernet).
# Setting it here does nothing by itself. It reaches the containers
# through  -o com.docker.network.driver.mtu  on the docker network.
OVERLAY_MTU=1450
VXLAN_PORT=4789

# The node that owns a DC holds its gateway address (DCx_GW, ending in .1).
# The other two nodes still need that bridge, or the kernel has no route
# to that /16 and cannot pass traffic between DCs. They get .1(10+node):
#
#   bridge   node1          node2          node3
#   br-dc1   10.20.1.1 gw   10.20.1.12     10.20.1.13
#   br-dc2   10.30.1.11     10.30.1.1 gw   10.30.1.13
#   br-dc3   10.40.1.11     10.40.1.12     10.40.1.1 gw
#
# The same address on two hosts would confuse ARP: once the tunnels are
# up, the three bridges of a DC are one broadcast domain.
NON_OWNER_HOST_OFFSET=10

# every aws call in every script picks this up
export AWS_DEFAULT_REGION="$REGION"
