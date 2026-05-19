#!/bin/bash
set -euo pipefail

STATE_DIR="/var/lib/rpi-monitor"
TG="/usr/local/bin/bot-msg-snd.sh"
HOST="$(hostname)"

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

# -------------------------
# Helper: send telegram
# -------------------------
send_alert() {
  local msg="$1"
  "$TG" "⚠️ $msg"
}

# -------------------------
# (4) New users / sudo group changes
# -------------------------
PASSWD_HASH_FILE="$STATE_DIR/passwd.sha256"
GROUP_HASH_FILE="$STATE_DIR/group.sha256"
SUDOERS_HASH_FILE="$STATE_DIR/sudoers.sha256"

hash_file_check() {
  local file="$1"
  local statefile="$2"
  local label="$3"

  if [ ! -f "$file" ]; then
    return
  fi

  local newhash
  newhash="$(sha256sum "$file" | awk '{print $1}')"

  if [ ! -f "$statefile" ]; then
    echo "$newhash" > "$statefile"
    return
  fi

  local oldhash
  oldhash="$(cat "$statefile")"

  if [ "$newhash" != "$oldhash" ]; then
    echo "$newhash" > "$statefile"
    send_alert "$label changed: $file"
  fi
}

hash_file_check /etc/passwd "$PASSWD_HASH_FILE" "User database (/etc/passwd)"
hash_file_check /etc/group "$GROUP_HASH_FILE" "Group database (/etc/group)"
hash_file_check /etc/sudoers "$SUDOERS_HASH_FILE" "Sudoers file (/etc/sudoers)"

# -------------------------
# (6) New listening ports
# -------------------------
PORTS_FILE="$STATE_DIR/listening_ports.txt"

current_ports="$(ss -tulpnH | awk '{print $1,$5,$7}' | sort)"

if [ ! -f "$PORTS_FILE" ]; then
  echo "$current_ports" > "$PORTS_FILE"
else
  old_ports="$(cat "$PORTS_FILE")"
  if [ "$current_ports" != "$old_ports" ]; then
    echo "$current_ports" > "$PORTS_FILE"
    send_alert "Listening ports changed. Run: ss -tulpn"
  fi
fi

# -------------------------
# (7) Firewall status changes (UFW + nftables)
# -------------------------
FW_FILE="$STATE_DIR/firewall_status.txt"

ufw_status="ufw:not_installed"
if command -v ufw >/dev/null 2>&1; then
  ufw_status="ufw:$(ufw status | head -n1)"
fi

nft_svc="nftables:not_installed"
if systemctl list-unit-files 2>/dev/null | grep -q "^nftables.service"; then
  nft_svc="nftables:$(systemctl is-active nftables 2>/dev/null || true)"
fi

iptables_svc="iptables:not_installed"
if systemctl list-unit-files 2>/dev/null | grep -q "^iptables.service"; then
  iptables_svc="iptables:$(systemctl is-active iptables 2>/dev/null || true)"
fi

fw_now="$ufw_status | $nft_svc | $iptables_svc"

if [ ! -f "$FW_FILE" ]; then
  echo "$fw_now" > "$FW_FILE"
else
  fw_old="$(cat "$FW_FILE")"
  if [ "$fw_now" != "$fw_old" ]; then
    echo "$fw_now" > "$FW_FILE"
    send_alert "Firewall status changed: $fw_now"
  fi
fi

# -------------------------
# (8) Disk usage critical
# -------------------------
DISK_THRESHOLD=90
disk_use="$(df -P / | awk 'NR==2 {gsub("%",""); print $5}')"

DISK_ALERT_FILE="$STATE_DIR/disk_alerted"

if [ "$disk_use" -ge "$DISK_THRESHOLD" ]; then
  if [ ! -f "$DISK_ALERT_FILE" ]; then
    touch "$DISK_ALERT_FILE"
    send_alert "Disk usage critical: / is ${disk_use}% full"
  fi
else
  rm -f "$DISK_ALERT_FILE"
fi

# -------------------------
# (9) High CPU load sustained
# -------------------------
LOAD_THRESHOLD=2.50
LOAD_FILE="$STATE_DIR/load_alerted"

load_now="$(awk '{print $1}' /proc/loadavg)"

# compare floats using awk
high_load="$(awk -v l="$load_now" -v t="$LOAD_THRESHOLD" 'BEGIN{print (l>=t) ? 1 : 0}')"

if [ "$high_load" -eq 1 ]; then
  if [ ! -f "$LOAD_FILE" ]; then
    touch "$LOAD_FILE"
    send_alert "High CPU load detected: loadavg=$load_now (threshold=$LOAD_THRESHOLD)"
  fi
else
  rm -f "$LOAD_FILE"
fi

# -------------------------
# (10) apt installs / upgrades (detect dpkg log changes)
# -------------------------
DPKG_LOG="/var/log/dpkg.log"
DPKG_STATE="$STATE_DIR/dpkg_lastpos"

if [ -f "$DPKG_LOG" ]; then
  lastpos=0
  if [ -f "$DPKG_STATE" ]; then
    lastpos="$(cat "$DPKG_STATE")"
  fi

  size="$(stat -c%s "$DPKG_LOG")"

  # handle log rotation/truncate
  if [ "$size" -lt "$lastpos" ]; then
    lastpos=0
  fi

  if [ "$size" -gt "$lastpos" ]; then
    new_lines="$(tail -c +"$((lastpos+1))" "$DPKG_LOG" | grep -E " install | upgrade " || true)"

    if [ -n "$new_lines" ]; then
      # summarize last few
      summary="$(echo "$new_lines" | tail -n 5)"
      send_alert "Package install/upgrade detected: $summary"
    fi

    echo "$size" > "$DPKG_STATE"
  fi
fi

# -------------------------
# (12) fail2ban ban alerts
# -------------------------
if command -v fail2ban-client >/dev/null 2>&1; then
  F2B_STATE="$STATE_DIR/fail2ban_bans.txt"
  bans_now="$(fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/.*Jail list:\s*//' | tr ',' '\n' | sed 's/^ *//g')"

  if [ -n "$bans_now" ]; then
    ban_summary=""

    while read -r jail; do
      [ -z "$jail" ] && continue
      banned="$(fail2ban-client status "$jail" 2>/dev/null | grep "Currently banned" | awk -F: '{print $2}' | xargs)"
      ban_summary+="$jail=$banned "
    done <<< "$bans_now"

    if [ ! -f "$F2B_STATE" ]; then
      echo "$ban_summary" > "$F2B_STATE"
    else
      old="$(cat "$F2B_STATE")"
      if [ "$ban_summary" != "$old" ]; then
        echo "$ban_summary" > "$F2B_STATE"
        send_alert "Fail2ban ban count changed: $ban_summary"
      fi
    fi
  fi
fi

exit 0
