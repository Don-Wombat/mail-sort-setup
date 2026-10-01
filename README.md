**Deutsch** | [English](#english)

# mail-sort-setup

Claude-Code-Skill: geführte Einrichtung einer automatischen, **read-only** E-Mail-Sortierung für beliebige IMAP-Konten (Gmail, GMX, Web.de, Outlook, ...). Claude liest Mails und verschiebt/markiert sie zwischen den eigenen Ordnern — es wird nie etwas gesendet, endgültig gelöscht oder weitergeleitet.

- `SKILL.md` — der Skill selbst (Interview, Einrichtung, Testlauf, Rückfrage-Runde)
- `templates/` — Vorlagen (Prompt, Loop-Skript, systemd/cron, `config.toml`)
- `INSTALL.md` — dieselbe Installationsanleitung als eigene Datei

## Voraussetzung

Claude Code muss entweder

- in einem Docker-Container laufen, der abgestürzte/beendete Sessions automatisch neu startet (self-healing), **oder**
- als lokale Installation auf dem eigenen Rechner laufen (dann übernimmt Cron/systemd/launchd die Zeitsteuerung, keine Docker-Voraussetzung).

## Installation (einmalig)

Auf dem Rechner/Server, auf dem Claude Code läuft (Docker-Container oder lokale Installation):

```bash
git clone https://github.com/Don-Wombat/mail-sort-setup.git ~/.claude/skills/mail-sort-setup
```

Der Ordnername unter `~/.claude/skills/` **muss `mail-sort-setup` heißen**, exakt wie in der `name:`-Zeile im Frontmatter von `SKILL.md` — danach erscheint der Skill automatisch in Claude Code. Falls er nicht sofort in der Liste auftaucht, Claude Code neu starten oder eine neue Session öffnen.

Alternativ ohne Git: den kompletten Ordner (inkl. `SKILL.md` und `templates/`) kopieren:

```bash
mkdir -p ~/.claude/skills/mail-sort-setup
cp -r /pfad/zu/mail-skill/* ~/.claude/skills/mail-sort-setup/
```

## Nutzen

In einer Claude-Code-Session einfach eingeben:

```
/mail-sort-setup
```

Claude führt dann durch ein Interview (E-Mail-Konten, IMAP-Zugangsdaten, gewünschte Zielordner, Zeitplan) und richtet alles selbst ein — inklusive eines Testlaufs, bei dem du das Ergebnis erst prüfst und korrigieren kannst, und einer Rückfrage-Runde danach (was blieb unsortiert, ist etwas falsch gelandet), bevor irgendetwas automatisch läuft.

## Was du selbst bereithalten solltest

- E-Mail-Adresse(n), die sortiert werden sollen
- IMAP-Zugangsdaten dazu (bei 2FA meist ein separates App-Passwort statt des normalen Kontopassworts — der Skill erklärt das im Interview)
- Eine grobe Vorstellung, welche Ordner du haben möchtest und woran man eine Mail dem jeweiligen Ordner zuordnen könnte (z. B. "alles von Amazon nach Bestellungen") — muss nicht vollständig sein, der Skill fragt gezielt nach.

## Sicherheit, kurz zusammengefasst

Der Skill konfiguriert den zugrundeliegenden Mail-Server standardmäßig **ohne** Versand-Zugangsdaten (SMTP) — Senden ist dadurch nicht nur verboten, sondern technisch unmöglich, unabhängig davon, was Claude tut. Zusätzlich ist Claude bei jedem automatischen Lauf auf lesen/verschieben/markieren beschränkt. Details: Abschnitt 0 in `SKILL.md`. Bekannte Grenzen und wie du eine Sicherheitslücke meldest: [SECURITY.md](SECURITY.md).

## Bereits live getestet

Am 2026-09-28 gegen ein echtes Gmail-Konto validiert (Docker-Pfad): Erstlauf-Erkennung, Domain-basierte Klassifizierung, Login-Ausnahmen, die Rückfrage-Runde nach unsortierten Mails — alles wie vorgesehen. Der lokale Pfad (ohne Docker) ist bisher nur nach Dokumentationslage gebaut, noch nicht real durchgespielt.

---

# English

[Deutsch](#mail-sort-setup) | **English**

Claude Code skill: guided setup of an automatic, **read-only** email sorting for any IMAP account (Gmail, GMX, Web.de, Outlook, ...). Claude reads emails and moves/tags them between your own folders — it never sends, permanently deletes or forwards anything.

- `SKILL.md` — the skill itself (interview, setup, test run, follow-up round)
- `templates/` — templates (prompt, loop script, systemd/cron, `config.toml`)
- `INSTALL.md` — the same installation guide as a separate file (German)

## Requirements

Claude Code must either

- run in a Docker container that automatically restarts crashed/stopped sessions (self-healing), **or**
- be installed locally on your own machine (then cron/systemd/launchd handles the scheduling, no Docker required).

## Installation (one-time)

On the machine/server where Claude Code runs (Docker container or local install):

```bash
git clone https://github.com/Don-Wombat/mail-sort-setup.git ~/.claude/skills/mail-sort-setup
```

The folder name under `~/.claude/skills/` **must be `mail-sort-setup`**, exactly as in the `name:` line of the `SKILL.md` frontmatter — the skill then shows up in Claude Code automatically. If it does not appear right away, restart Claude Code or open a new session.

Alternatively, without Git: copy the whole folder (including `SKILL.md` and `templates/`):

```bash
mkdir -p ~/.claude/skills/mail-sort-setup
cp -r /path/to/mail-skill/* ~/.claude/skills/mail-sort-setup/
```

## Usage

In a Claude Code session, simply enter:

```
/mail-sort-setup
```

Claude then walks you through an interview (email accounts, IMAP credentials, target folders, schedule) and sets everything up itself — including a test run where you review the result first and can correct it, and a follow-up round afterwards (what stayed unsorted, did anything land in the wrong place), before anything runs automatically.

## What you should have ready

- The email address(es) to be sorted
- IMAP credentials for them (with 2FA usually a separate app password instead of your normal account password — the skill explains this during the interview)
- A rough idea of which folders you want and how a mail can be assigned to each (e.g. "everything from Amazon goes to Orders") — it does not have to be complete, the skill asks targeted questions.

## Security in short

By default the skill configures the underlying mail server **without** sending credentials (SMTP) — sending is therefore not just forbidden but technically impossible, regardless of what Claude does. In addition, Claude is restricted to reading/moving/tagging on every automatic run. Details: section 0 in `SKILL.md`. Known limits and how to report a vulnerability: [SECURITY.md](SECURITY.md#english).

## Already tested live

Validated on 2026-09-28 against a real Gmail account (Docker path): first-run detection, domain-based classification, login exceptions, the follow-up round for unsorted mails — all as intended. The local path (without Docker) has so far only been built from documentation and not yet run for real.
