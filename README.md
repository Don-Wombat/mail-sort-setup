# mail-sort-setup

Claude-Code-Skill: geführte Einrichtung einer automatischen, **read-only** E-Mail-Sortierung für beliebige IMAP-Konten (Gmail, GMX, Web.de, Outlook, ...). Claude liest Mails und verschiebt/markiert sie zwischen den eigenen Ordnern — es wird nie etwas gesendet, endgültig gelöscht oder weitergeleitet.

- `SKILL.md` — der Skill selbst (Interview, Einrichtung, Testlauf, Rückfrage-Runde)
- `templates/` — Vorlagen (Prompt, Loop-Skript, systemd/cron, `config.toml`)
- `INSTALL.md` — ausführliche Installationsanleitung

## Schnellinstallation

```bash
git clone <dieses-repo> ~/.claude/skills/mail-sort-setup
```

Danach in Claude Code `/mail-sort-setup` aufrufen (ggf. neue Session öffnen). Der Verzeichnisname muss `mail-sort-setup` heißen. Mehr dazu in `INSTALL.md`.
