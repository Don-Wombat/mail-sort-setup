**Deutsch** | [English](#english)

# Sicherheit

`mail-sort-setup` richtet eine automatische E-Mail-Sortierung ein, die auf dein Postfach zugreift. Deshalb ist hier genau beschrieben, was geschützt ist, und was **nicht**.

## Was der Skill absichert

- **Kein Senden, Weiterleiten, Löschen.** Der Skill lässt den `[emails.outgoing]`-Block (SMTP) in der Konfiguration des Mail-Servers standardmäßig weg. Ohne Versand-Zugangsdaten kann der Server nicht senden, egal was Claude versucht.
- **Eingeschränkte Werkzeuge.** Jeder automatische Lauf startet Claude mit einer festen Liste erlaubter Werkzeuge: Konten und Ordner auflisten, Mail-Kopfdaten (Absender, Betreff, Datum) lesen, Mails verschieben und Tags setzen. Nicht enthalten sind Senden, Weiterleiten, Löschen, Archivieren, Mail-Inhalte oder Anhänge abrufen.
- **Im Zweifel nichts tun.** Mails ohne eindeutige Regel bleiben im Posteingang.
- **Testlauf vor Automatisierung.** Nichts läuft automatisch, bevor du den ersten Lauf geprüft hast.

Details: Abschnitt 0 in `skills/setup/SKILL.md`.

## Was nicht abgesichert ist (bekannte Grenzen)

- **Der Mail-Server hat keinen Nur-Lesen-Modus.** Die genannten Schutzmaßnahmen (fehlendes SMTP, Werkzeugliste) sind die einzigen Sperren. Die Werkzeugliste greift nur, solange deine Claude-Code-Einstellungen nicht ohnehin weitreichendere Rechte erteilen (z. B. ein Modus, der alles freigibt). Prüfe das bei einer eigenen, ungewöhnlichen Konfiguration.
- **E-Mails sind fremde Eingaben.** Ein Absender kann Text in Betreff oder Absendername schreiben, der Claude zu falschem Verhalten verleiten soll (Prompt Injection). Wegen der eingeschränkten Werkzeuge ist der schlimmste Fall eine falsch verschobene oder falsch markierte Mail, kein Versand und keine Datenabgabe nach außen. Verschobene Mails lassen sich manuell zurückschieben.
- **Verschieben kann wie Löschen wirken.** Wenn du eine Regel schreibst, die Mails in den Papierkorb verschiebt, sind sie dort nur so lange wiederherstellbar, wie dein Anbieter den Papierkorb aufbewahrt.
- **Zugangsdaten liegen im Klartext.** Das Passwort steht in der `config.toml` des Mail-Servers. Verwende ein **App-Passwort** statt deines Hauptpassworts, setze restriktive Dateirechte (z. B. `chmod 600`), und lege die Datei **nie** in ein Git-Repository oder teile sie.
- **Der Mail-Server hat keine eigene Anmeldung.** Im Docker-Pfad ist er per HTTP im Container-Netz erreichbar. Veröffentliche seinen Port nicht nach außen und hänge ihn nur in ein Netz, dem du vertraust.
- **Nutzungslimits und Fehler.** Läuft ein automatischer Lauf nicht durch, bleibt die Mail einfach liegen und wird beim nächsten Lauf erneut betrachtet. Das ist ein Ausfall, kein Sicherheitsproblem.

---

# English

[Deutsch](#sicherheit) | **English**

# Security

`mail-sort-setup` sets up an automatic email sorting that accesses your mailbox. This page describes exactly what is protected, and what is **not**.

## What the skill protects

- **No sending, forwarding or deleting.** By default the skill leaves out the `[emails.outgoing]` block (SMTP) in the mail server's configuration. Without sending credentials the server cannot send, no matter what Claude tries.
- **Restricted tools.** Every automatic run starts Claude with a fixed list of allowed tools: list accounts and folders, read mail headers (sender, subject, date), move mails and set tags. Not included: sending, forwarding, deleting, archiving, fetching mail bodies or attachments.
- **When in doubt, do nothing.** Mails without a clear rule stay in the inbox.
- **Test run before automation.** Nothing runs automatically until you have reviewed the first run.

Details: section 0 in `skills/setup/SKILL.md`.

## What is not protected (known limits)

- **The mail server has no read-only mode.** The measures above (missing SMTP, tool list) are the only barriers. The tool list only holds as long as your Claude Code settings do not already grant broader permissions (e.g. a mode that allows everything). Check this if you use an unusual configuration of your own.
- **Emails are untrusted input.** A sender can put text in the subject or sender name that tries to mislead Claude (prompt injection). Because of the restricted tools, the worst case is a wrongly moved or wrongly tagged mail — no sending and no data leaving your account. Moved mails can be moved back manually.
- **Moving can act like deleting.** If you write a rule that moves mails to the trash, they are only recoverable for as long as your provider keeps the trash.
- **Credentials are stored in plain text.** The password is in the mail server's `config.toml`. Use an **app password** instead of your main password, set restrictive file permissions (e.g. `chmod 600`), and **never** put the file in a Git repository or share it.
- **The mail server has no login of its own.** In the Docker path it is reachable over HTTP inside the container network. Do not publish its port to the outside and only attach it to a network you trust.
- **Usage limits and errors.** If an automatic run does not complete, the mail simply stays where it is and is considered again on the next run. That is an outage, not a security issue.
