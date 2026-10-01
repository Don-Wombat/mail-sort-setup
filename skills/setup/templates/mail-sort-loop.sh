#!/usr/bin/env bash
# Generischer Mail-Sortier-Loop. Von mail-sort-setup aus einer Vorlage
# befuellt -- die MAIL_SORT_*-Variablen unten sind die einzigen Stellen,
# die pro Einrichtung angepasst werden muessen.
#
# Manueller Einzellauf (z.B. fuer den Testlauf in SKILL.md Phase 6):
#   bash mail-sort-loop.sh --once
# Dauerbetrieb (Endlosschleife mit Wartezeit zwischen den Laeufen):
#   bash mail-sort-loop.sh
set -uo pipefail

# In das eigene Verzeichnis wechseln: die MCP-Registrierung (-s local) gilt
# nur fuer dieses Projektverzeichnis, und Cron/systemd starten sonst
# irgendwo anders.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)" || exit 1
cd "$SCRIPT_DIR" || exit 1
# Cron/systemd haben nur einen minimalen PATH -- typische Installationsorte
# von claude/uvx ergaenzen.
export PATH="$PATH:$HOME/.local/bin:$HOME/.npm-global/bin:/usr/local/bin"

# --- Anpassen ---------------------------------------------------------
MAIL_SORT_PROMPT_FILE="$SCRIPT_DIR/mail-sort-prompt.txt"
MAIL_SORT_LOG_FILE="$SCRIPT_DIR/mail-sort.log"
MAIL_SORT_STATE_FILE="$SCRIPT_DIR/mail-sort-last-run.txt"
MAIL_SORT_INTERVAL_SECONDS=14400   # Abstand zwischen automatischen Laeufen (Phase 5). 14400 = 4h.
MAIL_SORT_INITIAL_DELAY_SECONDS=0  # >0, falls der ERSTE Lauf nicht sofort starten soll (Phase 5).
# Nur Lesen/Verschieben/Markieren -- siehe SKILL.md Abschnitt 0. NICHT
# erweitern, ohne die Sicherheitsbegruendung dort neu zu bewerten.
MAIL_SORT_ALLOWED_TOOLS="mcp__mail__list_available_accounts mcp__mail__list_emails_metadata mcp__mail__list_mailboxes mcp__mail__list_email_tags mcp__mail__move_emails mcp__mail__set_email_tags"
# Zusaetzliche Sperre: diese Werkzeuge sind auch dann verboten, wenn die
# Claude-Code-Einstellungen sie sonst freigeben wuerden (deny gewinnt).
MAIL_SORT_DISALLOWED_TOOLS="mcp__mail__send_email mcp__mail__forward_email mcp__mail__delete_emails mcp__mail__archive_emails mcp__mail__save_to_mailbox mcp__mail__download_attachment mcp__mail__get_attachment_content"
# Der Prompt verlangt diese Schlusszeile; nur dann gilt der Lauf als
# vollstaendig und der Watermark wird fortgeschrieben.
MAIL_SORT_DONE_MARKER="MAIL_SORT_LAUF_OK"
# -----------------------------------------------------------------------

# Bevorzugt claude-auto-retry, falls vorhanden (haelt Laeufe bei erreichtem
# Nutzungslimit am Leben statt sie ausfallen zu lassen) -- optional, siehe
# SKILL.md "Bekannte Fallstricke". Faellt sonst automatisch auf normales
# "claude" zurueck, ohne dass hier etwas geaendert werden muss.
if command -v claude-retry >/dev/null 2>&1; then
  CLAUDE_BIN="claude-retry"
else
  CLAUDE_BIN="claude"
fi

run_once() {
  local run_start prompt since_ts output rc
  run_start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  prompt="$(cat "$MAIL_SORT_PROMPT_FILE")"

  if [ -s "$MAIL_SORT_STATE_FILE" ]; then
    since_ts="$(cat "$MAIL_SORT_STATE_FILE")"
    prompt="$prompt

Hinweis: Dies ist KEIN Erstlauf. Übergib bei list_emails_metadata den
Parameter since=\"$since_ts\" (UTC), damit nur Mails geprüft werden, die
seit dem letzten Lauf neu eingegangen sind."
    echo "[mail-sort] $run_start Starte Sortierlauf (since=$since_ts, via $CLAUDE_BIN)..."
  else
    prompt="$prompt

Hinweis: Dies ist der Erstlauf (kein since-Zeitstempel vorhanden). Prüfe
den kompletten aktuellen Bestand in INBOX ohne Zeitfilter."
    echo "[mail-sort] $run_start Starte Sortierlauf (Erstlauf, kompletter Bestand, via $CLAUDE_BIN)..."
  fi

  output="$("$CLAUDE_BIN" -p "$prompt" \
    --allowedTools $MAIL_SORT_ALLOWED_TOOLS \
    --disallowedTools $MAIL_SORT_DISALLOWED_TOOLS 2>&1)"
  rc=$?
  printf '%s\n' "$output"

  if [ "$rc" -eq 0 ] && printf '%s\n' "$output" | grep -qx "$MAIL_SORT_DONE_MARKER"; then
    echo "$run_start" > "$MAIL_SORT_STATE_FILE"
    echo "[mail-sort] $(date -u +%Y-%m-%dT%H:%M:%SZ) Lauf beendet (Watermark aktualisiert auf $run_start)."
  else
    echo "[mail-sort] $(date -u +%Y-%m-%dT%H:%M:%SZ) Lauf unvollstaendig oder mit Fehler beendet (Exit $rc, Abschlussmarke ${MAIL_SORT_DONE_MARKER} fehlt oder Fehler), Watermark NICHT aktualisiert."
    return 1
  fi
}

if [ "${1:-}" = "--once" ]; then
  run_once 2>&1 | tee -a "$MAIL_SORT_LOG_FILE"
  exit "${PIPESTATUS[0]}"
fi

if [ "$MAIL_SORT_INITIAL_DELAY_SECONDS" -gt 0 ]; then
  echo "[mail-sort] Warte ${MAIL_SORT_INITIAL_DELAY_SECONDS}s bis zum ersten geplanten Lauf..." >> "$MAIL_SORT_LOG_FILE"
  sleep "$MAIL_SORT_INITIAL_DELAY_SECONDS"
fi

while true; do
  run_once >> "$MAIL_SORT_LOG_FILE" 2>&1 || true
  sleep "$MAIL_SORT_INTERVAL_SECONDS"
done
