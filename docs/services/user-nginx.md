# User Service (`user-nginx`)

Reports the status of the user service, with a total user count and how many were active today.

## At a glance

| | |
|---|---|
| Port | `8080` |
| Health check | `GET /health` → `ok` |
| Through a gateway | `http://<gateway>/users/` |
| Memory limit / reservation | 128 MB / 64 MB |
| CPU limit | 0.25 |

## Where it runs

| Datacenter | Container | IP | Role |
|---|---|---|---|
| DC1 | `dc1-user-nginx` | `10.20.2.10` | primary |
| DC3 | `dc3-user-nginx` | `10.40.2.10` | standby |

## Failover

This is the service `make test-failover` uses. It stops `dc1-user-nginx` and checks that the DC1 gateway gets its answer from `dc3-user-nginx` instead, then starts it again and checks that traffic returns to DC1.

![Failover test](../screenshots/10-test-failover.png)

## Example reply

From `dc1-user-nginx`:

```json
{
  "service": "user-nginx",
  "status": "up",
  "datacenter": "DC1",
  "port": 8080,
  "users": {
    "total": 1250,
    "active_today": 342
  }
}
```

The datacenter name is filled in when the container starts, from `-e DC=...`.
The same image gives a different name when it runs in another datacenter.

## Try it

From the lab container, through node 1:

```bash
bash scripts/remote.sh 1 curl -s http://10.20.2.10:8080/
bash scripts/remote.sh 1 curl -s http://10.20.2.10:8080/health
```

## Files

| File | Purpose |
|---|---|
| `dockerfiles/Dockerfile.user-nginx` | builds the image |
| `configs/nginx/user-nginx.conf` | port, reply and `/health` |
| `data/service-responses/user-nginx/index.json` | the reply |
| `configs/nginx/40-set-dc.sh` | puts the datacenter name into the reply at start |
