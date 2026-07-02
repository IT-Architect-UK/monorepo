# Security

PKI, TLS certificate lifecycle, secrets management, and compliance reporting.

| Directory | Purpose | Docs |
|-----------|---------|------|
| `tls/` | Certificate issue, deploy, and renewal — Let's Encrypt, cloud CAs, Nginx/Apache/IIS | [tls/README.md](tls/README.md) |
| `vault/` | HashiCorp Vault server install and operation | [vault/README.md](vault/README.md) |
| `pki/` | Private OpenSSL CA — root and subordinate certificates | see below |
| `compliance/` | Compliance reporting | see below |

## PKI — `pki/`

| Script | Purpose |
|--------|---------|
| `create-openssl-root-cert.sh` | Create a self-signed root CA (4096-bit RSA, 10-year cert) |
| `openssl-sign-sub-ca.sh` | Sign a subordinate CA with the root |

Run the root script once on a secured host, keep the root key offline, then sign subordinates as needed. Full usage in each header.

## Compliance — `compliance/`

| Script | Purpose |
|--------|---------|
| `PAM-TechSpecComplianceReport.ps1` | Generate a PAM technical-specification compliance report (PowerShell; see comment-based help) |
