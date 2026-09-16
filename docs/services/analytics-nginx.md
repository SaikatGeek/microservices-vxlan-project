# Analytics Service (`analytics-nginx`)

Returns sample analytics: visits and orders for the last 7 days, and the top product ids.

## At a glance

| | |
|---|---|
| Port | `8085` |
| Health check | `GET /health` → `ok` |
| Through a gateway | `http://<gateway>/analytics/` |
| Memory limit / reservation | 128 MB / 64 MB |
| CPU limit | 0.25 |

## Where it runs

| Datacenter | Container | IP | Role |
|---|---|---|---|
| DC3 | `dc3-analytics-nginx` | `10.40.2.15` | primary |

## No backup

Analytics runs only in DC3, as the task describes. If `dc3-analytics-nginx` is down, `/analytics/` returns `502 Bad Gateway` from every gateway.

## Example reply

From `dc3-analytics-nginx`:

```json
{
  "service": "analytics-nginx",
  "status": "up",
  "datacenter": "DC3",
  "port": 8085,
  "last_7_days": {
    "visits": [410, 385, 502, 467, 530, 610, 575],
    "orders": [38, 35, 47, 44, 51, 60, 57]
  },
  "top_products": [101, 102]
}
```

The datacenter name is filled in when the container starts, from `-e DC=...`.
The same image gives a different name when it runs in another datacenter.

## Try it

From the lab container, through node 3:

```bash
bash scripts/remote.sh 3 curl -s http://10.40.2.15:8085/
bash scripts/remote.sh 3 curl -s http://10.40.2.15:8085/health
```

## Files

| File | Purpose |
|---|---|
| `dockerfiles/Dockerfile.analytics-nginx` | builds the image |
| `configs/nginx/analytics-nginx.conf` | port, reply and `/health` |
| `data/service-responses/analytics-nginx/index.json` | the reply |
| `configs/nginx/40-set-dc.sh` | puts the datacenter name into the reply at start |
