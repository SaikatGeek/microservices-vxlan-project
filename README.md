# Multi-Datacenter Microservices over VXLAN

This project runs eight small nginx services across three "datacenters" on AWS.
Each datacenter is one EC2 node in its own availability zone. The containers in
different datacenters talk to each other over VXLAN tunnels, as if they were
on the same local network.

Everything is built with bash, the AWS CLI, Docker and a Makefile. No console
clicks, no Terraform, no Kubernetes.

## What you get

- **3 datacenters** in `ap-southeast-1a`, `1b` and `1c`, one EC2 node each
- **3 VXLAN networks**, one per datacenter: VNI 200, 300 and 400
- **8 nginx services**, 22 containers in total, each with a fixed IP
- **Failover**: the gateway sends traffic to a backup copy in DC3 when a service goes down
- **Health checks** and **memory / CPU limits** on every container
- **Tests** for the network, the services, cross-datacenter traffic, failover and load

## The big picture

```
                       AWS VPC 10.0.0.0/16  (one subnet per AZ)

   ap-southeast-1a             ap-southeast-1b             ap-southeast-1c
 +-------------------+       +-------------------+       +-------------------+
 |  dc1-node         |       |  dc2-node         |       |  dc3-node         |
 |  10.0.1.10        |       |  10.0.2.10        |       |  10.0.3.10        |
 |                   |       |                   |       |                   |
 |  DC1 containers   |       |  DC2 containers   |       |  DC3 containers   |
 |  10.20.x.x        |       |  10.30.x.x        |       |  10.40.x.x        |
 |                   |       |                   |       |                   |
 |  br-dc1  vxlan200 |=======|  br-dc1  vxlan200 |=======|  br-dc1  vxlan200 |
 |  br-dc2  vxlan300 |=======|  br-dc2  vxlan300 |=======|  br-dc2  vxlan300 |
 |  br-dc3  vxlan400 |=======|  br-dc3  vxlan400 |=======|  br-dc3  vxlan400 |
 +-------------------+       +-------------------+       +-------------------+

   ===  VXLAN over UDP 4789, full mesh (node 1 also links straight to node 3)
```

AWS only sees normal UDP traffic between the three node IPs. The container
traffic (`10.20.x.x`, `10.30.x.x`, `10.40.x.x`) is packed inside it.

The full network design is in [architecture/network-topology.md](architecture/network-topology.md).

## Quick start

Run everything from this folder, inside the lab container. You need the AWS CLI
configured for `ap-southeast-1`, and `make`.

```bash
make setup-infrastructure      # VPC, subnets, gateway, SG, key, 3 nodes; copies this project to them
make validate-infrastructure   # checks the 3 nodes
make setup-vxlan-mesh          # bridges, docker networks and tunnels on every node
make test-connectivity         # the tunnels work (no containers needed yet)
make deploy-services           # builds images and starts all 22 containers
make test                      # connectivity + services + cross-datacenter
```

Or all of it in one go:

```bash
make all
```

When you are done:

```bash
make cleanup-infrastructure    # deletes every AWS resource this project made
```

`make help` lists every target with a one-line description.

## Services

| Service | Port | DC1 | DC2 | DC3 |
|---|---|---|---|---|
| gateway-nginx | 80 | primary | backup | standby |
| user-nginx | 8080 | primary | | standby |
| catalog-nginx | 8081 | primary | | standby |
| order-nginx | 8082 | primary | replica | standby |
| payment-nginx | 8083 | | primary | standby |
| notify-nginx | 8084 | | primary | standby |
| analytics-nginx | 8085 | | | primary |
| discovery-nginx | 8500 | | | primary |

Each datacenter also has a `db-stub` and a `cache-stub` for the data tier.

How the services work and fail over: [architecture/service-architecture.md](architecture/service-architecture.md).
One page per service: [docs/services/](docs/services/).

## Folder layout

```
Makefile                   every command, in one place
architecture/              network topology, service architecture, deployment strategy
configs/nginx/             nginx config per service, and the script that sets the DC name
data/service-responses/    the HTML/JSON each service returns
dockerfiles/               one Dockerfile per service
scripts/infrastructure/    AWS setup, checks, VXLAN mesh, teardown
scripts/deployment/        build and run the containers of one DC
scripts/testing/           connectivity, services, cross-DC, failover, load
scripts/remote.sh          runs a command inside a node from the lab
docs/                      setup guide, troubleshooting, service pages, screenshots
```

## More

- Step by step setup, with the output to expect: [docs/setup-guide.md](docs/setup-guide.md)
- When something does not work: [docs/troubleshooting.md](docs/troubleshooting.md)
- Why things are done in this order: [architecture/deployment-strategy.md](architecture/deployment-strategy.md)

## One change from the task

The task gives DC2 and DC3 the subnets `10.300.0.0/16` and `10.400.0.0/16`. Those
are not valid IP addresses, because each part of an IPv4 address can only go up to
255. This project uses `10.30.0.0/16` and `10.40.0.0/16` instead, and keeps
everything else the same. The details are in
[architecture/network-topology.md](architecture/network-topology.md#a-correction-to-the-task).
