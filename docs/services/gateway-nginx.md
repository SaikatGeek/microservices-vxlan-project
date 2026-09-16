# Gateway (`gateway-nginx`)

The front door of each datacenter. It serves a small HTML page saying which datacenter it is in, and passes every other request to the right service. When a service is down, it sends the request to the backup copy in DC3.

## At a glance

| | |
|---|---|
| Port | `80` |
| Health check | `GET /health` → `ok` |
| Memory limit / reservation | 256 MB / 128 MB |
| CPU limit | 0.50 |

## Where it runs

| Datacenter | Container | IP | Role |
|---|---|---|---|
| DC1 | `dc1-gateway-nginx` | `10.20.1.10` | primary |
| DC2 | `dc2-gateway-nginx` | `10.30.1.10` | backup |
| DC3 | `dc3-gateway-nginx` | `10.40.1.10` | standby |

## Routes

| Path | Service | Normal servers | Backup |
|---|---|---|---|
| `/` | this page | — | — |
| `/health` | health check | — | — |
| `/users/` | user-nginx | DC1 `10.20.2.10:8080` | DC3 `10.40.2.10:8080` |
| `/catalog/` | catalog-nginx | DC1 `10.20.2.11:8081` | DC3 `10.40.2.11:8081` |
| `/orders/` | order-nginx | DC1 `10.20.2.12:8082`, DC2 `10.30.2.12:8082` | DC3 `10.40.2.12:8082` |
| `/payments/` | payment-nginx | DC2 `10.30.2.10:8083` | DC3 `10.40.2.13:8083` |
| `/notify/` | notify-nginx | DC2 `10.30.2.11:8084` | DC3 `10.40.2.14:8084` |
| `/analytics/` | analytics-nginx | DC3 `10.40.2.15:8085` | — |
| `/discovery/` | discovery-nginx | DC3 `10.40.2.16:8500` | — |

Every answer carries an `X-Served-By` header with the address that really answered. After a failover it lists every server tried, for example `10.20.2.10:8080, 10.40.2.10:8080`.

Normal servers are marked down for 10 seconds after 3 failures within 10 seconds (`max_fails=3 fail_timeout=10s`). A server that does not connect within 2 seconds is skipped and the same request goes to the next one.

The full design is in [service-architecture.md](../../architecture/service-architecture.md#the-gateway-and-load-balancing).

## Example reply

From `dc1-gateway-nginx`:

```html
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>API Gateway - DC1</title>
</head>
<body>
  <h1>API Gateway - DC1</h1>
  <p>This gateway sends each request to the right service.</p>
</body>
</html>
```

The datacenter name is filled in when the container starts, from `-e DC=...`.
The same image gives a different name when it runs in another datacenter.

## Try it

From the lab container, through node 1:

```bash
bash scripts/remote.sh 1 curl -s http://10.20.1.10:80/users/
bash scripts/remote.sh 1 curl -s http://10.20.1.10:80/health
```

## Files

| File | Purpose |
|---|---|
| `dockerfiles/Dockerfile.gateway-nginx` | builds the image |
| `configs/nginx/gateway-nginx.conf` | port, reply and `/health` |
| `data/service-responses/gateway-nginx/index.html` | the reply |
| `configs/nginx/40-set-dc.sh` | puts the datacenter name into the reply at start |
