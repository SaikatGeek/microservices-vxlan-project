# Services

One page per service.

| Service | Port | Runs in |
|---|---|---|
| [Gateway](gateway-nginx.md) | 80 | DC1, DC2, DC3 |
| [User Service](user-nginx.md) | 8080 | DC1, DC3 |
| [Catalog Service](catalog-nginx.md) | 8081 | DC1, DC3 |
| [Order Service](order-nginx.md) | 8082 | DC1, DC2, DC3 |
| [Payment Service](payment-nginx.md) | 8083 | DC2, DC3 |
| [Notification Service](notify-nginx.md) | 8084 | DC2, DC3 |
| [Analytics Service](analytics-nginx.md) | 8085 | DC3 |
| [Discovery Service](discovery-nginx.md) | 8500 | DC3 |

Each datacenter also runs `db-stub` and `cache-stub`: plain `nginx:alpine` containers on port 80 that hold the data-tier addresses (`10.x0.3.10` and `10.x0.3.11`).
