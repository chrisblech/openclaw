#!/usr/bin/env bash
# /autoupdate/setup.sh
#
# Zweck:
# - richtet auf Debian ein "production-grade" Autoupdate-Setup via systemd ein
# - Token wird sicher in /etc/openclaw/deploy.env abgelegt (chmod 600)
# - Repo-Pfad wird automatisch ermittelt: eine Ebene über diesem Skript
#
# Erwartete Repo-Struktur:
#   <repo-root>/
#     autoupdate/
#       setup.sh   (dieses Skript)
#       deploy.sh  (wird von setup.sh erzeugt/überschrieben)
#       README.md  (optional)
#
set -euo pipefail

# ----------------------------
# 0) Root-Check
# ----------------------------
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Dieses Skript muss als root laufen. Bitte mit sudo ausführen."
  echo "  Beispiel: sudo bash autoupdate/setup.sh"
  exit 1
fi

# ----------------------------
# 1) Repo-Root ermitteln
# ----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"     # eine Ebene höher als /autoupdate
DEPLOY_SH="${SCRIPT_DIR}/deploy.sh"

echo "Repo-Root erkannt als: ${REPO_ROOT}"

# ----------------------------
# 2) Grundkonstanten
# ----------------------------
SERVICE_NAME="openclaw-deploy"
OPENCLAW_USER="openclaw"
OPENCLAW_GROUP="openclaw"

ETC_DIR="/etc/openclaw"
ENV_FILE="${ETC_DIR}/deploy.env"

SYSTEMD_SERVICE="/etc/systemd/system/${SERVICE_NAME}.service"
SYSTEMD_TIMER="/etc/systemd/system/${SERVICE_NAME}.timer"

# GitHub Repo (Fork/origin)
DEFAULT_OWNER="chrisblech"
DEFAULT_REPO="openclaw"

# Upstream Repo (für Tag-Ermittlung über releases/latest)
UPSTREAM_LATEST_URL="https://github.com/openclaw/openclaw/releases/latest"

# ----------------------------
# 3) Token-Erklärung + Einlesen
# ----------------------------
cat <<'TXT'

============================================================
GitHub Token erstellen (Fine-grained PAT) – kurz erklärt
============================================================
1) GitHub → Settings → Developer settings → Personal access tokens
2) Fine-grained token erstellen:
   - Resource owner: dein Account/Org
   - Repository access: nur chrisblech/openclaw (dieses Fork-Repo)
   - Permissions (Repository permissions):
       Contents: Read and write
       Metadata: Read
   - Expiration: sinnvoll wählen (z.B. 90 Tage) und später rotieren

Warum Write?
- Der Workflow pusht Branches (openclaw-cb + openclaw-cb-vYYYY.MM.DD).

Das Token wird lokal auf der VPS gespeichert in:
  /etc/openclaw/deploy.env
mit Rechten:
  chmod 600 (nur root lesbar)

TXT

read -r -p "GitHub OWNER für deinen Fork [${DEFAULT_OWNER}]: " OWNER_IN || true
OWNER_IN="${OWNER_IN:-$DEFAULT_OWNER}"

read -r -p "GitHub REPO für deinen Fork  [${DEFAULT_REPO}]: " REPO_IN || true
REPO_IN="${REPO_IN:-$DEFAULT_REPO}"

# Token verdeckt einlesen
echo -n "Bitte GitHub Token eingeben (wird nicht angezeigt): "
read -rs GITHUB_TOKEN
echo

if [ -z "${GITHUB_TOKEN}" ]; then
  echo "ERROR: Kein Token eingegeben."
  exit 1
fi

# ----------------------------
# 4) System-User anlegen
# ----------------------------
if id -u "${OPENCLAW_USER}" >/dev/null 2>&1; then
  echo "User '${OPENCLAW_USER}' existiert bereits."
else
  echo "Lege System-User '${OPENCLAW_USER}' an..."
  useradd --system --home "${REPO_ROOT}" --shell /usr/sbin/nologin "${OPENCLAW_USER}"
fi

# Repo-Rechte (mindestens lesbar für openclaw; Schreibrechte für Build-Outputs ggf. nötig)
chown -R "${OPENCLAW_USER}:${OPENCLAW_GROUP}" "${REPO_ROOT}"

# ----------------------------
# 5) /etc/openclaw + ENV Datei schreiben
# ----------------------------
mkdir -p "${ETC_DIR}"
cat > "${ENV_FILE}" <<EOF
# Root-only secrets/config for openclaw autoupdate
GITHUB_TOKEN=${GITHUB_TOKEN}
OWNER=${OWNER_IN}
REPO=${REPO_IN}

# Repo root path on this VPS (auto-detected by setup.sh)
REPO_ROOT=${REPO_ROOT}

# Optional overrides
# REPO_DIR=\${REPO_ROOT}/repo
# ORIGIN_URL=https://github.com/\${OWNER}/\${REPO}.git
EOF

chown root:root "${ENV_FILE}"
chmod 600 "${ENV_FILE}"
echo "Geschrieben: ${ENV_FILE} (chmod 600)"

# ----------------------------
# 7) systemd Service schreiben
# ----------------------------
cat > "${SYSTEMD_SERVICE}" <<EOF
[Unit]
Description=OpenClaw Deploy (webhook -> wait -> checkout -> build)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot

EnvironmentFile=${ENV_FILE}

User=${OPENCLAW_USER}
Group=${OPENCLAW_GROUP}

WorkingDirectory=${REPO_ROOT}
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ExecStart=${DEPLOY_SH}

# Optional: nach erfolgreichem Build den eigentlichen Dienst neu starten
# (Passe "openclaw.service" an deinen echten Service-Namen an)
# ExecStartPost=/bin/systemctl restart openclaw.service

# Hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${REPO_ROOT} /run
EOF

# ----------------------------
# 8) Optionaler Timer (standardmäßig deaktiviert)
# ----------------------------
cat > "${SYSTEMD_TIMER}" <<EOF
[Unit]
Description=Run OpenClaw deploy periodically

[Timer]
OnBootSec=2min
OnUnitActiveSec=30min
AccuracySec=1min
Unit=${SERVICE_NAME}.service

[Install]
WantedBy=timers.target
EOF

echo "Schreibe systemd Unit: ${SYSTEMD_SERVICE}"
echo "Schreibe systemd Timer: ${SYSTEMD_TIMER}"

systemctl daemon-reload

# Service aktivieren (nicht auto-start; oneshot wird manuell oder per timer gestartet)
systemctl enable "${SERVICE_NAME}.service" >/dev/null 2>&1 || true

# ----------------------------
# 9) Abschluss-Hinweise
# ----------------------------
cat <<TXT

============================================================
Setup abgeschlossen ✅
============================================================

Wichtige Dateien:
- Secrets/Config:  ${ENV_FILE}
- Deploy-Skript:   ${DEPLOY_SH}
- systemd Service: ${SYSTEMD_SERVICE}
- systemd Timer:   ${SYSTEMD_TIMER}

Manuell ausführen:
  sudo systemctl start ${SERVICE_NAME}.service

Logs ansehen:
  journalctl -u ${SERVICE_NAME}.service -f

Timer optional aktivieren (wenn du NICHT rein on-demand arbeiten willst):
  sudo systemctl enable --now ${SERVICE_NAME}.timer

Hinweis zum Restart deines eigentlichen Dienstes:
- Wenn du nach dem Build automatisch neu starten willst:
  1) trage in ${SYSTEMD_SERVICE} ein:
       ExecStartPost=/bin/systemctl restart openclaw.service
  2) dann:
       sudo systemctl daemon-reload
       sudo systemctl start ${SERVICE_NAME}.service

TXT

read -r -p "Timer jetzt aktivieren? (y/N): " ENABLE_TIMER || true
if [[ "${ENABLE_TIMER:-}" =~ ^[Yy]$ ]]; then
  systemctl enable --now "${SERVICE_NAME}.timer"
  echo "Timer aktiviert: ${SERVICE_NAME}.timer"
else
  echo "Timer bleibt deaktiviert (on-demand via systemctl start)."
fi

echo "Fertig."
