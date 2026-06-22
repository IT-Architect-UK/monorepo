# Monitoring — Self-Hosted & Cloud

Know when things break before your users do. This section covers monitoring for self-hosted servers and all three cloud providers.

## 📁 Folder Structure

```
monitoring/
├── uptime-kuma/           # Self-hosted uptime monitoring
│   └── install-uptime-kuma-docker.sh
└── cloud/
    ├── aws/
    │   └── setup-cloudwatch-agent.sh    # AWS CloudWatch Agent
    ├── azure/
    │   └── setup-azure-monitor-agent.sh # Azure Monitor / Log Analytics
    └── gcp/
        └── setup-gcp-ops-agent.sh       # GCP Ops Agent
```

## 🚀 Quick Start

### Self-Hosted: Uptime Kuma (home lab / any server)
```bash
# Basic install — access on port 3001
sudo ./uptime-kuma/install-uptime-kuma-docker.sh

# With HTTPS (recommended for production)
sudo ./uptime-kuma/install-uptime-kuma-docker.sh --with-nginx --domain monitor.example.com --email admin@example.com
```

### AWS EC2
```bash
sudo ./cloud/aws/setup-cloudwatch-agent.sh
# Optionally ship logs too:
sudo ./cloud/aws/setup-cloudwatch-agent.sh --log-group /myapp/access --log-file /var/log/nginx/access.log
```

### Azure VM
```bash
sudo ./cloud/azure/setup-azure-monitor-agent.sh \
    --workspace-id "YOUR_WORKSPACE_ID" \
    --workspace-key "YOUR_WORKSPACE_KEY"
```

### GCP Compute Engine
```bash
sudo ./cloud/gcp/setup-gcp-ops-agent.sh
```

## ☁️ Provider Comparison

| Feature | Uptime Kuma | AWS CloudWatch | Azure Monitor | GCP Ops Agent |
|---------|------------|----------------|---------------|---------------|
| Cost | Free (self-hosted) | Pay per metric | Free tier, then pay | Free tier, then pay |
| HTTP uptime checks | ✅ | ✅ (Route 53 Health Checks) | ✅ | ✅ |
| Memory metrics | ✅ (on same host) | ✅ (requires agent) | ✅ (requires agent) | ✅ |
| Log shipping | ❌ | ✅ | ✅ | ✅ |
| Alerting (Slack, email) | ✅ (90+ integrations) | ✅ (SNS) | ✅ (Action Groups) | ✅ (Alerting Policies) |
| Dashboard | ✅ (built-in) | ✅ (CloudWatch) | ✅ (Azure Monitor Workbooks) | ✅ (Cloud Monitoring) |

## 🔗 Connecting Monitoring to Alerting

All three cloud providers support sending alerts to external channels:

**AWS → Slack:**
```bash
aws sns create-topic --name alerts
# Subscribe your Slack webhook via Lambda or SNS HTTP subscription
```

**Azure → Email:**
```bash
az monitor action-group create --name "email-alerts" --resource-group myRG \
    --action email admin admin@example.com
```

**GCP → Email/PagerDuty:**
```bash
gcloud alpha monitoring channels create \
    --display-name="Email" --type=email \
    --channel-labels=email_address=admin@example.com
```
