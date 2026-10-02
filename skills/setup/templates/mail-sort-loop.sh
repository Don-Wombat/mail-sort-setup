#!/usr/bin/env bash
# Generischer Mail-Sortier-Loop. Von mail-sort-setup aus einer Vorlage
# befuellt -- die MAIL_SORT_*-Variablen unten sind die einzigen Stellen,
# die pro Einrichtung angepasst werden muessen.
#
# Manueller Einzellauf (z.B. fuer den Testlauf in SKILL.md Phase 6):
#   bash mail-sort-loop.sh --once
# Einzellauf ueber den KOMPLETTEN Posteingang (Watermark ignorieren, z.B.
# nach einer Regelaenderung):
#   bash mail-sort-loop.sh --once --full
# Dauerbetrieb (Endlosschleife mit Wartezeit zwischen den Laeufen):
#   bash mail-sort-loop.sh
#
# Exit-Codes (--once): 0 = Lauf vollstaendig, 1 = Fehler/unvollstaendig,
# 3 = anderer Lauf aktiv.
set -uo pipefail
umask 077

# In das eigene Verzeichnis wechseln und PATH ergaenzen: Cron/systemd
# starten sonst irgendwo anders und mit minimalem PATH. Angehaengt (nicht
# vorangestellt), damit ein vom Nutzer gesetzter PATH Vorrang behaelt.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)" || exit 1
cd "$SCRIPT_DIR" || exit 1
export PATH="$PATH:$HOME/.local/bin:$HOME/.npm-global/bin:/usr/local/bin"

# --- Anpassen ---------------------------------------------------------
MAIL_SORT_PROMPT_FILE="$SCRIPT_DIR/mail-sort-prompt.txt"
MAIL_SORT_LOG_FILE="$SCRIPT_DIR/mail-sort.log"
MAIL_SORT_STATE_FILE="$SCRIPT_DIR/mail-sort-last-run.txt"
# Nur dieser MCP-Server wird im Lauf geladen (siehe SKILL.md Phase 1b).
MAIL_SORT_MCP_CONFIG="$SCRIPT_DIR/mail-mcp.json"
MAIL_SORT_INTERVAL_SECONDS=14400   # Abstand zwischen automatischen Laeufen (Phase 5). 14400 = 4h.
MAIL_SORT_FIRST_RUN_AT=""          # "HH:MM" (Ortszeit): erster Lauf erst zu dieser Uhrzeit, nur solange noch kein Watermark existiert. Leer = sofort.
MAIL_SORT_FIRST_RUN_SINCE=""       # Optional, ISO-Zeitstempel mit Offset (z.B. 2026-01-01T00:00:00Z): Erstlauf nur ab diesem Datum statt kompletter Bestand.
MAIL_SORT_RUN_TIMEOUT_SECONDS=1800 # Abbruch eines haengenden Laufs.
MAIL_SORT_LOG_MAX_BYTES=5242880    # Log-Rotation (eine Generation: mail-sort.log.1).
MAIL_SORT_STATE_MARGIN_SECONDS=300 # Sicherheitsmarge beim Watermark (Uhrabweichung Container <-> IMAP-Server).
# Wer einen Retry-Wrapper nutzt, traegt ihn hier ein. Er muss die
# claude-Argumente 1:1 durchreichen, stdin weiterleiten und den Exit-Code
# erhalten.
CLAUDE_BIN="${MAIL_SORT_CLAUDE_BIN:-claude}"
# Nur Lesen/Verschieben/Markieren -- siehe SKILL.md Abschnitt 0. NICHT
# erweitern, ohne die Sicherheitsbegruendung dort neu zu bewerten.
MAIL_SORT_ALLOWED_TOOLS=(
  mcp__mail__list_available_accounts
  mcp__mail__list_emails_metadata
  mcp__mail__list_mailboxes
  mcp__mail__list_email_tags
  mcp__mail__move_emails
  mcp__mail__set_email_tags
)
# Zusaetzliche Sperre (deny gewinnt): alle schreibenden bzw. inhaltlesenden
# Tools von mcp-email-server, falls jemand den Permission-Mode ueberschreibt.
MAIL_SORT_DISALLOWED_TOOLS=(
  mcp__mail__send_email
  mcp__mail__forward_email
  mcp__mail__save_to_mailbox
  mcp__mail__delete_emails
  mcp__mail__archive_emails
  mcp__mail__set_email_flags
  mcp__mail__mark_emails_as_read
  mcp__mail__get_emails_content
  mcp__mail__download_attachment
  mcp__mail__get_attachment_content
)
# Der Prompt verlangt diese Schlusszeile; nur dann gilt der Lauf als
# vollstaendig und der Watermark wird fortgeschrieben.
MAIL_SORT_DONE_MARKER="MAIL_SORT_LAUF_OK"
# -----------------------------------------------------------------------

LOCK_DIR="$SCRIPT_DIR/.mail-sort.lock"
LOCK_HELD=0

ts_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Epoch-Sekunden -> UTC-ISO (GNU date, sonst BSD/macOS date)
fmt_epoch() {
  date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ
}

# Verwaist, wenn der Besitzer nicht mehr laeuft, die PID die eigene ist
# (PID-Wiederverwendung nach Neustart) oder das Lock aelter ist als ein
# Lauf maximal dauern kann (PID inzwischen an fremden Prozess vergeben).
lock_is_stale() {
  local pid max_min
  pid="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
  if [ -z "$pid" ]; then
    # Gerade erst angelegt (PID noch nicht geschrieben) oder kaputt.
    [ -n "$(find "$LOCK_DIR" -maxdepth 0 -mmin +1 2>/dev/null)" ]
    return
  fi
  [ "$pid" = "$$" ] && return 0
  kill -0 "$pid" 2>/dev/null || return 0
  max_min=$(( (MAIL_SORT_RUN_TIMEOUT_SECONDS + 600) / 60 ))
  [ -n "$(find "$LOCK_DIR" -maxdepth 0 -mmin +"$max_min" 2>/dev/null)" ]
}

acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo $$ > "$LOCK_DIR/pid"; LOCK_HELD=1; return 0
  fi
  lock_is_stale || return 1
  rm -rf "$LOCK_DIR"
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo $$ > "$LOCK_DIR/pid"; LOCK_HELD=1; return 0
  fi
  return 1
}

cleanup() {
  [ "$LOCK_HELD" -eq 1 ] && rm -rf "$LOCK_DIR"
  LOCK_HELD=0
}
trap cleanup EXIT
trap 'exit 130' INT TERM

rotate_log() {
  local size
  [ -f "$MAIL_SORT_LOG_FILE" ] || return 0
  size="$(wc -c < "$MAIL_SORT_LOG_FILE" | tr -d ' ')"
  if [ "${size:-0}" -gt "$MAIL_SORT_LOG_MAX_BYTES" ]; then
    mv -f "$MAIL_SORT_LOG_FILE" "$MAIL_SORT_LOG_FILE.1"
  fi
}

TIMEOUT_CMD=()
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD=(timeout --kill-after=60 "$MAIL_SORT_RUN_TIMEOUT_SECONDS")
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD=(gtimeout --kill-after=60 "$MAIL_SORT_RUN_TIMEOUT_SECONDS")
fi

# Gueltiger Watermark auf stdout, sonst nichts (ungueltig: Warnung auf stderr).
read_watermark() {
  local w
  [ -s "$MAIL_SORT_STATE_FILE" ] || return 0
  w="$(tr -d '[:space:]' < "$MAIL_SORT_STATE_FILE")"
  if printf '%s' "$w" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$'; then
    printf '%s' "$w"
  elif [ -n "$w" ]; then
    echo "[mail-sort] WARNUNG: Watermark-Datei hat ungueltigen Inhalt, behandle den Lauf als Erstlauf." >&2
  fi
}

# Prompt fuer diesen Lauf auf stdout. $1 = run_start, $2 = since (leer = Erstlauf/Vollauf), $3 = first_since
build_prompt() {
  cat "$MAIL_SORT_PROMPT_FILE"
  if [ -n "$2" ]; then
    printf '\n\nHinweis: Dies ist KEIN Erstlauf. Zeitfenster dieses Laufs (UTC): since="%s" und before="%s".\nÜbergib beide Werte als since- bzw. before-Parameter an list_emails_metadata.\n' "$2" "$1"
  elif [ -n "$3" ]; then
    printf '\n\nHinweis: Dies ist der Erstlauf, begrenzt auf einen Zeitraum. Zeitfenster dieses Laufs: since="%s" und before="%s".\nÜbergib beide Werte als since- bzw. before-Parameter an list_emails_metadata.\n' "$3" "$1"
  else
    printf '\n\nHinweis: Dies ist der Erstlauf bzw. ein Vollauf (kein since-Zeitstempel). Prüfe den kompletten aktuellen Bestand in INBOX.\nZeitfenster dieses Laufs (UTC): nur before="%s" (als before-Parameter an list_emails_metadata übergeben).\n' "$1"
  fi
}

run_once() {
  local full="$1" run_start start_epoch output rc last_line mode since="" first_since=""

  if [ ! -f "$MAIL_SORT_PROMPT_FILE" ]; then
    echo "[mail-sort] $(ts_utc) FEHLER: Prompt-Datei $MAIL_SORT_PROMPT_FILE fehlt."
    return 1
  fi
  if [ ! -f "$MAIL_SORT_MCP_CONFIG" ]; then
    echo "[mail-sort] $(ts_utc) FEHLER: MCP-Konfiguration $MAIL_SORT_MCP_CONFIG fehlt (siehe SKILL.md Phase 1b)."
    return 1
  fi
  if grep -qE '__[A-Z_]+__|^# --- Hinweise' "$MAIL_SORT_PROMPT_FILE"; then
    echo "[mail-sort] $(ts_utc) FEHLER: Prompt-Datei enthaelt noch Platzhalter oder den Hinweis-Kommentarblock. Lauf abgebrochen."
    return 1
  fi

  start_epoch="$(date +%s)"
  run_start="$(fmt_epoch "$start_epoch")"
  if [ "$full" -eq 0 ]; then
    since="$(read_watermark)"
    if [ -z "$since" ] && [ ! -s "$MAIL_SORT_STATE_FILE" ]; then first_since="$MAIL_SORT_FIRST_RUN_SINCE"; fi
  fi
  if [ -n "$since" ]; then mode="since $since"; else mode="Erstlauf/Vollauf"; fi
  echo "[mail-sort] $run_start Starte Sortierlauf ($mode, via $CLAUDE_BIN)..."
  if [ "${#TIMEOUT_CMD[@]}" -eq 0 ]; then
    echo "[mail-sort] Hinweis: weder timeout noch gtimeout gefunden, Lauf ohne Zeitlimit."
  fi

  # Nur stdout wird ausgewertet; stderr geht direkt ins Log (Aufrufer leitet 2>&1 um).
  output="$(build_prompt "$run_start" "$since" "$first_since" \
    | ${TIMEOUT_CMD[@]+"${TIMEOUT_CMD[@]}"} "$CLAUDE_BIN" -p \
      --permission-mode dontAsk \
      --tools "" \
      --strict-mcp-config --mcp-config "$MAIL_SORT_MCP_CONFIG" \
      --allowedTools "${MAIL_SORT_ALLOWED_TOOLS[@]}" \
      --disallowedTools "${MAIL_SORT_DISALLOWED_TOOLS[@]}")"
  rc=$?
  printf '%s\n' "$output"

  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    echo "[mail-sort] $(ts_utc) Timeout nach ${MAIL_SORT_RUN_TIMEOUT_SECONDS}s, Watermark NICHT aktualisiert."
    return 1
  fi

  # Nur die letzte nicht-leere Zeile zaehlt (CR, Leerzeichen, Markdown-Zeichen ignoriert).
  last_line="$(printf '%s\n' "$output" | tr -d '\r' | sed -e 's/[*`[:space:]]//g' | grep -v '^$' | tail -n1)"
  if [ "$rc" -eq 0 ] && [ "$last_line" = "$MAIL_SORT_DONE_MARKER" ]; then
    printf '%s\n' "$(fmt_epoch $((start_epoch - MAIL_SORT_STATE_MARGIN_SECONDS)))" > "$MAIL_SORT_STATE_FILE.tmp" \
      && mv -f "$MAIL_SORT_STATE_FILE.tmp" "$MAIL_SORT_STATE_FILE"
    echo "[mail-sort] $(ts_utc) Lauf beendet (Watermark aktualisiert auf $(cat "$MAIL_SORT_STATE_FILE"))."
    return 0
  fi
  echo "[mail-sort] $(ts_utc) Lauf unvollstaendig oder mit Fehler beendet (Exit $rc, Abschlussmarke ${MAIL_SORT_DONE_MARKER} fehlt als letzte Zeile), Watermark NICHT aktualisiert."
  return 1
}

ONCE=0
FULL=0
for arg in "$@"; do
  case "$arg" in
    --once) ONCE=1 ;;
    --full) FULL=1 ;;
    *) echo "Unbekanntes Argument: $arg (erlaubt: --once, --full)" >&2; exit 2 ;;
  esac
done

if [ "$ONCE" -eq 1 ]; then
  rotate_log
  if ! acquire_lock; then
    echo "[mail-sort] Ein anderer Lauf ist aktiv (Lock $LOCK_DIR). Abbruch." | tee -a "$MAIL_SORT_LOG_FILE"
    exit 3
  fi
  run_once "$FULL" 2>&1 | tee -a "$MAIL_SORT_LOG_FILE"
  exit "${PIPESTATUS[0]}"
fi

# Endlosschleife: --full gilt nur fuer den ersten Durchlauf.
if [ -n "$MAIL_SORT_FIRST_RUN_AT" ] && [ ! -s "$MAIL_SORT_STATE_FILE" ]; then
  hh="${MAIL_SORT_FIRST_RUN_AT%%:*}"; mm="${MAIL_SORT_FIRST_RUN_AT##*:}"
  now_sod=$(( 10#$(date +%H) * 3600 + 10#$(date +%M) * 60 + 10#$(date +%S) ))
  wait_s=$(( 10#$hh * 3600 + 10#$mm * 60 - now_sod ))
  [ "$wait_s" -lt 0 ] && wait_s=$(( wait_s + 86400 ))
  echo "[mail-sort] $(ts_utc) Warte ${wait_s}s bis zum ersten geplanten Lauf um ${MAIL_SORT_FIRST_RUN_AT}..." >> "$MAIL_SORT_LOG_FILE"
  sleep "$wait_s"
fi

while true; do
  rotate_log
  if acquire_lock; then
    run_once "$FULL" >> "$MAIL_SORT_LOG_FILE" 2>&1 || true
    cleanup
  else
    echo "[mail-sort] $(ts_utc) Lauf uebersprungen, anderer Lauf aktiv." >> "$MAIL_SORT_LOG_FILE"
  fi
  FULL=0
  sleep "$MAIL_SORT_INTERVAL_SECONDS"
done
