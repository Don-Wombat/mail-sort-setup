# Changelog

## 1.1.0

Überarbeitung nach externem Review.

- Loop: gehärteter `claude -p`-Aufruf (`--permission-mode dontAsk`, `--tools ""`,
  `--strict-mcp-config` mit `mail-mcp.json`, Allow-/Deny-Listen als Arrays,
  Prompt per stdin).
- Paging: `before=<Laufstart>` zusätzlich zu `since`, Seiten rückwärts, max.
  100 IDs je `move_emails`.
- Abschlussmarke nur als letzte (normalisierte) Zeile; `--full` für einen
  Vollauf ohne Watermark; Lock, Zeitlimit, atomarer Watermark mit Marge,
  Log-Rotation, `MAIL_SORT_CLAUDE_BIN`, `MAIL_SORT_FIRST_RUN_AT`.
- Skill: neue Phase 1b (Projektordner), Passwort nie im Chat, Zielordner-
  Prüfung per `list_mailboxes`, ein Projekt für alle Konten, Docker-Pfad
  präzisiert, Version pinnen.
- Templates: gültige Timer-Syntax, Service-Timeout, Cron ohne Doppel-
  Logging, `config.toml.example` mit `allowed_recipients = []`, neue
  `mail-mcp.http.json`/`mail-mcp.stdio.json`.
- Docs: SECURITY.md/README ergänzt.
- Hinweis: Der Docker-Pfad muss mit 1.1.0 erneut gegen ein echtes Konto
  validiert werden.

## 1.0.0

Erste Veröffentlichung.
