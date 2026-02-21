#!/usr/bin/env bash
set -euo pipefail

# ----------------------------
# 0) Root-Check
# ----------------------------
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Dieses Skript muss als root laufen. Bitte mit sudo ausführen."
  exit 1
fi

UNIT="openclaw-deploy.service"

log() { echo "[upgrade.sh] $*"; }

# Startzeit merken, damit wir nur neue Logs streamen
SINCE="$(date --iso-8601=seconds)"

# Service starten (oder wenn er läuft, nur anhängen)
if systemctl is-active --quiet "$UNIT"; then
  log "$UNIT läuft bereits – hänge Logs an."
else
  log "Starte $UNIT…"
  systemctl start "$UNIT"
fi

# Watcher: wartet bis Unit nicht mehr active ist, dann beendet er journalctl (Foreground)
# -> killt den Prozess in der aktuellen Prozessgruppe (journalctl läuft im Vordergrund)
(
  # warten, bis Unit fertig ist
  while systemctl is-active --quiet "$UNIT"; do
    sleep 0.5
  done

  # Exit-Infos sammeln (optional)
  RESULT="$(systemctl show -p Result --value "$UNIT" 2>/dev/null || true)"
  EC="$(systemctl show -p ExecMainStatus --value "$UNIT" 2>/dev/null || true)"

  echo
  log "Service fertig. Result=${RESULT:-?} ExitCode=${EC:-?}"

  # journalctl im Vordergrund beenden (SIGTERM an die Prozessgruppe)
  # (kill 0 sendet an Prozessgruppe; wir wollen aber nur journalctl beenden)
  # Daher: PID aus parent (upgrade.sh) via pgrep im aktuellen TTY ist tricky.
  # Einfacher: wir beenden die gesamte FG-Pipeline via SIGINT an uns selbst:
  kill -INT "$$" 2>/dev/null || true
) &

WATCHER_PID=$!

# Wichtig: journalctl im VORDERGRUND, damit tmux/TTY zuverlässig ausgibt.
# --since: nur neue Logs ab Start dieses upgrade.sh
# -o short-iso: gut lesbar, inkl. Zeit
# stdbuf: erzwingt line-buffering (hilft in manchen TTY/tmux Fällen zusätzlich)
log "Zeige Live-Logs (endet automatisch wenn Service stoppt)…"
# stdbuf -oL -eL journalctl -u "$UNIT" -f --no-pager -o short-iso --since "$SINCE"
journalctl -u "$UNIT" -f --no-pager -o short-iso --since "$SINCE"

# Wenn journalctl endet (durch Watcher oder manuell), Watcher sauber aufräumen
kill "$WATCHER_PID" >/dev/null 2>&1 || true
wait "$WATCHER_PID" >/dev/null 2>&1 || true
