# mail-sort-setup installieren

Claude-Code-Plugin: geführte Einrichtung für automatische, read-only
E-Mail-Sortierung (liest Mails, verschiebt sie zwischen deinen eigenen
Ordnern, markiert sie -- sendet, löscht und leitet **nie** etwas weiter).
Ausführliche Beschreibung, Voraussetzungen und Sicherheitshinweise: siehe
[README.md](README.md) und [SECURITY.md](SECURITY.md).

## Installation (einmalig)

Auf dem Rechner/Server, auf dem Claude Code läuft (Linux, macOS oder Windows; unter Windows in PowerShell oder CMD):

```bash
claude plugin marketplace add Don-Wombat/mail-sort-setup
claude plugin install mail-sort-setup@mail-sort-setup
```

Voraussetzung: eine aktuelle Claude-Code-Version (der Loop nutzt `--permission-mode dontAsk`, `--tools` und `--strict-mcp-config`; der Skill prüft das in Phase 0).

Falls der Skill nicht sofort auftaucht: in Claude Code `/reload-plugins`
eingeben oder neu starten.

Alternative ohne Marketplace:

```bash
git clone https://github.com/Don-Wombat/mail-sort-setup.git ~/.claude/skills/mail-sort-setup
```

## Nutzen

In einer Claude-Code-Session einfach eingeben:

```
/mail-sort-setup:setup
```

Claude führt dann durch ein Interview und richtet alles selbst ein --
inklusive Testlauf und Rückfrage-Runde, bevor irgendetwas automatisch läuft.

## Bereits live getestet

Der Sortier-Algorithmus selbst läuft seit mehreren Wochen im täglichen
Einsatz (GMX und Gmail). Der Setup-Skill wurde am 2026-09-28 gegen ein
echtes Gmail-Konto validiert (Docker-Pfad); dieses Datum gilt nur für den
Setup-Skill. Der lokale Pfad (ohne Docker) ist bisher nur nach
Dokumentationslage gebaut, noch nicht real durchgespielt; Der Docker-Pfad wurde nach der Überarbeitung des Loops (ab 1.1.0) am 2026-10-02 (Version 1.2.1) erneut mit echtem Gmail-Konto validiert. Der Windows-Pfad (ab 1.2.0) lief am selben Tag auf einem echten Windows-Runner und auf einer Windows-11-VM, dort auch als Standardnutzer ohne Adminrechte mit echtem Gmail-Lauf. Nicht getestet: Windows 10, englisches Windows, durch Firmenrichtlinien verwaltete Rechner, macOS, lokaler Linux-Pfad. Von den Mail-Anbietern ist nur Gmail durchgespielt; Outlook/Microsoft 365 funktioniert nicht (kein OAuth).
