# Payment Service (`payment-nginx`)

Reports the status of the payment service, with payments processed and failed today.

## At a glance

| | |
|---|---|
| Port | `8083` |
| Health check | `GET /health` → `ok` |
| Through a gateway | `http://<gateway>/payments/` |
| Memory limit / reservation | 128 MB / 64 MB |
| CPU limit | 0.25 |

## Where it runs

| Datacenter | Container | IP | Role |
|---|---|---|---|
| DC2 | `dc2-payment-nginx` | `10.30.2.10` | primary |
| DC3 | `dc3-payment-nginx` | `10.40.2.13` | standby |

## Example reply

From `dc2-payment-nginx`:

```json
{
  "service": "payment-nginx",
  "status": "up",
  "datacenter": "DC2",
  "port": 8083,
  "payments": {
    "processed_today": 204,
    "failed_today": 3
  }
}
```

The datacenter name is filled in when the container starts, from `-e DC=...`.
The same image gives a different name when it runs in another datacenter.

## Try it

From the lab container, through node 2:

```bash
bash scripts/remote.sh 2 curl -s http://10.30.2.10:8083/
bash scripts/remote.sh 2 curl -s http://10.30.2.10:8083/health
```

## Files

| File | Purpose |
|---|---|
| `dockerfiles/Dockerfile.payment-nginx` | builds the image |
| `configs/nginx/payment-nginx.conf` | port, reply and `/health` |
| `data/service-responses/payment-nginx/index.json` | the reply |
| `configs/nginx/40-set-dc.sh` | puts the datacenter name into the reply at start |
