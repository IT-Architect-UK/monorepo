# Python Tooling

Operational scripts for inventory, health checking, and metrics. Install dependencies first:

```bash
pip install -r requirements.txt
```

| Script | Purpose | Example |
|--------|---------|---------|
| `azure-resource-inventory.py` | Inventory all resources in an Azure subscription → CSV + console summary | `./azure-resource-inventory.py --subscription <id>` |
| `infrastructure-health-check.py` | Concurrent TCP/HTTP health checks across a host list → colour-coded table, optional JSON | `./infrastructure-health-check.py --hosts hosts.txt` |
| `prometheus-query.py` | Instant or range queries against a Prometheus API → table or JSON | `./prometheus-query.py --url http://prom:9090 --query up` |
| `test.py` | Quick environment sanity check (DNS, outbound connectivity) | `./test.py` |

Run any script with `--help` for the full argument reference; each file's docstring documents behaviour and output formats.
