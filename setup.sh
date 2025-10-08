#!/usr/bin/env bash
# hysteria2-autosetup-ubuntu24
# Ubuntu 24.04 LTS (amd64) Hysteria2 automated server setup
#
# Prerequisites:
#   1. Domain with A/AAAA record pointing to your VPS IP
#   2. Ports 80/TCP (ACME), 443/TCP+UDP (Hysteria) must be open
#
# Usage:
#   sudo ./setup.sh yourdomain.com admin@example.com
#   cat /etc/hysteria/client-uri.txt  # Get hysteria2:// URI
#
# Arguments:
#   yourdomain.com   - Your domain name (must resolve to this server)
#   admin@example.com - Email for Let's Encrypt notifications
#
# Firewall (UFW):
#   Script automatically opens: 80/tcp, 443/tcp, 443/udp
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

is_ubuntu_24() {
  . /etc/os-release || true
  [[ "${NAME:-}" == "Ubuntu" && "${VERSION_ID:-}" == "24.04" ]]
}

install_prereqs() {
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    curl ca-certificates ufw jq python3
}

install_hysteria_binary() {
  if ! command -v hysteria >/dev/null 2>&1; then
    # Официальный инсталлятор: ставит бинарь и службу
    bash <(curl -fsSL https://get.hy2.sh/)
    # Обновляем PATH после установки
    export PATH="/usr/local/bin:$PATH"
  fi
  # Проверяем установку через прямой путь
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
  # Проверяем есть ли правило в UFW
  if ufw status | grep -qE "${port}/${proto}.*ALLOW"; then
    return 0
  else
    return 1
  fi
}

ufw_server_rules() {
  local log_file="/etc/hysteria/firewall-setup.log"
  echo "=== Firewall setup log $(date) ===" > "$log_file"

  # Разрешаем ACME и трафик 443/udp+tcp; включаем UFW, если он был выключен
  ufw --force allow 80/tcp 2>&1 | tee -a "$log_file" || true
  ufw --force allow 443/tcp 2>&1 | tee -a "$log_file" || true
  ufw --force allow 443/udp 2>&1 | tee -a "$log_file" || true

  if ufw status | grep -q "Status: inactive"; then
    ufw --force enable 2>&1 | tee -a "$log_file"
  fi

  # Проверка результатов
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
  cat >/etc/hysteria/config.yaml <<YAML
listen: :443

acme:
  domains:
    - ${domain}
  email: ${email}

# Максимальная обфускация Salamander
obfs:
  type: salamander
  salamander:
    password: "${obfs_pass}"

auth:
  type: password
  password: "${auth_pass}"

# Маскарад под обычный сайт
masquerade:
  type: proxy
  proxy:
    url: ${masquerade_url}
    rewriteHost: true
YAML
  chmod 640 /etc/hysteria/config.yaml
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

menu_server() {
  local domain="$1" email="$2"

  # Generate random passwords
  local obfs_pass auth_pass
  obfs_pass="$(generate_random_password)"
  auth_pass="$(generate_random_password)"
  local masquerade_url="https://www.google.com"

  echo "== SERVER setup (automated) =="
  echo "Domain: ${domain}"
  echo "Email: ${email}"
  echo "Generating random passwords..."

  install_hysteria_binary
  ensure_dirs
  write_server_config "$domain" "$email" "$obfs_pass" "$auth_pass" "$masquerade_url"
  ufw_server_rules
  enable_server_service

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
}

# ---------- Entry ----------
must_root
if ! is_ubuntu_24; then
  echo "Warning: script is tested for Ubuntu 24.04, continuing anyway..." >&2
fi

# Require domain and email arguments
if [[ -z "${1:-}" || -z "${2:-}" ]]; then
  echo "Usage: $0 <domain> <email>" >&2
  echo "Example: $0 yourdomain.com admin@example.com" >&2
  exit 1
fi

install_prereqs
menu_server "$1" "$2"
