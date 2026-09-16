# Notification Service (`notify-nginx`)

Reports the status of the notification service, the channels it uses, and how many messages are queued.

## At a glance

| | |
|---|---|
| Port | `8084` |
| Health check | `GET /health` → `ok` |
| Through a gateway | `http://<gateway>/notify/` |
| Memory limit / reservation | 128 MB / 64 MB |
| CPU limit | 0.25 |

## Where it runs

| Datacenter | Container | IP | Role |
|---|---|---|---|
| DC2 | `dc2-notify-nginx` | `10.30.2.11` | primary |
| DC3 | `dc3-notify-nginx` | `10.40.2.14` | standby |

## Example reply

From `dc2-notify-nginx`:

```json
{
  "service": "notify-nginx",
  "status": "up",
  "datacenter": "DC2",
  "port": 8084,
  "channels": ["email", "sms"],
  "queued": 12
}
```

The datacenter name is filled in when the container starts, from `-e DC=...`.
The same image gives a different name when it runs in another datacenter.

## Try it

From the lab container, through node 2:

```bash
bash scripts/remote.sh 2 curl -s http://10.30.2.11:8084/
bash scripts/remote.sh 2 curl -s http://10.30.2.11:8084/health
```

## Files

| File | Purpose |
|---|---|
| `dockerfiles/Dockerfile.notify-nginx` | builds the image |
| `configs/nginx/notify-nginx.conf` | port, reply and `/health` |
| `data/service-responses/notify-nginx/index.json` | the reply |
| `configs/nginx/40-set-dc.sh` | puts the datacenter name into the reply at start |
