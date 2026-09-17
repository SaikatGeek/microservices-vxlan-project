# Screenshots

These were taken during a full run of the project in the lab on 2026-09-17: three
nodes built from nothing, the VXLAN mesh brought up, all 22 containers deployed, and
every test run. The code was not changed during the run.

They appear in order of the run.

## 1. Infrastructure

**Provision** — `make setup-infrastructure`. The VPC, three subnets, gateway, route
table, security group, and three nodes with their public and private IPs.

![Provision summary](01-provision.png)

**Validate** — `make validate-infrastructure`. Checks from outside and inside each node:
SSH, security group, tools, internet, DNS, HTTPS and path MTU. 12 local checks and every
remote check passed.

![Validation passed](02-validate-infrastructure.png)

## 2. VXLAN mesh

**Overlay on node 1** — `make setup-vxlan-mesh`. Node 1 owns DC1, so it creates `dc1-net`
with gateway `10.20.1.1`, and plain bridges for DC2 and DC3 with `.11` addresses. Each
tunnel gets the other two nodes as fdb peers.

![Overlay on node 1](03-overlay-up-node1.png)

**Network status** — `make show-network-status`. Three VXLAN links up, three bridges with
their addresses, six fdb peer entries.

![Network status on node 1](04-show-network-status.png)

**Routing table** — `make show-routing-table`. The three `10.20/30/40.0.0/16` routes are
`proto kernel`: Linux added them when the bridges got their addresses.

![Routing table on node 1](13-routing-table.png)

**Connectivity** — `make test-connectivity`. On node 3: IP forwarding, every tunnel up at
MTU 1450 with two peers, firewall rules in place, and pings to the DC1 and DC2 gateways
across the tunnels. 18 pass, 0 fail.

![Connectivity test on node 3](05-test-connectivity.png)

## 3. Services

**Deploy** — `make deploy-services`. The ten DC3 containers started with fixed IPs and
memory and CPU limits.

![DC3 deploy](06-deploy-services.png)

**Health** — `make health-check`. All 22 containers running; the 16 services report
healthy. The db and cache stubs have no health check.

![Health of every container](07-health-check.png)

**Service tests** — `make test-services`. Every DC1 container runs, answers HTTP 200,
reports healthy, answers `/health`, and names DC1 in its reply. 24 pass, 0 fail.

![DC1 service tests](08-test-services.png)

## 4. Across datacenters

**Cross-DC** — `make test-cross-dc`. Through the DC1 gateway, every route answers, and
each line shows which server answered and in which DC. The DC1 gateway container also
pings and calls containers in DC2 and DC3 directly. 11 pass, 0 fail.

![Cross-DC tests from DC1](09-test-cross-dc.png)

**VXLAN on the wire** — `sudo tcpdump -ni any udp port 4789` on node 1 while the cross-DC
test ran. The outer packets go between node IPs (`10.0.1.10` ↔ `10.0.2.10`) marked
`VXLAN ... vni 300`; inside is the call to the payment service on `10.30.2.10:8083`, with
`mss 1410` from the 1450 MTU.

![tcpdump of VXLAN traffic](12-tcpdump-vxlan.png)

## 5. Failover and load

**Failover** — `make test-failover`. `/users/` is answered by DC1. With `dc1-user-nginx`
stopped, the gateway tries DC1, moves on, and DC3 answers. When it starts again, traffic
returns to DC1.

![Failover test](10-test-failover.png)

**Load** — `make load-test`. 200 requests, 20 at a time, to `/orders/` through the DC1
gateway. All 200 succeeded, split 100 / 100 between the DC1 and DC2 order services.

![Load test](11-load-test.png)
