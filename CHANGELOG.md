# Changelog

## 1.2.1

- Fix (Gmail, per Live-Test gefunden): `move_emails` antwortet bei Gmail auch
  nach geglückter Verschiebung mit `Move result [succeeded: …; warning:
  reconciliation needed]` statt „Successfully …“. Die strenge
  Abschlusszeilen-Regel der Prompt-Vorlage hat deshalb nie `MAIL_SORT_LAUF_OK`
  ausgegeben, der Watermark blieb stehen. Die Regel akzeptiert jetzt diese
  Form (alle IDs unter `succeeded:`, kein `failed:`/`unknown:`).
- SKILL.md: neuer Fallstrick und Hinweis im Testlauf (Phase 6).
- Docker-Pfad gegen ein echtes Gmail-Konto neu validiert (Container-Snippet,
  HTTP-Transport, gehärteter Loop, Vollauf, Marke, Watermark). Zusätzlich mit
  einem frischen Test-Konto und neu gestartetem `mail-mcp-sort`-Container
  (Version 1.11.0, `user: 1000:1000`, Config 600): Host-Prüfung (421 bei
  falschem Host), Vollauf und Folgelauf mit `since`, Abschlussmarke, Watermark,
  Gmail-`reconciliation needed` korrekt akzeptiert, Fehlerfall (Server ohne
  Netz) liefert keine Marke und lässt den Watermark stehen.
- Windows-Pfad auf einem echten Windows-Runner (GitHub Actions) geprüft:
  Windows PowerShell 5.1 und PowerShell 7, kompilierter `claude.exe`-Stub,
  `.cmd`-Shim, Timeout/Tree-Kill, Registrierung in der Aufgabenplanung. Keine
  Skriptänderung nötig. Zusätzlich auf einer echten Windows-11-VM
  (deutsch, PS 5.1) mit dem echten `claude.exe` 2.1.286 und einem echten
  Aufgabenplanung-Start geprüft (leere MCP-Konfiguration, kein Mail-Konto).

## 1.2.0

- Windows nativ: `templates/windows/mail-sort-loop.ps1` (PowerShell 5.1/7,
  gleiches Verhalten wie der Bash-Loop: gesperrter `claude`-Aufruf, Prompt
  per stdin, `-Once`/`-Full`, Lock, Zeitlimit inkl. Kindprozessen,
  Watermark mit Marge, Log-Rotation) und
  `templates/windows/register-mail-sort-task.ps1` für die
  Windows-Aufgabenplanung. Kein Git Bash/WSL nötig.
- SKILL.md: Windows-Erkennung in Phase 0, Windows-Hinweise für Rechte
  (`icacls`), Passwort-Prüfung, uv-Installation, Zeitplan und Testlauf.
- Hinweis: Der Windows-Pfad ist mit PowerShell 7 gegen einen Test-Stub
  geprüft (siehe 1.2.1: inzwischen auch auf echtem Windows).
- Fixes (beide Loops): keine liegengebliebenen Prompt-Temp-Dateien mehr bei
  `--once`; verwaiste Locks werden auch bei wiederverwendeter PID (eigene
  PID oder Lock älter als ein Lauf maximal dauert) erkannt; die
  Abschlussmarke wird nur noch in stdout gesucht, stderr landet nur im Log;
  keine Fehlermeldung der Log-Rotation beim ersten Lauf; unter Windows
  bricht eine fehlgeschlagene Log-Rotation den Lauf nicht mehr ab.
- SKILL.md: `mail-sort.log` wird nicht mehr vorab angelegt (der Loop legt
  es mit restriktiven Rechten an).

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
