#!/usr/bin/env bash
# hysteria2-autosetup-ubuntu
# Ubuntu 22.04+ LTS (amd64) Hysteria2 automated server setup
#
# Prerequisites:
#   1. Domain with A/AAAA record pointing to your VPS IP
#   2. Ports 80/TCP (ACME), 443/TCP+UDP (Hysteria) must be open
#
# Usage:
#   Local:
#     curl -fsSL https://raw.githubusercontent.com/kryuchenko/hysteria2-autosetup-ubuntu/refs/heads/main/setup.sh | sudo bash -s yourdomain.com admin@example.com
#   Via SSH:
#     ssh your-server 'curl -fsSL https://raw.githubusercontent.com/kryuchenko/hysteria2-autosetup-ubuntu/refs/heads/main/setup.sh | sudo bash -s yourdomain.com admin@example.com'
#   Get connection URI:
#     cat /etc/hysteria/client-uri.txt
#
# Arguments:
#   yourdomain.com   - Your domain name (must resolve to this server)
#   admin@example.com - Email for Let's Encrypt notifications
#
# Firewall (UFW):
#   Script automatically opens: 22/tcp (SSH), 80/tcp, 443/tcp, 443/udp
#
# Features:
# - Salamander obfs + ACME TLS + masquerade proxy (443/UDP+TCP)
# - Auto-generated random passwords
# - Client URI saved to /etc/hysteria/client-uri.txt
#
set -euo pipefail

must_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Please run as root: sudo $0" >&2
    exit 1
  fi
}

is_ubuntu_supported() {
  . /etc/os-release || true
  if [[ "${NAME:-}" == "Ubuntu" ]]; then
    local version="${VERSION_ID:-0}"
    # Check version >= 22.04
    if [[ $(echo "$version >= 22.04" | bc -l 2>/dev/null || echo "0") -eq 1 ]]; then
      return 0
    fi
  fi
  return 1
}

install_prereqs() {
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    curl ca-certificates ufw jq python3 dnsutils bc
}

install_hysteria_binary() {
  if ! command -v hysteria >/dev/null 2>&1; then
    # Official installer: installs binary and systemd service
    bash <(curl -fsSL https://get.hy2.sh/)
    # Update PATH after installation
    export PATH="/usr/local/bin:$PATH"
  fi
  # Verify installation via direct path
  if ! command -v hysteria >/dev/null 2>&1 && [ ! -x /usr/local/bin/hysteria ]; then
    echo "hysteria not found after install" >&2
    exit 1
  fi
}

ensure_dirs() {
  mkdir -p /etc/hysteria
  chmod 755 /etc/hysteria
}

check_port_open() {
  local port="$1" proto="$2"
  # Check if UFW rule exists
  if ufw status | grep -qE "${port}/${proto}.*ALLOW"; then
    return 0
  else
    return 1
  fi
}

ufw_server_rules() {
  local log_file="/etc/hysteria/firewall-setup.log"
  echo "=== Firewall setup log $(date) ===" > "$log_file"

  # Allow SSH first to prevent losing access
  ufw allow 22/tcp 2>&1 | tee -a "$log_file" || true

  # Allow ACME and Hysteria traffic (443/udp+tcp)
  ufw allow 80/tcp 2>&1 | tee -a "$log_file" || true
  ufw allow 443/tcp 2>&1 | tee -a "$log_file" || true
  ufw allow 443/udp 2>&1 | tee -a "$log_file" || true

  if ufw status | grep -q "Status: inactive"; then
    ufw --force enable 2>&1 | tee -a "$log_file"
  fi

  # Verify results
  echo "" >> "$log_file"
  echo "=== Port check results ===" >> "$log_file"

  local all_ok=true
  for port_proto in "80/tcp" "443/tcp" "443/udp"; do
    local port="${port_proto%/*}"
    local proto="${port_proto#*/}"
    if check_port_open "$port" "$proto"; then
      echo "✓ Port ${port_proto} is OPEN" >> "$log_file"
    else
      echo "✗ Port ${port_proto} FAILED to open" >> "$log_file"
      all_ok=false
    fi
  done

  if [ "$all_ok" = false ]; then
    echo "" >> "$log_file"
    echo "WARNING: Some ports failed to open. Check firewall rules manually:" >> "$log_file"
    echo "  sudo ufw status verbose" >> "$log_file"
    echo ""
    echo "⚠️  WARNING: Some ports failed to open!"
    echo "    Check log: cat /etc/hysteria/firewall-setup.log"
  fi

  chmod 600 "$log_file"
}

write_server_config() {
  local domain="$1" email="$2" obfs_pass="$3" auth_pass="$4" masquerade_url="$5"

  if [[ -n "$domain" && -n "$email" ]]; then
    # ACME mode with Let's Encrypt
    cat >/etc/hysteria/config.yaml <<YAML
listen: :443

acme:
  domains:
    - ${domain}
  email: ${email}

# Maximum obfuscation with Salamander
obfs:
  type: salamander
  salamander:
    password: "${obfs_pass}"

auth:
  type: password
  password: "${auth_pass}"

# Masquerade as regular website
masquerade:
  type: proxy
  proxy:
    url: ${masquerade_url}
    rewriteHost: true
YAML
  else
    # Self-signed certificate mode
    cat >/etc/hysteria/config.yaml <<YAML
listen: :443

tls:
  cert: /etc/hysteria/cert.pem
  key: /etc/hysteria/key.pem

# Maximum obfuscation with Salamander
obfs:
  type: salamander
  salamander:
    password: "${obfs_pass}"

auth:
  type: password
  password: "${auth_pass}"

# Masquerade as regular website
masquerade:
  type: proxy
  proxy:
    url: ${masquerade_url}
    rewriteHost: true
YAML
  fi

  chmod 640 /etc/hysteria/config.yaml
  chown hysteria:hysteria /etc/hysteria/config.yaml
}

enable_server_service() {
  systemctl enable --now hysteria-server.service
  systemctl --no-pager -l status hysteria-server.service || true
  echo
  echo "Server logs: journalctl -u hysteria-server.service -e --no-pager"
}

# ------------ Server Setup ------------
generate_random_password() {
  # Generate 16-byte random password, base64url encoded
  python3 -c "import secrets, base64; print(base64.urlsafe_b64encode(secrets.token_bytes(16)).decode().rstrip('='))"
}

check_dns_resolution() {
  local domain="$1"
  echo "Checking DNS resolution for ${domain}..."

  # Get server public IP
  local server_ip
  server_ip=$(curl -s -4 ifconfig.me || curl -s -4 icanhazip.com || echo "")

  if [[ -z "$server_ip" ]]; then
    echo "⚠️  Warning: Could not determine server IP address"
    return 0
  fi

  # Check if domain resolves
  local resolved_ip
  resolved_ip=$(dig +short "$domain" A | head -1 || echo "")

  if [[ -z "$resolved_ip" ]]; then
    echo "⚠️  Warning: Domain ${domain} does not resolve to any IP"
    echo "   Make sure your DNS A/AAAA record is configured"
    return 0
  fi

  if [[ "$resolved_ip" != "$server_ip" ]]; then
    echo "⚠️  Warning: Domain ${domain} resolves to ${resolved_ip}"
    echo "   But server IP is ${server_ip}"
    echo "   ACME validation may fail!"
    return 0
  fi

  echo "✓ DNS check passed: ${domain} → ${server_ip}"
}

menu_server() {
  local domain="$1" email="$2"

  echo "== SERVER setup (automated) =="
  echo "Domain: ${domain}"
  echo "Email: ${email}"
  echo

  # Check DNS before proceeding
  check_dns_resolution "$domain"
  echo

  # Generate random passwords
  local obfs_pass auth_pass
  obfs_pass="$(generate_random_password)"
  auth_pass="$(generate_random_password)"
  local masquerade_url="https://www.google.com"

  echo "Generating random passwords..."

  install_hysteria_binary
  ensure_dirs
  write_server_config "$domain" "$email" "$obfs_pass" "$auth_pass" "$masquerade_url"
  ufw_server_rules
  enable_server_service

  # Wait for service to start and ACME certificate to be obtained
  echo
  echo "Waiting for ACME certificate (this may take 10-30 seconds)..."
  sleep 15

  # Check service status
  if systemctl is-active --quiet hysteria-server.service; then
    echo "✓ Hysteria server is running"
  else
    echo "⚠️  Warning: Hysteria server may have issues. Check logs:"
    echo "   journalctl -u hysteria-server.service -e --no-pager"
  fi

  local uri="hysteria2://${auth_pass}@${domain}:443/?obfs=salamander&obfs-password=${obfs_pass}&sni=${domain}"

  # Save URI to file
  echo "$uri" > /etc/hysteria/client-uri.txt
  chmod 600 /etc/hysteria/client-uri.txt

  echo
  echo "=== Setup complete! ==="
  echo "Client URI saved to: /etc/hysteria/client-uri.txt"
  echo
  echo "Content:"
  echo "$uri"
  echo
  echo "Logs:"
  echo "  Server: journalctl -u hysteria-server.service -e --no-pager"
  echo "  Firewall: cat /etc/hysteria/firewall-setup.log"
}

# ---------- Entry ----------
must_root

# Check Ubuntu version
if ! is_ubuntu_supported; then
  echo "⚠️  WARNING: This script is designed for Ubuntu 22.04 or later" >&2
  echo "Current system: $(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")" >&2
  echo "Proceeding anyway at your own risk..." >&2
  echo ""
  sleep 3
fi

# Require domain and email arguments
if [[ -z "${1:-}" || -z "${2:-}" ]]; then
  echo "Usage: $0 <domain> <email>" >&2
  echo "Example: $0 yourdomain.com admin@example.com" >&2
  exit 1
fi

install_prereqs
menu_server "$1" "$2"
