#!/usr/bin/env bash
set -euo pipefail



SCRIPT_NAME="$(basename "$0")"
LOG_TS() { date +"%Y-%m-%dT%H:%M:%S%z"; }

log()     { echo "[$(LOG_TS)] [INFO]  $*"; }
warn()    { echo "[$(LOG_TS)] [WARN]  $*"; }
error()   { echo "[$(LOG_TS)] [ERROR] $*" >&2; }
pass()    { echo "[$(LOG_TS)] [PASS]  $*"; }
fail()    { echo "[$(LOG_TS)] [FAIL]  $*" >&2; }

require_root() {
  [[ "${EUID}" -eq 0 ]] || { error "Run as root."; exit 1; }
}

require_ubuntu() {
  [[ -f /etc/os-release ]] || { error "Cannot determine OS."; exit 1; }
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || { error "This script supports Ubuntu only."; exit 1; }
}

PHASE_FAILURES=0

record_failure() {
  PHASE_FAILURES=$((PHASE_FAILURES + 1))
  fail "$*"
}

# ------------------------------ Config ---------------------------------------

KIJANI_ROOT="/opt/kijanikiosk"
CONFIG_DIR="${KIJANI_ROOT}/config"
HEALTH_DIR="${KIJANI_ROOT}/health"
SHARED_LOG_DIR="${KIJANI_ROOT}/shared/logs"

API_USER="kk-api"
PAY_USER="kk-payments"
LOG_USER="kk-logs"
PLATFORM_GROUP="kijanikiosk"


NGINX_VERSION="${NGINX_VERSION:-1.24.0-2ubuntu7.6}"
NODEJS_VERSION="${NODEJS_VERSION:-18.19.1+dfsg-6ubuntu5}"

MONITORING_CIDR="10.0.1.0/24"

OPS_USER="${SUDO_USER:-${USER:-vodca}}"

# --------------------------- Utility Helpers ---------------------------------

pkg_installed_version() {
  local pkg="$1"
  dpkg-query -W -f='${Version}\n' "$pkg" 2>/dev/null || true
}

ensure_group() {
  local grp="$1"
  if getent group "$grp" >/dev/null 2>&1; then
    log "Already exists: group ${grp}"
  else
    groupadd "$grp"
    log "Created group ${grp}"
  fi
}

ensure_user() {
  local user="$1"
  local comment="$2"
  if id "$user" >/dev/null 2>&1; then
    log "Already exists: user ${user}"
  else
    useradd \
      --system \
      --no-create-home \
      --home-dir /nonexistent \
      --shell /usr/sbin/nologin \
      --comment "$comment" \
      "$user"
    log "Created system user ${user}"
  fi
}

ensure_user_in_group() {
  local user="$1"
  local group="$2"
  if id -nG "$user" | tr ' ' '\n' | grep -qx "$group"; then
    log "User ${user} already in group ${group}"
  else
    usermod -aG "$group" "$user"
    log "Added ${user} to ${group}"
  fi
}

ensure_dir() {
  local path="$1" owner="$2" group="$3" mode="$4"
  mkdir -p "$path"
  chown "$owner:$group" "$path"
  chmod "$mode" "$path"
}

write_file_if_changed() {
  local target="$1"
  local tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  if [[ -f "$target" ]] && cmp -s "$tmp" "$target"; then
    rm -f "$tmp"
    log "No change: ${target}"
    return 0
  fi
  install -m 0644 "$tmp" "$target"
  rm -f "$tmp"
  log "Wrote ${target}"
}

write_secret_file_if_changed() {
  local target="$1" owner="$2" group="$3" mode="$4"
  local tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  if [[ -f "$target" ]] && cmp -s "$tmp" "$target"; then
    rm -f "$tmp"
    log "No change: ${target}"
  else
    install -m "$mode" -o "$owner" -g "$group" "$tmp" "$target"
    rm -f "$tmp"
    log "Wrote ${target}"
  fi
  chown "$owner:$group" "$target"
  chmod "$mode" "$target"
}

set_default_acls() {
  local dir="$1"
  
  setfacl -b "$dir" || true
  setfacl -k "$dir" || true

  setfacl -m u::rwx "$dir"
  setfacl -m g::r-x "$dir"
  setfacl -m u:${API_USER}:rwx "$dir"
  setfacl -m u:${PAY_USER}:r-x "$dir"
  setfacl -m u:${OPS_USER}:r-x "$dir"
  setfacl -m m::rwx "$dir"
  setfacl -m o::--- "$dir"

  setfacl -d -m u::rwx "$dir"
  setfacl -d -m g::r-x "$dir"
  setfacl -d -m u:${API_USER}:rwx "$dir"
  setfacl -d -m u:${PAY_USER}:r-x "$dir"
  setfacl -d -m u:${OPS_USER}:r-x "$dir"
  setfacl -d -m m::rwx "$dir"
  setfacl -d -m o::--- "$dir"
}

# ------------------------------ Phase 1 --------------------------------------

phase1_packages() {
  log "=== Phase 1: Packages and version control ==="

  apt-get update -y
  apt-get install -y acl ufw nginx nodejs logrotate jq curl

  local nginx_current node_current
  nginx_current="$(pkg_installed_version nginx)"
  node_current="$(pkg_installed_version nodejs)"

  if [[ -z "$nginx_current" || -z "$node_current" ]]; then
    error "Required packages not installed after apt-get install."
    exit 1
  fi

  log "Installed nginx version: ${nginx_current}"
  log "Installed nodejs version: ${node_current}"

  if [[ "$nginx_current" != "$NGINX_VERSION" ]]; then
    error "nginx version drift detected. Expected ${NGINX_VERSION}, found ${nginx_current}. Refusing automatic downgrade."
    exit 1
  fi

  if [[ "$node_current" != "$NODEJS_VERSION" ]]; then
    error "nodejs version drift detected. Expected ${NODEJS_VERSION}, found ${node_current}. Refusing automatic downgrade."
    exit 1
  fi

  apt-mark hold nginx nodejs >/dev/null
  log "Held nginx and nodejs against drift"
}

# ------------------------------ Phase 2 --------------------------------------

phase2_identities() {
  log "=== Phase 2: Service identities ==="

  ensure_group "$PLATFORM_GROUP"

  ensure_user "$API_USER" "KijaniKiosk API Service"
  ensure_user "$PAY_USER" "KijaniKiosk Payments Service"
  ensure_user "$LOG_USER" "KijaniKiosk Logging Service"

  ensure_user_in_group "$API_USER" "$PLATFORM_GROUP"
  ensure_user_in_group "$PAY_USER" "$PLATFORM_GROUP"
  ensure_user_in_group "$LOG_USER" "$PLATFORM_GROUP"

  if id "$OPS_USER" >/dev/null 2>&1; then
    ensure_user_in_group "$OPS_USER" "$PLATFORM_GROUP"
  else
    warn "OPS_USER ${OPS_USER} not present; skipping platform group membership."
  fi
}

# ------------------------------ Phase 3 --------------------------------------

phase3_filesystem() {
  log "=== Phase 3: Filesystem, permissions, ACLs ==="

  ensure_dir "$KIJANI_ROOT" root "$PLATFORM_GROUP" 0750
  ensure_dir "${KIJANI_ROOT}/api" "$API_USER" "$API_USER" 0750
  ensure_dir "${KIJANI_ROOT}/payments" "$PAY_USER" "$PAY_USER" 0750
  ensure_dir "${KIJANI_ROOT}/logs" "$LOG_USER" "$LOG_USER" 0750
  ensure_dir "${KIJANI_ROOT}/scripts" root root 0750
  ensure_dir "${KIJANI_ROOT}/shared" root "$PLATFORM_GROUP" 0750
  ensure_dir "$SHARED_LOG_DIR" "$LOG_USER" "$PLATFORM_GROUP" 0750
  ensure_dir "$CONFIG_DIR" root "$PLATFORM_GROUP" 0750
  ensure_dir "$HEALTH_DIR" "$LOG_USER" "$PLATFORM_GROUP" 0750

  if id "$OPS_USER" >/dev/null 2>&1; then
    setfacl -m u:${OPS_USER}:r-x "$HEALTH_DIR"
    setfacl -d -m u:${OPS_USER}:r-x "$HEALTH_DIR"
    setfacl -m m::rwx "$HEALTH_DIR"
    setfacl -d -m m::rwx "$HEALTH_DIR"
  fi

  [[ -f "${KIJANI_ROOT}/api/server.js" ]] || echo "console.log('KijaniKiosk API running');" > "${KIJANI_ROOT}/api/server.js"
  [[ -f "${KIJANI_ROOT}/payments/processor.js" ]] || cat > "${KIJANI_ROOT}/payments/processor.js" <<'EOF'
const http = require('http');
const server = http.createServer((req, res) => {
  res.writeHead(200, {'Content-Type': 'application/json'});
  res.end(JSON.stringify({ service: 'kk-payments', status: 'ok' }));
});
server.listen(3001, '127.0.0.1');
EOF

  [[ -f "${KIJANI_ROOT}/logs/aggregator.sh" ]] || cat > "${KIJANI_ROOT}/logs/aggregator.sh" <<'EOF'
#!/usr/bin/env bash
while true; do
  sleep 60
done
EOF

  chown "$API_USER:$API_USER" "${KIJANI_ROOT}/api/server.js"
  chown "$PAY_USER:$PAY_USER" "${KIJANI_ROOT}/payments/processor.js"
  chown "$LOG_USER:$LOG_USER" "${KIJANI_ROOT}/logs/aggregator.sh"
  chmod 0750 "${KIJANI_ROOT}/logs/aggregator.sh"
  chmod 0640 "${KIJANI_ROOT}/api/server.js" "${KIJANI_ROOT}/payments/processor.js"

  write_secret_file_if_changed "${CONFIG_DIR}/db.env" root "$PLATFORM_GROUP" 0640 <<'EOF'
DB_HOST=internal-postgres.kijanikiosk.internal
DB_PORT=5432
DB_NAME=kijanikiosk_prod
DB_USER=kk_app
DB_PASSWORD=change-me
EOF

  write_secret_file_if_changed "${CONFIG_DIR}/api.env" root "$PLATFORM_GROUP" 0640 <<'EOF'
NODE_ENV=production
PORT=3000
EOF

  write_secret_file_if_changed "${CONFIG_DIR}/payments-api.env" root "$PLATFORM_GROUP" 0640 <<'EOF'
PAYMENTS_API_KEY=change-me
PAYMENTS_WEBHOOK_SECRET=change-me
PORT=3001
EOF

  chmod 0750 "$CONFIG_DIR"
  chmod 0640 "${CONFIG_DIR}/"*.env
  chown root:"$PLATFORM_GROUP" "$CONFIG_DIR" "${CONFIG_DIR}/"*.env

  set_default_acls "$SHARED_LOG_DIR"

  if [[ -f "${KIJANI_ROOT}/scripts/deploy.sh" ]]; then
    chmod u-s "${KIJANI_ROOT}/scripts/deploy.sh" || true
    chmod 0750 "${KIJANI_ROOT}/scripts/deploy.sh" || true
    chown root:root "${KIJANI_ROOT}/scripts/deploy.sh" || true
  fi
}

# ------------------------------ Phase 4 --------------------------------------

phase4_systemd() {
  log "=== Phase 4: systemd units ==="

  write_file_if_changed /etc/systemd/system/kk-api.service <<EOF
[Unit]
Description=KijaniKiosk API Service
Wants=network-online.target
After=network-online.target
Documentation=internal

[Service]
Type=simple
User=${API_USER}
Group=${API_USER}
WorkingDirectory=${KIJANI_ROOT}/api
EnvironmentFile=${CONFIG_DIR}/db.env
EnvironmentFile=${CONFIG_DIR}/api.env
ExecStart=/usr/bin/node ${KIJANI_ROOT}/api/server.js
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5s
StartLimitIntervalSec=60
StartLimitBurst=3
TimeoutStartSec=30
TimeoutStopSec=30
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectClock=true
ProtectHostname=true
ProtectKernelLogs=true
ProtectKernelModules=true
ProtectKernelTunables=true
PrivateDevices=true
PrivateMounts=true
RestrictSUIDSGID=true
RestrictNamespaces=true
LockPersonality=true
MemoryDenyWriteExecute=true
RemoveIPC=true
SystemCallArchitectures=native
UMask=0027
ReadWritePaths=${KIJANI_ROOT}/api
ReadOnlyPaths=${CONFIG_DIR}
CapabilityBoundingSet=
AmbientCapabilities=
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kk-api

[Install]
WantedBy=multi-user.target
EOF

  write_file_if_changed /etc/systemd/system/kk-payments.service <<EOF
[Unit]
Description=KijaniKiosk Payments Service
Wants=network-online.target kk-api.service
After=network-online.target kk-api.service
Documentation=internal

[Service]
Type=simple
User=${PAY_USER}
Group=${PAY_USER}
WorkingDirectory=${KIJANI_ROOT}/payments
EnvironmentFile=${CONFIG_DIR}/payments-api.env
ExecStart=/usr/bin/node ${KIJANI_ROOT}/payments/processor.js
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5s
StartLimitIntervalSec=60
StartLimitBurst=3
TimeoutStartSec=30
TimeoutStopSec=30
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ProtectClock=true
ProtectHostname=true
ProtectKernelLogs=true
ProtectKernelModules=true
ProtectKernelTunables=true
PrivateDevices=true
PrivateUsers=true
ProtectProc=invisible
ProcSubset=pid
PrivateMounts=true
RestrictSUIDSGID=true
RestrictRealtime=true
RestrictNamespaces=true
LockPersonality=true
MemoryDenyWriteExecute=true
RemoveIPC=true
SystemCallArchitectures=native
SystemCallFilter=@system-service
UMask=0027
ReadWritePaths=${KIJANI_ROOT}/payments
ReadOnlyPaths=${CONFIG_DIR}
CapabilityBoundingSet=
AmbientCapabilities=
SocketBindDeny=any
IPAddressDeny=any
IPAddressAllow=127.0.0.1
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kk-payments

[Install]
WantedBy=multi-user.target
EOF

  write_file_if_changed /etc/systemd/system/kk-logs.service <<EOF
[Unit]
Description=KijaniKiosk Log Aggregator Service
Wants=network-online.target
After=network-online.target
Documentation=internal

[Service]
Type=simple
User=${LOG_USER}
Group=${LOG_USER}
WorkingDirectory=${KIJANI_ROOT}/logs
ExecStart=${KIJANI_ROOT}/logs/aggregator.sh
Restart=on-failure
RestartSec=5s
StartLimitIntervalSec=60
StartLimitBurst=3
TimeoutStartSec=30
TimeoutStopSec=30
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectClock=true
ProtectHostname=true
ProtectKernelLogs=true
ProtectKernelModules=true
ProtectKernelTunables=true
PrivateDevices=true
PrivateMounts=true
RestrictSUIDSGID=true
RestrictNamespaces=true
LockPersonality=true
MemoryDenyWriteExecute=true
RemoveIPC=true
SystemCallArchitectures=native
UMask=0027
ReadWritePaths=${SHARED_LOG_DIR} ${KIJANI_ROOT}/logs
CapabilityBoundingSet=
AmbientCapabilities=
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kk-logs

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable kk-api.service kk-payments.service kk-logs.service

  
  systemctl restart kk-api.service || true
  systemctl restart kk-payments.service || true
  systemctl restart kk-logs.service || true
}

# ------------------------------ Phase 5 --------------------------------------

phase5_firewall() {
  log "=== Phase 5: Firewall intent ==="

  apt-get install -y ufw >/dev/null

  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing

  ufw allow 22/tcp comment 'Allow SSH administration'
  ufw allow 80/tcp comment 'Allow HTTP to nginx'
  ufw allow in on lo to any port 3001 proto tcp comment 'Allow loopback proxy to payments'
  ufw allow from "${MONITORING_CIDR}" to any port 3001 proto tcp comment 'Allow monitoring health checks to payments'
  ufw deny 3001/tcp comment 'Deny external direct access to payments service'
  ufw --force enable
  ufw reload
}

# ------------------------------ Phase 6 --------------------------------------

phase6_sudoers() {
  log "=== Phase 6: Restricted sudoers policy ==="

  if id "$OPS_USER" >/dev/null 2>&1; then
    cat > /etc/sudoers.d/"${OPS_USER}" <<EOF
Cmnd_Alias KKIJ_SYSTEMCTL_STATUS = /bin/systemctl status kk-api.service, /bin/systemctl status kk-payments.service, /bin/systemctl status kk-logs.service, /bin/systemctl status kk-api, /bin/systemctl status kk-payments, /bin/systemctl status kk-logs
Cmnd_Alias KKIJ_SYSTEMCTL_RESTART = /bin/systemctl restart kk-api.service, /bin/systemctl restart kk-payments.service, /bin/systemctl restart kk-logs.service, /bin/systemctl restart kk-api, /bin/systemctl restart kk-payments, /bin/systemctl restart kk-logs
Cmnd_Alias KKIJ_JOURNAL = /bin/journalctl -u kk-api, /bin/journalctl -u kk-payments, /bin/journalctl -u kk-logs, /bin/journalctl -u kk-api.service, /bin/journalctl -u kk-payments.service, /bin/journalctl -u kk-logs.service
Cmnd_Alias KKIJ_NGINX_EDIT = sudoedit /etc/nginx/nginx.conf

${OPS_USER} ALL=(root) NOPASSWD: KKIJ_SYSTEMCTL_STATUS, KKIJ_SYSTEMCTL_RESTART, KKIJ_JOURNAL, KKIJ_NGINX_EDIT
EOF
    chmod 0440 /etc/sudoers.d/"${OPS_USER}"
    visudo -cf /etc/sudoers.d/"${OPS_USER}" >/dev/null
  else
    warn "OPS_USER ${OPS_USER} not present; skipping sudoers drop-in."
  fi
}

# ------------------------------ Phase 7 --------------------------------------

phase7_journal_and_logrotate() {
  log "=== Phase 7: Journal persistence and log rotation ==="

  mkdir -p /var/log/journal
  systemd-tmpfiles --create --prefix /var/log/journal
  mkdir -p /etc/systemd/journald.conf.d

  write_file_if_changed /etc/systemd/journald.conf.d/kijanikiosk-persistent.conf <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=500M
RuntimeMaxUse=200M
EOF

  write_file_if_changed /etc/logrotate.d/kijanikiosk <<EOF
${SHARED_LOG_DIR}/*.log {
    daily
    rotate 14
    missingok
    notifempty
    compress
    delaycompress
    dateext
    su ${LOG_USER} ${PLATFORM_GROUP}
    create 0640 ${LOG_USER} ${PLATFORM_GROUP}
    sharedscripts
    postrotate
        /bin/systemctl try-restart kk-logs.service >/dev/null 2>&1 || true
    endscript
}
EOF

  systemctl restart systemd-journald

  logrotate --debug /etc/logrotate.d/kijanikiosk >/dev/null
  log "logrotate debug passed"
}

# ------------------------------ Phase 8 --------------------------------------

phase8_health_checks() {
  log "=== Phase 8: Monitoring health checks ==="

  mkdir -p "$HEALTH_DIR"

  local api_status payments_status logs_status
  api_status=$(timeout 2 bash -c "echo >/dev/tcp/127.0.0.1/3000" 2>/dev/null && echo '"ok"' || echo '"down"')
  payments_status=$(timeout 2 bash -c "echo >/dev/tcp/127.0.0.1/3001" 2>/dev/null && echo '"ok"' || echo '"down"')
  logs_status=$(systemctl is-active kk-logs.service >/dev/null 2>&1 && echo '"ok"' || echo '"down"')

  printf '{"timestamp":"%s","kk-api":%s,"kk-payments":%s,"kk-logs":%s}\n' \
    "$(date -Is)" "$api_status" "$payments_status" "$logs_status" \
    > "${HEALTH_DIR}/last-provision.json"

  chown "${LOG_USER}:${PLATFORM_GROUP}" "${HEALTH_DIR}/last-provision.json"
  chmod 0640 "${HEALTH_DIR}/last-provision.json"

  if id "$OPS_USER" >/dev/null 2>&1; then
    setfacl -m u:${OPS_USER}:r-- "${HEALTH_DIR}/last-provision.json" || true
  fi

  log "Wrote ${HEALTH_DIR}/last-provision.json"
}

# --------------------------- Verification ------------------------------------

verify_packages() {
  local ok=0
  [[ "$(pkg_installed_version nginx)" == "$NGINX_VERSION" ]] && pass "nginx pinned version correct" || { record_failure "nginx version mismatch"; ok=1; }
  [[ "$(pkg_installed_version nodejs)" == "$NODEJS_VERSION" ]] && pass "nodejs pinned version correct" || { record_failure "nodejs version mismatch"; ok=1; }
  apt-mark showhold | grep -qx nginx && pass "nginx held" || { record_failure "nginx hold missing"; ok=1; }
  apt-mark showhold | grep -qx nodejs && pass "nodejs held" || { record_failure "nodejs hold missing"; ok=1; }
  return "$ok"
}

verify_identities() {
  local ok=0
  for u in "$API_USER" "$PAY_USER" "$LOG_USER"; do
    id "$u" >/dev/null 2>&1 && pass "user ${u} exists" || { record_failure "user ${u} missing"; ok=1; }
  done
  getent group "$PLATFORM_GROUP" >/dev/null 2>&1 && pass "group ${PLATFORM_GROUP} exists" || { record_failure "group ${PLATFORM_GROUP} missing"; ok=1; }
  return "$ok"
}

verify_filesystem() {
  local ok=0
  sudo -u "$API_USER" test -r "${CONFIG_DIR}/db.env" && pass "kk-api can read db.env" || { record_failure "kk-api cannot read db.env"; ok=1; }
  sudo -u "$API_USER" touch "${SHARED_LOG_DIR}/test-write.tmp" && pass "kk-api can write shared logs" || { record_failure "kk-api cannot write shared logs"; ok=1; }
  rm -f "${SHARED_LOG_DIR}/test-write.tmp" || true
  sudo -u "$PAY_USER" test -r "${SHARED_LOG_DIR}" && pass "kk-payments can read shared logs directory" || { record_failure "kk-payments cannot read shared logs"; ok=1; }
  return "$ok"
}

verify_systemd() {
  local ok=0

  systemctl cat kk-api.service >/dev/null 2>&1 \
    && pass "kk-api unit installed" \
    || { record_failure "kk-api unit missing"; ok=1; }

  systemctl cat kk-payments.service >/dev/null 2>&1 \
    && pass "kk-payments unit installed" \
    || { record_failure "kk-payments unit missing"; ok=1; }

  systemctl cat kk-logs.service >/dev/null 2>&1 \
    && pass "kk-logs unit installed" \
    || { record_failure "kk-logs unit missing"; ok=1; }

  systemctl is-enabled kk-api.service >/dev/null 2>&1 \
    && pass "kk-api enabled" \
    || { record_failure "kk-api not enabled"; ok=1; }

  systemctl is-enabled kk-payments.service >/dev/null 2>&1 \
    && pass "kk-payments enabled" \
    || { record_failure "kk-payments not enabled"; ok=1; }

  systemctl is-enabled kk-logs.service >/dev/null 2>&1 \
    && pass "kk-logs enabled" \
    || { record_failure "kk-logs not enabled"; ok=1; }

  return "$ok"
}

verify_firewall() {
  local ok=0
  local status
  status="$(sudo ufw status)"

  echo "$status" | grep -q "22/tcp.*ALLOW" \
    && pass "SSH allowed" \
    || { record_failure "SSH rule missing"; ok=1; }

  echo "$status" | grep -q "80/tcp.*ALLOW" \
    && pass "HTTP allowed" \
    || { record_failure "HTTP rule missing"; ok=1; }

  echo "$status" | grep -q "3001/tcp.*DENY" \
    && pass "port 3001 deny present" \
    || { record_failure "port 3001 deny rule missing"; ok=1; }

  if echo "$status" | grep -q "10.0.1.0/24" && echo "$status" | grep -q "3001/tcp"; then
    pass "monitoring CIDR allowed to 3001"
  else
    record_failure "monitoring CIDR allow missing"
    ok=1
  fi

  return "$ok"
}

verify_journal_and_logrotate() {
  local ok=0
  [[ -d /var/log/journal ]] && pass "persistent journal directory exists" || { record_failure "persistent journal directory missing"; ok=1; }
  logrotate --debug /etc/logrotate.d/kijanikiosk >/dev/null && pass "logrotate debug clean" || { record_failure "logrotate debug failed"; ok=1; }

  touch "${SHARED_LOG_DIR}/payments-test.log"
  logrotate --force /etc/logrotate.d/kijanikiosk >/dev/null 2>&1 || true
  sudo -u "$API_USER" touch "${SHARED_LOG_DIR}/post-rotate-write.tmp" && pass "kk-api can write after logrotate" || { record_failure "kk-api cannot write after logrotate"; ok=1; }
  rm -f "${SHARED_LOG_DIR}/post-rotate-write.tmp" || true
  return "$ok"
}

verify_health_file() {
  local ok=0
  [[ -f "${HEALTH_DIR}/last-provision.json" ]] && pass "health JSON exists" || { record_failure "health JSON missing"; ok=1; }
  jq . "${HEALTH_DIR}/last-provision.json" >/dev/null 2>&1 && pass "health JSON valid" || { record_failure "health JSON invalid"; ok=1; }
  return "$ok"
}

final_verification() {
  log "=== Final verification ==="
  verify_packages || true
  verify_identities || true
  verify_filesystem || true
  verify_systemd || true
  verify_firewall || true
  verify_journal_and_logrotate || true
  verify_health_file || true

  if [[ "$PHASE_FAILURES" -gt 0 ]]; then
    error "Verification failed with ${PHASE_FAILURES} failed check(s)."
    exit 1
  fi

  pass "All verification checks passed."
}

main() {
  require_root
  require_ubuntu

  phase1_packages
  phase2_identities
  phase3_filesystem
  phase4_systemd
  phase5_firewall
  phase6_sudoers
  phase7_journal_and_logrotate
  phase8_health_checks
  final_verification
}

main "$@"

