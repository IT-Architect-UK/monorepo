# Backup & Recovery

Backups are only valuable if you can restore from them. This section covers backup solutions for on-premises servers and all three cloud providers, plus disaster recovery planning.

## 📁 Folder Structure

```
backup/
├── on-premises/
│   ├── restic/                  # Restic — encrypted, deduplicated backup
│   │   ├── install-restic.sh        # Install Restic
│   │   ├── backup-to-local.sh       # Back up to local disk/NAS
│   │   └── backup-to-s3.sh          # Back up to AWS S3 / Backblaze B2
│   └── veeam-agent/
│       └── install-veeam-agent-linux.sh  # Veeam Agent for Linux (free)
└── cloud/
    ├── aws/
    │   └── aws-backup-setup.sh      # AWS Backup centralised policy
    ├── azure/                        # Azure Backup (see below)
    └── gcp/                          # GCP Backup (see below)
```

## 🚀 Quick Start

### Self-hosted server → Local disk
```bash
# Install Restic
sudo ./on-premises/restic/install-restic.sh

# Configure daily backup to an external drive
sudo ./on-premises/restic/backup-to-local.sh \
    --repo /mnt/external/backups \
    --password "USE_A_STRONG_PASSPHRASE"
```

### Self-hosted server → S3 (off-site)
```bash
sudo ./on-premises/restic/backup-to-s3.sh \
    --bucket my-backup-bucket \
    --region eu-west-2 \
    --access-key AKIAEXAMPLE \
    --secret-key mysecretkey \
    --password "USE_A_STRONG_PASSPHRASE"
```

### AWS EC2
```bash
# Tag instances you want to back up, then set up the policy
./cloud/aws/aws-backup-setup.sh --region eu-west-2

# Tag an instance
aws ec2 create-tags --resources i-1234567890abcdef0 --tags Key=Backup,Value=true
```

## ☁️ Cloud Backup Comparison

| Feature | Restic (self-hosted) | AWS Backup | Azure Backup | GCP Backup |
|---------|---------------------|------------|--------------|------------|
| Cost | Storage cost only | Pay per backup | Pay per backup | Pay per backup |
| Encryption | ✅ Always on | ✅ | ✅ | ✅ |
| Deduplication | ✅ | ❌ (full snapshots) | ❌ | ❌ |
| Cross-region | Manual | ✅ (copy job) | ✅ | ✅ |
| Restore test | Manual | ✅ | ✅ | ✅ |
| DB-aware backup | ❌ | ✅ (RDS, DynamoDB) | ✅ (SQL, Cosmos) | ✅ (Cloud SQL) |

## ⚠️ The 3-2-1 Backup Rule

Always follow this rule for important data:
- **3** copies of your data
- **2** different storage types (e.g., local disk + cloud)
- **1** copy off-site (another location or cloud)

## 🔥 Disaster Recovery Checklist

Before any incident, document these:
1. **RTO** (Recovery Time Objective) — how long can you be down?
2. **RPO** (Recovery Point Objective) — how much data loss is acceptable?
3. **Backup schedule** — does it meet your RPO?
4. **Test restores** — when did you last actually restore from backup?
5. **Runbook** — can someone else restore without you?

## 🧪 Testing Your Backups

```bash
# Restic — verify repository integrity
restic -r /mnt/backup/myrepo check

# Restic — list snapshots
restic -r /mnt/backup/myrepo snapshots

# Restic — restore a file to /tmp/restore
restic -r /mnt/backup/myrepo restore latest --target /tmp/restore --include /etc/nginx

# AWS — restore a recovery point
aws backup start-restore-job \
    --recovery-point-arn <ARN> \
    --metadata '{"InstanceId":"i-NEW"}' \
    --iam-role-arn <ROLE_ARN> \
    --resource-type EC2
```
