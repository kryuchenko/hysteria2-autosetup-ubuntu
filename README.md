# hysteria2-autosetup-ubuntu

Automated Hysteria2 server setup script for Ubuntu 22.04+ LTS (amd64).

## Quick Start

**Prerequisites:** Ubuntu 22.04+ VPS with a domain pointing to your server IP.

Run directly from GitHub:

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/kryuchenko/hysteria2-autosetup-ubuntu24/refs/heads/main/setup.sh) yourdomain.com admin@example.com
```

Replace:
- `yourdomain.com` - Your domain name (must resolve to your server)
- `admin@example.com` - Your email for Let's Encrypt notifications

After installation, get your connection URI:

```bash
cat /etc/hysteria/client-uri.txt
```

That's it! Use the URI in your Hysteria2 client.

---

## Features

- 🔐 **Salamander obfuscation** - Maximum traffic obfuscation
- 🔒 **ACME TLS** - Automatic Let's Encrypt certificates
- 🎭 **Masquerade proxy** - Disguises as regular HTTPS traffic
- 🔑 **Auto-generated passwords** - Secure random credentials
- 📋 **Client URI export** - Easy client configuration
- 🛡️ **SSH protection** - Automatically preserves SSH access when enabling firewall
- 🔍 **DNS validation** - Checks domain resolution before ACME

## Detailed Prerequisites

1. Ubuntu 22.04 or later LTS (amd64) VPS
2. Domain with A/AAAA record pointing to your server IP
3. Ports must be accessible: 80/TCP (ACME), 443/TCP+UDP (Hysteria)

## What the script does

1. Validates Ubuntu version (22.04+)
2. Installs dependencies (curl, ca-certificates, ufw, jq, python3, dnsutils, bc)
3. Installs Hysteria2 binary and systemd service
4. Checks DNS resolution (domain → server IP)
5. Generates random passwords for authentication and obfuscation
6. Configures ACME for automatic TLS certificates
7. Sets up UFW firewall rules (22/tcp for SSH, 80/tcp, 443/tcp, 443/udp)
8. Enables and starts Hysteria2 server service
9. Waits for ACME certificate (10-30 seconds)
10. Verifies service status
11. Saves client connection URI to `/etc/hysteria/client-uri.txt`

## Logs and Configuration

- **Server logs**: `journalctl -u hysteria-server.service -e --no-pager`
- **Firewall setup log**: `cat /etc/hysteria/firewall-setup.log`
- **Server configuration**: `/etc/hysteria/config.yaml`
- **Client URI**: `/etc/hysteria/client-uri.txt`

## Security

- All passwords are randomly generated (16-byte base64url encoded)
- Valid TLS certificates from Let's Encrypt (auto-renewed)
- Traffic masqueraded as regular HTTPS (proxies to google.com)
- Salamander obfuscation for maximum DPI resistance
- SSH access automatically preserved when enabling firewall

## Compatibility

- **Supported**: Ubuntu 22.04 LTS, Ubuntu 24.04 LTS
- **Warning mode**: Other Ubuntu versions (proceeds at user's risk)

## License

GPL-3.0
