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

# Service starten (oder wenn er läuft, nur anhängen)
if systemctl is-active --quiet "$UNIT"; then
  log "$UNIT läuft bereits – Letzte 5 Logzeilen:"
  journalctl -u "$UNIT" --no-pager -n 5 -o short-iso || true

  # Nur interaktiv fragen (TTY vorhanden)
  if [ -t 0 ]; then
    echo
    echo "Optionen:"
    echo "  [A] Weiter anhängen (Logs folgen)"
    echo "  [R] Laufenden Job abbrechen und neu starten"
    echo "  [Q] Abbrechen (Job läuft weiter im Hintergrund)"
    read -r -p "Auswahl (A/R/Q) [A]: " CHOICE || true
    CHOICE="${CHOICE:-A}"
    case "${CHOICE}" in
      R|r)
        log "Stoppe laufenden Job ($UNIT)..."
        systemctl stop "$UNIT" || true

        # kurz warten, bis er wirklich nicht mehr aktiv/aktivating ist
        for _ in $(seq 1 40); do
          STATE="$(systemctl show -p ActiveState --value "$UNIT" 2>/dev/null || echo unknown)"
          case "$STATE" in
            inactive|failed|deactivating) break ;;
            *) sleep 0.25 ;;
          esac
        done

        log "Starte neuen Job ($UNIT)…"
        (systemctl start --no-block "$UNIT") &
        ;;
      Q|q)
        log "Abgebrochen."
        exit 0
        ;;
      A|a)
        : # nichts, gleich Logs folgen
        ;;
      *)
        log "Unbekannte Auswahl '${CHOICE}', hänge stattdessen an."
        ;;
    esac
  fi
else
  log "Starte $UNIT…"
  (systemctl start --no-block "$UNIT") &
fi

log "Zeige Live-Logs..."
# journalctl im Hintergrund starten, aber Ausgabe geht trotzdem in dein Terminal
stdbuf -oL -eL journalctl -u "$UNIT" -f --no-pager -o short-iso --since "now" &
JPID=$!

cleanup() {
  kill "$JPID" >/dev/null 2>&1 || true
  wait "$JPID" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

# Warten bis der Service weder active noch activating ist
sleep 1
while true; do
  STATE=$(systemctl show -p ActiveState --value "$UNIT" 2>/dev/null || echo unknown)
  case "$STATE" in
    active|activating) sleep 0.5 ;;
    *) break ;;
  esac
done

RESULT=$(systemctl show -p Result --value "$UNIT" 2>/dev/null || true)
EC=$(systemctl show -p ExecMainStatus --value "$UNIT" 2>/dev/null || true)

echo
log "Service fertig. ActiveState=${STATE:-?} Result=${RESULT:-?} ExitCode=${EC:-?}"

# journalctl stoppen
cleanup

if [ "${RESULT:-}" = "failed" ] || { [ -n "${EC:-}" ] && [ "${EC:-0}" != "0" ]; }; then
  exit 1
fi
