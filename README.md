# hysteria2-autosetup-ubuntu24

Automated Hysteria2 server setup script for Ubuntu 24.04 LTS (amd64).

## Features

- 🔐 **Salamander obfuscation** - Maximum traffic obfuscation
- 🔒 **ACME TLS** - Automatic Let's Encrypt certificates
- 🎭 **Masquerade proxy** - Disguises as regular HTTPS traffic
- 🔑 **Auto-generated passwords** - Secure random credentials
- 📋 **Client URI export** - Easy client configuration

## Prerequisites

1. Ubuntu 24.04 LTS (amd64) VPS
2. Domain with A/AAAA record pointing to your server IP
3. Ports must be accessible: 80/TCP (ACME), 443/TCP+UDP (Hysteria)

## Usage

```bash
sudo ./setup.sh yourdomain.com admin@example.com
```

### Arguments

- `yourdomain.com` - Your domain name (must resolve to this server)
- `admin@example.com` - Email for Let's Encrypt notifications

### Get Client URI

After installation, retrieve the connection URI:

```bash
cat /etc/hysteria/client-uri.txt
```

The URI format: `hysteria2://password@domain:443/?obfs=salamander&obfs-password=xxx&sni=domain`

## What the script does

1. Installs Hysteria2 binary and dependencies
2. Generates random passwords for authentication and obfuscation
3. Configures ACME for automatic TLS certificates
4. Sets up UFW firewall rules (80/tcp, 443/tcp, 443/udp)
5. Enables and starts Hysteria2 server service
6. Saves client connection URI to `/etc/hysteria/client-uri.txt`

## Logs

- **Server logs**: `journalctl -u hysteria-server.service -e --no-pager`
- **Firewall setup**: `cat /etc/hysteria/firewall-setup.log`
- **Configuration**: `/etc/hysteria/config.yaml`

## Security

- All passwords are randomly generated (16-byte base64url)
- TLS certificates from Let's Encrypt
- Traffic masqueraded as regular HTTPS (proxies to google.com)
- Salamander obfuscation for maximum DPI resistance

## License

GPL-3.0
