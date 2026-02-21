#!/usr/bin/env bash
set -euo pipefail

UNIT="openclaw-deploy.service"
log() { echo "[upgrade.sh] $*"; }

# ----------------------------
# 0) Root-Check
# ----------------------------
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Dieses Skript muss als root laufen. Bitte mit sudo ausführen."
  exit 1
fi

# Startzeit merken, damit wir nur neue Logs streamen
SINCE="$(date --iso-8601=seconds)"

# Service starten (oder wenn er läuft, nur anhängen)
if systemctl is-active --quiet "$UNIT"; then
  log "$UNIT läuft bereits – hänge Logs an."
else
  log "Starte $UNIT…"
  (systemctl start --no-block "$UNIT") &
fi

# Watcher beendet journalctl wenn Unit fertig
(
  while systemctl is-active --quiet "$UNIT" || systemctl is-activating --quiet "$UNIT"; do
    sleep 0.5
  done

  # Exit-Infos sammeln (optional)
  RESULT="$(systemctl show -p Result --value "$UNIT" 2>/dev/null || true)"
  EC="$(systemctl show -p ExecMainStatus --value "$UNIT" 2>/dev/null || true)"

  echo
  log "Service fertig. Result=${RESULT:-?} ExitCode=${EC:-?}"

  kill -INT "$$" 2>/dev/null || true
) &

WATCHER_PID=$!

# Wichtig: journalctl im VORDERGRUND, damit tmux/TTY zuverlässig ausgibt.
# --since: nur neue Logs ab Start dieses upgrade.sh
# -o short-iso: gut lesbar, inkl. Zeit
# stdbuf: erzwingt line-buffering (hilft in manchen TTY/tmux Fällen zusätzlich)
log "Zeige Live-Logs (endet automatisch wenn Service stoppt)…"
exec stdbuf -oL -eL journalctl -u "$UNIT" -f --no-pager -o short-iso --since "$SINCE"
