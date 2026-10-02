**Deutsch** | [English](#english)

# mail-sort-setup

Claude-Code-Skill: geführte Einrichtung einer automatischen, **read-only** E-Mail-Sortierung für beliebige IMAP-Konten (Gmail, GMX, Web.de, Outlook, ...). Claude liest Mails und verschiebt/markiert sie zwischen den eigenen Ordnern — es wird nie etwas gesendet, endgültig gelöscht oder weitergeleitet.

- `skills/setup/SKILL.md` — der Skill selbst (Interview, Einrichtung, Testlauf, Rückfrage-Runde)
- `skills/setup/templates/` — Vorlagen (Prompt, Loop-Skript, systemd/cron, `config.toml`, Windows-Varianten unter `windows/`)
- `.claude-plugin/` — Plugin- und Marketplace-Beschreibung (für die Installation über Claude Code)
- `INSTALL.md` — kurze Installationsanleitung als eigene Datei

## Voraussetzung

Claude Code muss entweder

- in einem Docker-Container laufen, der abgestürzte/beendete Sessions automatisch neu startet (self-healing), **oder**
- als lokale Installation auf dem eigenen Rechner laufen (dann übernimmt Cron/systemd/launchd die Zeitsteuerung, keine Docker-Voraussetzung). **Windows wird nativ unterstützt:** dort laufen Loop und Zeitsteuerung über PowerShell und die Windows-Aufgabenplanung, Git Bash oder WSL sind nicht nötig.

## Installation (einmalig)

Auf dem Rechner/Server, auf dem Claude Code läuft (Docker-Container oder lokale Installation), im Terminal:

```bash
claude plugin marketplace add Don-Wombat/mail-sort-setup
claude plugin install mail-sort-setup@mail-sort-setup
```

Oder direkt in einer laufenden Claude-Code-Session:

```
/plugin marketplace add Don-Wombat/mail-sort-setup
/plugin install mail-sort-setup@mail-sort-setup
```

Falls der Skill nicht sofort auftaucht: `/reload-plugins` eingeben oder Claude Code neu starten. Updates später mit `claude plugin update mail-sort-setup@mail-sort-setup`.

**Alternative ohne Marketplace** (Git-Clone; Claude Code lädt den Ordner als Plugin, der Ordnername ist frei wählbar):

```bash
git clone https://github.com/Don-Wombat/mail-sort-setup.git ~/.claude/skills/mail-sort-setup
```

## Nutzen

In einer Claude-Code-Session einfach eingeben:

```
/mail-sort-setup:setup
```

Claude führt dann durch ein Interview (E-Mail-Konten, IMAP-Zugangsdaten, gewünschte Zielordner, Zeitplan) und richtet alles selbst ein — inklusive eines Testlaufs, bei dem du das Ergebnis erst prüfst und korrigieren kannst, und einer Rückfrage-Runde danach (was blieb unsortiert, ist etwas falsch gelandet), bevor irgendetwas automatisch läuft.

## Was du selbst bereithalten solltest

- E-Mail-Adresse(n), die sortiert werden sollen
- IMAP-Zugangsdaten dazu (bei 2FA meist ein separates App-Passwort statt des normalen Kontopassworts — der Skill erklärt das im Interview)
- Eine grobe Vorstellung, welche Ordner du haben möchtest und woran man eine Mail dem jeweiligen Ordner zuordnen könnte (z. B. "alles von Amazon nach Bestellungen") — muss nicht vollständig sein, der Skill fragt gezielt nach.

## Sicherheit, kurz zusammengefasst

Der Skill konfiguriert den zugrundeliegenden Mail-Server standardmäßig **ohne** Versand-Zugangsdaten (SMTP) — Senden ist dadurch nicht nur verboten, sondern technisch unmöglich, unabhängig davon, was Claude tut. Zusätzlich läuft Claude bei jedem automatischen Lauf ohne eingebaute Werkzeuge, nur mit dem Mail-Server und nur mit lesen/verschieben/markieren (alles andere ist ausdrücklich gesperrt). Passwörter trägst du selbst in deinem Terminal ein, nie im Chat. Details: Abschnitt 0 in `skills/setup/SKILL.md`. Bekannte Grenzen: [SECURITY.md](SECURITY.md).

## Bereits live getestet

**Der Sortier-Algorithmus selbst** (Regelwerk, Loop und Prompt-Aufbau, auf denen dieser Skill basiert) läuft bereits seit mehreren Wochen im täglichen Einsatz auf echten Postfächern (GMX und Gmail) und ist dort entsprechend lange erprobt.

**Der Setup-Skill** (die geführte Einrichtung in diesem Repository) wurde dagegen am 2026-09-28 gegen ein echtes Gmail-Konto validiert (Docker-Pfad): Erstlauf-Erkennung, Domain-basierte Klassifizierung, Login-Ausnahmen, die Rückfrage-Runde nach unsortierten Mails — alles wie vorgesehen. Dieses Datum gilt nur für den Test des Setup-Skills, nicht für den Algorithmus. **Seit Version 1.1.0** wurde der Loop deutlich überarbeitet (gehärteter `claude`-Aufruf, Paging, Lock, Zeitlimit); der Docker-Pfad wurde deshalb am 2026-10-02 (Version 1.2.1) erneut gegen ein echtes Gmail-Konto validiert: Server-Container laut Snippet, gehärteter Vollauf über 126 Mails, Abschlussmarke und Watermark; danach nochmals mit einem frischen Test-Konto und frisch gestartetem `mail-mcp-sort`-Container (Vollauf, Folgelauf, Fehlerfall ohne Marke). Dabei fiel die Gmail-Antwort `warning: reconciliation needed` auf (in 1.2.1 behoben). Der lokale Pfad (ohne Docker) ist bisher nur nach Dokumentationslage gebaut, noch nicht real durchgespielt. Der Windows-Pfad (ab 1.2.0) wurde am 2026-10-02 auf einem echten Windows-Runner (GitHub Actions `windows-latest`, Windows PowerShell 5.1 und PowerShell 7) gegen einen Test-Stub von `claude` geprüft: Loop-Verhalten, Argument-Quotierung, `.cmd`-Shim, Timeout mit Prozessbaum-Ende sowie Registrierung in der echten Aufgabenplanung. Zusätzlich lief der Loop am selben Tag auf einer echten Windows-11-VM (deutsch, Windows PowerShell 5.1) mit dem echten `claude.exe` 2.1.286 (Exit 0, Abschlussmarke, Watermark, UTF-8-Log mit Umlauten) und ein echter Start über die Aufgabenplanung (Ergebnis 0, nächster Lauf korrekt berechnet); die `icacls`-Zeile aus der SKILL.md funktioniert auch auf deutschem Windows. Dort lief zunächst kein Mail-Konto mit. Am 2026-10-02 wurde der Windows-Pfad deshalb zusätzlich als Standardnutzer ohne Adminrechte (Installation von `claude` und `uv` per `winget`, Aufgabenplanung, `uvx mcp-email-server` per stdio) gegen ein echtes Gmail-Testkonto bis zur sortierten Mail durchgespielt. Offen: Windows 10, englisches Windows, durch Firmenrichtlinien verwaltete Rechner, macOS und der lokale Linux-Pfad. Von den Mail-Anbietern ist nur Gmail durchgespielt; Outlook/Microsoft 365 ist mit Passwort-Login nicht nutzbar (Microsoft hat Basic Auth für IMAP abgeschaltet, nötig wäre OAuth).

---

# English

[Deutsch](#mail-sort-setup) | **English**

Claude Code skill: guided setup of an automatic, **read-only** email sorting for any IMAP account (Gmail, GMX, Web.de, Outlook, ...). Claude reads emails and moves/tags them between your own folders — it never sends, permanently deletes or forwards anything.

- `skills/setup/SKILL.md` — the skill itself (interview, setup, test run, follow-up round)
- `skills/setup/templates/` — templates (prompt, loop script, systemd/cron, `config.toml`, Windows variants under `windows/`)
- `.claude-plugin/` — plugin and marketplace manifests (for installing through Claude Code)
- `INSTALL.md` — short installation guide as a separate file (German)

## Requirements

Claude Code must either

- run in a Docker container that automatically restarts crashed/stopped sessions (self-healing), **or**
- be installed locally on your own machine (then cron/systemd/launchd handles the scheduling, no Docker required). **Windows is supported natively:** there the loop and the scheduling run via PowerShell and Windows Task Scheduler, no Git Bash or WSL required.

## Installation (one-time)

On the machine/server where Claude Code runs (Docker container or local install), in a terminal:

```bash
claude plugin marketplace add Don-Wombat/mail-sort-setup
claude plugin install mail-sort-setup@mail-sort-setup
```

Or directly inside a running Claude Code session:

```
/plugin marketplace add Don-Wombat/mail-sort-setup
/plugin install mail-sort-setup@mail-sort-setup
```

If the skill does not show up right away: enter `/reload-plugins` or restart Claude Code. Update later with `claude plugin update mail-sort-setup@mail-sort-setup`.

**Alternative without a marketplace** (Git clone; Claude Code loads the folder as a plugin, the folder name is up to you):

```bash
git clone https://github.com/Don-Wombat/mail-sort-setup.git ~/.claude/skills/mail-sort-setup
```

## Usage

In a Claude Code session, simply enter:

```
/mail-sort-setup:setup
```

Claude then walks you through an interview (email accounts, IMAP credentials, target folders, schedule) and sets everything up itself — including a test run where you review the result first and can correct it, and a follow-up round afterwards (what stayed unsorted, did anything land in the wrong place), before anything runs automatically.

## What you should have ready

- The email address(es) to be sorted
- IMAP credentials for them (with 2FA usually a separate app password instead of your normal account password — the skill explains this during the interview)
- A rough idea of which folders you want and how a mail can be assigned to each (e.g. "everything from Amazon goes to Orders") — it does not have to be complete, the skill asks targeted questions.

## Security in short

By default the skill configures the underlying mail server **without** sending credentials (SMTP) — sending is therefore not just forbidden but technically impossible, regardless of what Claude does. In addition, every automatic run starts Claude without built-in tools, with only the mail server, and restricted to reading/moving/tagging (everything else is explicitly denied). You enter passwords yourself in your own terminal, never in the chat. Details: section 0 in `skills/setup/SKILL.md`. Known limits: [SECURITY.md](SECURITY.md#english).

## Already tested live

**The sorting algorithm itself** (rule set, loop and prompt structure that this skill is based on) has been in daily use on real mailboxes (GMX and Gmail) for several weeks and is correspondingly well proven.

**The setup skill** (the guided setup in this repository), on the other hand, was validated on 2026-09-28 against a real Gmail account (Docker path): first-run detection, domain-based classification, login exceptions, the follow-up round for unsorted mails — all as intended. This date applies only to the test of the setup skill, not to the algorithm. **Since version 1.1.0** the loop has been substantially reworked (hardened `claude` invocation, paging, lock, timeout); the Docker path was therefore validated again on 2026-10-02 (version 1.2.1) against a real Gmail account: server container per the snippet, hardened full run over 126 mails, completion marker and watermark. This surfaced Gmail's `warning: reconciliation needed` reply (fixed in 1.2.1). The local path (without Docker) has so far only been built from documentation and not yet run for real. The Windows path (since 1.2.0) was checked on 2026-10-02 on a real Windows runner (GitHub Actions `windows-latest`, Windows PowerShell 5.1 and PowerShell 7) against a stub of `claude`: loop behaviour, argument quoting, `.cmd` shim, timeout with process-tree kill, and registration in the real Task Scheduler. In addition, the loop ran the same day on a real Windows 11 VM (German locale, Windows PowerShell 5.1) with the real `claude.exe` 2.1.286 (exit 0, completion marker, watermark, UTF-8 log with umlauts), and an actual Task Scheduler start worked (result 0, next run computed correctly); the `icacls` line from SKILL.md also works on German Windows. No real mail account was attached in that first run. Later the same day the Windows path was also run as a standard user without admin rights (`claude` and `uv` installed via `winget`, Task Scheduler, `uvx mcp-email-server` over stdio) against a real Gmail test account, through to a sorted mail; the Docker path was additionally re-validated with a fresh test account and a freshly started `mail-mcp-sort` container. Still open: Windows 10, English-language Windows, machines managed by company policy, macOS and the local Linux path. Of the mail providers only Gmail has been run through the skill; Outlook/Microsoft 365 cannot be used with password login (Microsoft disabled basic auth for IMAP; OAuth would be required).
