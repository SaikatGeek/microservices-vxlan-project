# Catalog Service (`catalog-nginx`)

Returns a short sample product list: id, name, price and whether it is in stock.

## At a glance

| | |
|---|---|
| Port | `8081` |
| Health check | `GET /health` → `ok` |
| Through a gateway | `http://<gateway>/catalog/` |
| Memory limit / reservation | 128 MB / 64 MB |
| CPU limit | 0.25 |

## Where it runs

| Datacenter | Container | IP | Role |
|---|---|---|---|
| DC1 | `dc1-catalog-nginx` | `10.20.2.11` | primary |
| DC3 | `dc3-catalog-nginx` | `10.40.2.11` | standby |

## Example reply

From `dc1-catalog-nginx`:

```json
{
  "service": "catalog-nginx",
  "status": "up",
  "datacenter": "DC1",
  "port": 8081,
  "products": [
    { "id": 101, "name": "Wireless Mouse", "price": 19.99, "in_stock": true },
    { "id": 102, "name": "USB-C Cable", "price": 9.49, "in_stock": true },
    { "id": 103, "name": "Laptop Stand", "price": 34.00, "in_stock": false }
  ]
}
```

The datacenter name is filled in when the container starts, from `-e DC=...`.
The same image gives a different name when it runs in another datacenter.

## Try it

From the lab container, through node 1:

```bash
bash scripts/remote.sh 1 curl -s http://10.20.2.11:8081/
bash scripts/remote.sh 1 curl -s http://10.20.2.11:8081/health
```

## Files

| File | Purpose |
|---|---|
| `dockerfiles/Dockerfile.catalog-nginx` | builds the image |
| `configs/nginx/catalog-nginx.conf` | port, reply and `/health` |
| `data/service-responses/catalog-nginx/index.json` | the reply |
| `configs/nginx/40-set-dc.sh` | puts the datacenter name into the reply at start |
