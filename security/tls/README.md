# TLS Certificates — On-Premises & Cloud

TLS (Transport Layer Security) encrypts traffic between clients and servers. This section covers obtaining, deploying, and managing certificates across self-hosted infrastructure and all three major cloud providers.

## 📋 TLS Basics

A TLS certificate does two things:
1. **Encrypts traffic** — data is unreadable to anyone intercepting it
2. **Proves identity** — confirms you are who you say you are (via a trusted CA)

Without TLS: browsers show "Not Secure", some browser APIs are blocked, and data is sent in plaintext.

## 📁 Folder Structure

```
tls/
├── letsencrypt/           # Free certificates from Let's Encrypt
│   ├── install-certbot-nginx.sh    # Get cert + configure Nginx
│   ├── install-certbot-apache.sh   # Get cert + configure Apache
│   └── setup-auto-renewal.sh       # Verify and fix auto-renewal
│
├── deploy/                # Deploy an existing certificate
│   ├── deploy-cert-to-nginx.sh          # Any cert → Nginx
│   └── deploy-cert-to-windows-iis.ps1  # PFX/PEM → Windows IIS
│
└── cloud/                 # Cloud-native certificate services
    ├── aws-acm-request-cert.sh     # AWS Certificate Manager
    ├── azure-keyvault-cert.sh      # Azure Key Vault
    └── gcp-certificate-manager.sh  # GCP Certificate Manager
```

## 🚀 Quick Start by Scenario

### "I have a public website on Ubuntu + Nginx"
```bash
sudo ./letsencrypt/install-certbot-nginx.sh -d example.com -e you@example.com
```

### "I'm using Apache instead of Nginx"
```bash
sudo ./letsencrypt/install-certbot-apache.sh -d example.com -e you@example.com
```

### "I have a certificate file and want to configure Nginx manually"
```bash
sudo ./deploy/deploy-cert-to-nginx.sh -d example.com -c fullchain.pem -k privkey.pem
```

### "I need HTTPS on Windows IIS"
```powershell
.\deploy\deploy-cert-to-windows-iis.ps1 -CertPath cert.pfx -PfxPassword "pass" -Hostname example.com
```

### "My site is behind an AWS Load Balancer"
```bash
./cloud/aws-acm-request-cert.sh -d example.com -r us-east-1
# Then attach the ARN to your ALB listener
```

### "I'm using Azure App Service"
```bash
./cloud/azure-keyvault-cert.sh -v mykeyvault -n example-com --import --cert=fullchain.pem --key=privkey.pem
```

### "I'm using GCP Load Balancing"
```bash
./cloud/gcp-certificate-manager.sh -n my-cert -d example.com -p my-gcp-project
```

## ☁️ Provider Comparison

| Feature | Let's Encrypt | AWS ACM | Azure Key Vault | GCP Cert Manager |
|---------|--------------|---------|-----------------|-----------------|
| Cost | Free | Free (for AWS services) | ~$3/month per cert | Free |
| Self-hosted servers | ✅ | ❌ | ✅ (import) | ✅ (import) |
| Load balancers | ✅ (via Nginx proxy) | ✅ native | ✅ native | ✅ native |
| Auto-renewal | ✅ (Certbot timer) | ✅ | ✅ | ✅ |
| Wildcard certs | ✅ (DNS challenge) | ✅ | ✅ | ✅ |
| Private/internal | ❌ | ❌ | ✅ (self-signed) | ❌ |

## ❓ Troubleshooting

**Certbot challenge fails?**
→ Ensure port 80 is open to the internet (HTTP challenge).
→ Confirm DNS A record points to this server's IP.

**Certificate works but browser still shows warning?**
→ Ensure you're using `fullchain.pem` not just `cert.pem`. The chain includes intermediate certificates browsers need.

**ACM certificate stuck "Pending validation"?**
→ Add the DNS CNAME records shown in the ACM console. Check with: `dig CNAME _abc123.example.com`

**"Certificate not trusted" for internal/lab use?**
→ Let's Encrypt only works for public domains. For internal use, create an internal CA (see `/security/internal-ca/`) or use a self-signed cert.
