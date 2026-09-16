# Deployment Strategy

This page explains the order things are built in, where each script runs, and why
running any step twice is safe.

## Where things run

There are two places commands run:

| Where | What runs there | Why |
|---|---|---|
| **Lab container** | `make`, `provision.sh`, `verify.sh`, `teardown.sh`, `push-project.sh`, `remote.sh` | It has the AWS CLI and the SSH key |
| **Inside each EC2 node** | `overlay-up.sh`, `overlay-down.sh`, `deploy-services.sh`, the test scripts | Bridges, tunnels and containers live on the node |

You never need to log in to a node by hand. `scripts/remote.sh` finds a node by its
`Name` tag, connects over SSH and runs the command inside
`~/microservices-vxlan-project`. The Makefile uses it for every node target.

## The order

```
1. make setup-infrastructure     provision.sh, then push-project.sh
2. make validate-infrastructure  verify.sh
3. make setup-vxlan-mesh         overlay-up.sh on node 1, 2, 3
4. make test-connectivity        stop here if anything fails
5. make deploy-services          deploy-services.sh on node 1, 2, 3
6. make test                     connectivity + services + cross-DC
```

Each step depends on the one before:

1. **Infrastructure first.** Nodes, subnets and the security group must exist
   before anything can run on them. `push-project.sh` then copies this project to
   every node and installs `docker`, `tcpdump`, `ping` and `curl`, which a fresh
   Ubuntu node does not have.
2. **Validate before building on top.** `verify.sh` checks each node from outside
   (running, SSH open, ICMP blocked from the internet as intended) and from inside
   (tools present, internet reachable, MTU). A problem found here is cheap. The same
   problem found after deploying 22 containers is not.
3. **Network before containers.** `overlay-up.sh` creates the Docker network on the
   node that owns each DC. Containers cannot start without it.
4. **Test the network with no containers.** `test-connectivity` pings each
   datacenter's gateway address across the tunnels. If it passes, the tunnels, fdb
   peers, `ip_forward` and firewall rules are all correct. If it fails, nothing built
   later will work either, so this is the place to stop and fix.
5. **Deploy each DC on its own node.** Node 1 runs DC1, node 2 runs DC2, node 3 runs
   DC3. `deploy-services.sh` builds only the images that DC needs, then starts each
   container with its fixed IP, limits and DC name.
6. **Test everything.**

![Deploy output for one DC](../docs/screenshots/06-deploy-services.png)

## Why each DC's network lives on one node

Docker's network for DC1 (`dc1-net`, gateway `10.20.1.1`) is created only on node 1.
Nodes 2 and 3 still have a `br-dc1` bridge, but made by hand with their own
addresses (`10.20.1.12`, `10.20.1.13`).

If all three nodes created `dc1-net`, all three would claim `10.20.1.1`, and once
the tunnel joins them that address would exist three times on one network.

## Running a step twice is safe

Every script checks before it acts, so a step that failed halfway can simply be run
again:

- `provision.sh` looks up each AWS resource by its `Name` tag and reuses it if it exists.
- `push-project.sh` replaces the old copy on each node.
- `overlay-up.sh` reuses bridges and Docker networks, and deletes and recreates the
  VXLAN devices. Recreating them also clears their fdb, so peers never pile up.
  Firewall rules are checked with `iptables -C` before they are added.
- `deploy-services.sh` removes a container with the same name before starting a new one.
- `teardown.sh` treats "already deleted" as success, so it can finish a half-done cleanup.

## Updating

After changing a config, reply file or Dockerfile on the lab side:

```bash
make push-project          # copy the changed project to the nodes
make deploy-services       # rebuild images and replace the containers
make test
```

To change only one datacenter, use `make deploy-dc1-services` (or dc2, dc3).

## Stopping and cleaning up

| Target | What it does | Can be undone with |
|---|---|---|
| `make stop-services` | stops every container, keeps it | `make start-services` |
| `make cleanup-services` | removes every container | `make deploy-services` |
| `make cleanup-vxlan` | removes tunnels, hand-made bridges, firewall rules | `make setup-vxlan-mesh` |
| `make cleanup-infrastructure` | deletes every AWS resource this project made | `make setup-infrastructure` |

`teardown.sh` only touches resources whose `Name` tag matches `config.sh`. It deletes
them in reverse order (instances, key pair, security group, route table, internet
gateway, subnets, VPC) and waits for the instances to be fully terminated first,
because a terminating instance still holds its security group.

## Settings in one place

Every name, CIDR, IP and size used by the infrastructure scripts is in
`scripts/infrastructure/config.sh`. The container plan (which service, which IP,
which limits) is at the top of `scripts/deployment/deploy-services.sh`.
