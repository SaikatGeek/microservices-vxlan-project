# Troubleshooting

Most problems in this project are silent. Nothing prints an error; packets just do
not arrive. This page lists what went wrong while building it, in the order you are
most likely to hit it.

A good first move for any network problem is to test without containers:

```bash
make test-connectivity
```

## Scripts will not start

### `Permission denied`

The script lost its executable bit, usually after a copy or upload.
Run it with `bash` in front, which does not need the bit:

```bash
bash scripts/infrastructure/verify.sh
```

The Makefile always uses `bash`, so `make` targets are not affected.

### `cannot execute: required file not found`

The file exists, but it has Windows line endings. The first line reads
`#!/bin/bash\r`, and there is no program called `bash\r`.

Check:

```bash
head -1 scripts/remote.sh | cat -A      # a ^M at the end means Windows line endings
```

Fix:

```bash
find . -name '*.sh' -exec sed -i 's/\r$//' {} +
```

`push-project.sh` does the same fix on the nodes automatically.

## AWS errors

### `UnauthorizedOperation` on `RunInstances`

The lab's IAM policy does not allow creating EC2 instances. No command change gets
past this. Use a lab that allows EC2.

### `AuthFailure` on every call

The AWS CLI still has credentials from an old lab. Run `aws configure` again with the
new keys, then `aws sts get-caller-identity`.

### `teardown.sh` stops with `DependencyViolation`

Something still uses the resource. The script retries a few times. If it still fails,
run it again. It skips what is already gone and continues.

## Node checks fail

### Many FAILs in `verify.sh`, but SSH works

On a fresh Ubuntu 24.04 node, `ping`, `tcpdump` and `docker` are not installed. The
`tools` section names each missing package. Install them with:

```bash
bash scripts/infrastructure/push-project.sh
```

### `https egress` fails, everything else passes

Check by hand on the node:

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://registry-1.docker.io/v2/
```

`401` is a good answer: the registry wants a token, so egress works. `000` means no
connection. Check the route table's `0.0.0.0/0` route and the internet gateway.

### `permission denied while trying to connect to the Docker daemon`

The user was added to the `docker` group, but the group only applies to new logins.
The scripts fall back to `sudo docker` on their own. By hand, log out and back in,
or use `sudo docker`.

## Tunnels do not work

Symptom: `make test-connectivity` fails on the `ping DCx gateway` lines.
Go down this list in order:

1. **Wrong node number.** Each node must run `overlay-up.sh` with its own number.
   The output's first lines say which node it thinks it is. A wrong number makes two
   nodes claim the same gateway address. Fix: `make cleanup-vxlan`, then
   `make setup-vxlan-mesh`.

2. **IP forwarding is off.** Without it, nothing moves between bridges.
   ```bash
   sysctl net.ipv4.ip_forward        # must print 1
   ```

3. **Firewall rules are missing.** Docker drops forwarded traffic on bridges it did
   not create. Each bridge needs a rule in both directions.
   ```bash
   sudo iptables -L DOCKER-USER -n   # br-dc1, br-dc2, br-dc3, each -i and -o
   ```
   With only one direction, the request leaves and the reply never comes back.

4. **fdb peers are missing.** Each tunnel needs one line per other node.
   ```bash
   bridge fdb show | grep 00:00:00:00:00:00    # 6 lines: 3 tunnels x 2 peers
   ```

5. **UDP 4789 is blocked** in the security group. `provision.sh` opens it for the
   whole VPC. Check it was not changed by hand.

6. **Wrong NIC name** on the VXLAN device.
   ```bash
   ip -d link show vxlan200          # 'dev' must be the real NIC, e.g. enX0
   ```

To watch whether packets leave at all:

```bash
sudo tcpdump -ni any udp port 4789
```

Remember that a reply between two datacenters comes back on a different tunnel than
the request. Watching a single `vxlanN` device shows only half the conversation, so
always use `-i any`.

## Services do not work

### A container is `unhealthy`

```bash
make show-logs
bash scripts/remote.sh 1 docker inspect --format '{{json .State.Health}}' dc1-user-nginx
```

The health check calls `http://127.0.0.1:<port>/health` inside the container. If
nginx failed to start, the log says why.

### A reply says `"datacenter": "UNKNOWN"`

The container was started without `-e DC=DCx`. Deploy with the script, which always
sets it: `make deploy-dc1-services`.

### `Network dc1-net is missing`

`deploy-services.sh` runs before the mesh. Run `make setup-vxlan-mesh` first.

### Gateway returns `502 Bad Gateway`

Every server for that route is down, including the backup. Check with
`make health-check`. The `X-Served-By` header lists what the gateway tried:

```bash
bash scripts/remote.sh 1 curl -s -D - -o /dev/null http://10.20.1.10/users/
```

### Small requests work, large replies hang

This is the MTU problem. VXLAN adds 50 bytes, so containers must use 1450.

```bash
bash scripts/remote.sh 1 docker network inspect dc1-net | grep -i mtu    # must show 1450
```

To measure it across the overlay from node 1 (1422 + 28 = 1450 must pass,
1472 + 28 = 1500 must fail with `message too long`):

```bash
bash scripts/remote.sh 1 ping -c 2 -M do -s 1422 10.40.1.10
bash scripts/remote.sh 1 ping -c 2 -M do -s 1472 10.40.1.10
```

This runs on the node, not in a container: the busybox `ping` inside the images
does not support `-M do`.

If the network shows no MTU, it was created without
`-o com.docker.network.driver.mtu=1450`. Remove the containers and the network, then
run `make setup-vxlan-mesh` and `make deploy-services` again.

## Terminal shows broken characters

Output in a language other than English can show as broken glyphs in the lab
terminal. All scripts in this project print English only for this reason.
