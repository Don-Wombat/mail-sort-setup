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

# --- Anpassen ---------------------------------------------------------
MAIL_SORT_PROMPT_FILE="$(dirname "$0")/mail-sort-prompt.txt"
MAIL_SORT_LOG_FILE="$(dirname "$0")/mail-sort.log"
MAIL_SORT_STATE_FILE="$(dirname "$0")/mail-sort-last-run.txt"
MAIL_SORT_INTERVAL_SECONDS=14400   # Abstand zwischen automatischen Laeufen (Phase 5). 14400 = 4h.
MAIL_SORT_INITIAL_DELAY_SECONDS=0  # >0, falls der ERSTE Lauf nicht sofort starten soll (Phase 5).
# Nur Lesen/Verschieben/Markieren -- siehe SKILL.md Abschnitt 0. NICHT
# erweitern, ohne die Sicherheitsbegruendung dort neu zu bewerten.
MAIL_SORT_ALLOWED_TOOLS="mcp__mail__list_available_accounts mcp__mail__list_emails_metadata mcp__mail__list_mailboxes mcp__mail__list_email_tags mcp__mail__move_emails mcp__mail__set_email_tags"
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
  local run_start prompt since_ts
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

  if "$CLAUDE_BIN" -p "$prompt" --allowedTools $MAIL_SORT_ALLOWED_TOOLS; then
    echo "$run_start" > "$MAIL_SORT_STATE_FILE"
    echo "[mail-sort] $(date -u +%Y-%m-%dT%H:%M:%SZ) Lauf beendet (Watermark aktualisiert auf $run_start)."
  else
    echo "[mail-sort] $(date -u +%Y-%m-%dT%H:%M:%SZ) Lauf mit Fehler beendet, Watermark NICHT aktualisiert."
  fi
}

if [ "${1:-}" = "--once" ]; then
  run_once 2>&1 | tee -a "$MAIL_SORT_LOG_FILE"
  exit 0
fi

if [ "$MAIL_SORT_INITIAL_DELAY_SECONDS" -gt 0 ]; then
  echo "[mail-sort] Warte ${MAIL_SORT_INITIAL_DELAY_SECONDS}s bis zum ersten geplanten Lauf..." >> "$MAIL_SORT_LOG_FILE"
  sleep "$MAIL_SORT_INITIAL_DELAY_SECONDS"
fi

while true; do
  run_once >> "$MAIL_SORT_LOG_FILE" 2>&1
  sleep "$MAIL_SORT_INTERVAL_SECONDS"
done
