# Screenshots to capture

Take these in the lab, save them in this folder with exactly these names,
and the documents will pick them up. Each one is already linked from a document.

Tip: make the terminal wide before you run the command, so lines do not wrap.

| # | File name | Run this | What must be visible |
|---|---|---|---|
| 1 | `01-provision.png` | `bash scripts/infrastructure/provision.sh` | The summary box at the end: VPC, subnets, IGW, SG, and the three nodes with public and private IPs |
| 2 | `02-validate-infrastructure.png` | `make validate-infrastructure` | The final box: `local checks ... 0 fail`, `remote checks: 0 fail`, `all good` |
| 3 | `03-overlay-up-node1.png` | `make setup-vxlan-mesh` (node 1 part) | Node 1 output: the three `--- dc ---` blocks and the `peers per tunnel` list |
| 4 | `04-show-network-status.png` | `make show-network-status` | For one node: three vxlan links, three bridges with addresses, six fdb lines |
| 5 | `05-test-connectivity.png` | `make test-connectivity` | At least one node's block with every line PASS and `result: ... 0 fail` |
| 6 | `06-deploy-services.png` | `make deploy-services` | The `run` lines for a DC: container name, IP, memory, CPU |
| 7 | `07-health-check.png` | `make health-check` | All three DC tables, every container `running (healthy)` |
| 8 | `08-test-services.png` | `make test-services` | One DC's results, all PASS |
| 9 | `09-test-cross-dc.png` | `make test-cross-dc` | The gateway routes with `served by` and DC, and the container-to-container checks |
| 10 | `10-test-failover.png` | `make test-failover` | All three steps: DC1 answers, DC3 takes over, DC1 returns |
| 11 | `11-load-test.png` | `make load-test` | Requests, success, failed, per second, and the split between DC1 and DC2 |
| 12 | `12-tcpdump-vxlan.png` | on any node: `sudo tcpdump -ni any udp port 4789` while `make test-cross-dc` runs in another terminal | Lines showing `VXLAN, flags [I], vni 200/300/400` with the inner 10.x.x.x addresses |
| 13 | `13-routing-table.png` | `make show-routing-table` | One node's routes, including the three `10.20/30/40.0.0/16 ... proto kernel` lines |
