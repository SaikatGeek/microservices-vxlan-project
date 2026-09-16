# Discovery Service (`discovery-nginx`)

Returns a list of every service: its port, and each copy with its datacenter, IP and role (primary, replica, backup, standby). Any script or service can read it to find where things run.

## At a glance

| | |
|---|---|
| Port | `8500` |
| Health check | `GET /health` → `ok` |
| Through a gateway | `http://<gateway>/discovery/` |
| Memory limit / reservation | 128 MB / 64 MB |
| CPU limit | 0.25 |

## Where it runs

| Datacenter | Container | IP | Role |
|---|---|---|---|
| DC3 | `dc3-discovery-nginx` | `10.40.2.16` | primary |

## Why a static list works

Every container in the project has a fixed IP set with `docker run --ip`. The list only changes when the IP plan changes, and then both this file (`data/service-responses/discovery-nginx/index.json`) and `scripts/deployment/deploy-services.sh` are edited together.

## Example reply

From `dc3-discovery-nginx`:

```json
{
  "service": "discovery-nginx",
  "status": "up",
  "datacenter": "DC3",
  "port": 8500,
  "note": "Static list. Every container has a fixed IP, so this list stays true.",
  "services": [
    { "name": "gateway-nginx", "port": 80, "instances": [
      { "dc": "DC1", "ip": "10.20.1.10", "role": "primary" },
      { "dc": "DC2", "ip": "10.30.1.10", "role": "backup" },
      { "dc": "DC3", "ip": "10.40.1.10", "role": "standby" } ] },
    { "name": "user-nginx", "port": 8080, "instances": [
      { "dc": "DC1", "ip": "10.20.2.10", "role": "primary" },
      { "dc": "DC3", "ip": "10.40.2.10", "role": "standby" } ] },
    { "name": "catalog-nginx", "port": 8081, "instances": [
      { "dc": "DC1", "ip": "10.20.2.11", "role": "primary" },
      { "dc": "DC3", "ip": "10.40.2.11", "role": "standby" } ] },
    { "name": "order-nginx", "port": 8082, "instances": [
      { "dc": "DC1", "ip": "10.20.2.12", "role": "primary" },
      { "dc": "DC2", "ip": "10.30.2.12", "role": "replica" },
      { "dc": "DC3", "ip": "10.40.2.12", "role": "standby" } ] },
    { "name": "payment-nginx", "port": 8083, "instances": [
      { "dc": "DC2", "ip": "10.30.2.10", "role": "primary" },
      { "dc": "DC3", "ip": "10.40.2.13", "role": "standby" } ] },
    { "name": "notify-nginx", "port": 8084, "instances": [
      { "dc": "DC2", "ip": "10.30.2.11", "role": "primary" },
      { "dc": "DC3", "ip": "10.40.2.14", "role": "standby" } ] },
    { "name": "analytics-nginx", "port": 8085, "instances": [
      { "dc": "DC3", "ip": "10.40.2.15", "role": "primary" } ] },
    { "name": "discovery-nginx", "port": 8500, "instances": [
      { "dc": "DC3", "ip": "10.40.2.16", "role": "primary" } ] }
  ]
}
```

The datacenter name is filled in when the container starts, from `-e DC=...`.
The same image gives a different name when it runs in another datacenter.

## Try it

From the lab container, through node 3:

```bash
bash scripts/remote.sh 3 curl -s http://10.40.2.16:8500/
bash scripts/remote.sh 3 curl -s http://10.40.2.16:8500/health
```

## Files

| File | Purpose |
|---|---|
| `dockerfiles/Dockerfile.discovery-nginx` | builds the image |
| `configs/nginx/discovery-nginx.conf` | port, reply and `/health` |
| `data/service-responses/discovery-nginx/index.json` | the reply |
| `configs/nginx/40-set-dc.sh` | puts the datacenter name into the reply at start |
