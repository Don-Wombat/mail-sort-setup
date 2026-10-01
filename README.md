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
git clone <dieses-repo> ~/.claude/skills/mail-sort-setup
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

Der Skill konfiguriert den zugrundeliegenden Mail-Server standardmäßig **ohne** Versand-Zugangsdaten (SMTP) — Senden ist dadurch nicht nur verboten, sondern technisch unmöglich, unabhängig davon, was Claude tut. Zusätzlich ist Claude bei jedem automatischen Lauf auf lesen/verschieben/markieren beschränkt. Details: Abschnitt 0 in `SKILL.md`.

## Bereits live getestet

Am 2026-09-28 gegen ein echtes Gmail-Konto validiert (Docker-Pfad): Erstlauf-Erkennung, Domain-basierte Klassifizierung, Login-Ausnahmen, die Rückfrage-Runde nach unsortierten Mails — alles wie vorgesehen. Der lokale Pfad (ohne Docker) ist bisher nur nach Dokumentationslage gebaut, noch nicht real durchgespielt.
