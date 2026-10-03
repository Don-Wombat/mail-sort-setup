**Deutsch** | [English](#english)

# Sicherheit

`mail-sort-setup` richtet eine automatische E-Mail-Sortierung ein, die auf dein Postfach zugreift. Deshalb ist hier genau beschrieben, was geschützt ist, und was **nicht**.

## Was der Skill absichert

- **Kein Senden, Weiterleiten, Löschen.** Der Skill lässt den `[emails.outgoing]`-Block (SMTP) in der Konfiguration des Mail-Servers standardmäßig weg. Ohne Versand-Zugangsdaten kann der Server nicht senden, egal was Claude versucht.
- **Eingeschränkte Werkzeuge.** Jeder automatische Lauf startet Claude im Modus `dontAsk` (Nicht-Erlaubtes wird abgelehnt), ohne eingebaute Werkzeuge (`--tools ""`), nur mit dem Mail-MCP-Server aus der Projektdatei `mail-mcp.json` (`--strict-mcp-config`, andere MCP-Server werden nicht geladen) und mit einer festen Liste erlaubter Mail-Werkzeuge: Konten und Ordner auflisten, Mail-Kopfdaten (Absender, Betreff, Datum) lesen, Mails verschieben und Tags setzen. Zusätzlich sind Senden, Weiterleiten, Löschen, Archivieren, Flags setzen, Mail-Inhalte und Anhänge abrufen explizit gesperrt. Eine reine Erlaubnisliste allein würde andere Werkzeuge nicht sperren — erst die Kombination tut das.
- **Im Zweifel nichts tun.** Mails ohne eindeutige Regel bleiben im Posteingang.
- **Testlauf vor Automatisierung.** Nichts läuft automatisch, bevor du den ersten Lauf geprüft hast.

Details: Abschnitt 0 in `skills/setup/SKILL.md`.

## Was nicht abgesichert ist (bekannte Grenzen)

- **Der Mail-Server hat keinen Nur-Lesen-Modus.** Die genannten Schutzmaßnahmen (fehlendes SMTP, Werkzeugliste) sind die einzigen Sperren. Nur das Senden ist auch serverseitig unmöglich (kein SMTP); für Löschen und Verschieben in beliebige Ordner gibt es serverseitig keine Sperre, dort greifen allein die Werkzeugliste des Loops und die Prompt-Regeln. Die Sperren greifen über die Kommandozeilen-Optionen des Loops; ändere sie nicht, ohne die Folgen zu bewerten. Der Loop verlangt eine Claude-Code-Version, die `--permission-mode dontAsk`, `--tools` und `--strict-mcp-config` kennt (Phase 0 des Skills prüft das).
- **E-Mails sind fremde Eingaben.** Ein Absender kann Text in Betreff oder Absendername schreiben, der Claude zu falschem Verhalten verleiten soll (Prompt Injection). Der Prompt behandelt Mail-Daten ausdrücklich als Daten, nicht als Anweisungen, und erlaubt Verschieben nur in die festgelegten Zielordner (nie Papierkorb, Spam, Gesendet, Entwürfe, Archiv). Wegen der eingeschränkten Werkzeuge ist der schlimmste Fall eine falsch verschobene oder falsch markierte Mail, kein Versand und keine Datenabgabe nach außen. Verschobene Mails lassen sich manuell zurückschieben.
- **Verschieben kann wie Löschen wirken.** Technisch kann der Server auch in den Papierkorb verschieben; der Lauf tut das nur nicht, weil der Prompt es verbietet. Wenn du eine Regel schreibst, die Mails in den Papierkorb verschiebt, sind sie dort nur so lange wiederherstellbar, wie dein Anbieter den Papierkorb aufbewahrt.
- **Zugangsdaten liegen im Klartext.** Das Passwort steht in der `config.toml` des Mail-Servers. Verwende ein **App-Passwort** statt deines Hauptpassworts, setze restriktive Dateirechte (z. B. `chmod 600`, unter Windows per `icacls` nur für deinen Benutzer), und lege die Datei **nie** in ein Git-Repository oder teile sie.
- **Passwörter gehören nicht in den Chat.** Alles, was im Chat steht, landet im Gesprächsprotokoll (Transkript) auf der Festplatte. Der Skill schreibt die Config deshalb mit einem Platzhalter; du trägst das App-Passwort selbst in deinem Terminal ein. Hast du es doch einmal im Chat genannt: App-Passwort beim Provider widerrufen und neu erzeugen.
- **Der Lauf-Log enthält Absender-Domains.** `mail-sort.log` zeigt Domains und Anzahlen unsortierter Mails (angelegt mit restriktiven Rechten, ab 5 MB rotiert). Gib den Log nicht ungeprüft weiter.
- **Der Mail-Server hat keine eigene Anmeldung.** Im Docker-Pfad ist er per HTTP im Container-Netz erreichbar. Wer ihn erreicht, kann alle seine Werkzeuge nutzen, auch Löschen. Veröffentliche seinen Port nicht nach außen und hänge ihn in ein **eigenes Docker-Netz**, in dem nur er und der Container des Loops hängen (kein gemeinsames Netz mit anderen Diensten oder einem Reverse Proxy).
- **Nutzungslimits und Fehler.** Läuft ein automatischer Lauf nicht durch, bleibt die Mail einfach liegen und wird beim nächsten Lauf erneut betrachtet. Das ist ein Ausfall, kein Sicherheitsproblem.

---

# English

[Deutsch](#sicherheit) | **English**

# Security

`mail-sort-setup` sets up an automatic email sorting that accesses your mailbox. This page describes exactly what is protected, and what is **not**.

## What the skill protects

- **No sending, forwarding or deleting.** By default the skill leaves out the `[emails.outgoing]` block (SMTP) in the mail server's configuration. Without sending credentials the server cannot send, no matter what Claude tries.
- **Restricted tools.** Every automatic run starts Claude in `dontAsk` mode (anything not allowed is denied), without built-in tools (`--tools ""`), with only the mail MCP server from the project file `mail-mcp.json` (`--strict-mcp-config`, no other MCP servers are loaded) and with a fixed list of allowed mail tools: list accounts and folders, read mail headers (sender, subject, date), move mails and set tags. In addition, sending, forwarding, deleting, archiving, setting flags and fetching mail bodies or attachments are explicitly denied. An allow list alone would not block other tools — only the combination does.
- **When in doubt, do nothing.** Mails without a clear rule stay in the inbox.
- **Test run before automation.** Nothing runs automatically until you have reviewed the first run.

Details: section 0 in `skills/setup/SKILL.md`.

## What is not protected (known limits)

- **The mail server has no read-only mode.** The measures above (missing SMTP, tool list) are the only barriers. Only sending is also impossible server-side (no SMTP); for deleting and for moving into arbitrary folders there is no server-side barrier, only the loop's tool list and the prompt rules apply. The restrictions are enforced through the loop's command-line options; do not change them without assessing the consequences. The loop requires a Claude Code version that knows `--permission-mode dontAsk`, `--tools` and `--strict-mcp-config` (phase 0 of the skill checks this).
- **Emails are untrusted input.** A sender can put text in the subject or sender name that tries to mislead Claude (prompt injection). The prompt explicitly treats mail data as data, not instructions, and only allows moving into the configured target folders (never trash, spam, sent, drafts, archive). Because of the restricted tools, the worst case is a wrongly moved or wrongly tagged mail — no sending and no data leaving your account. Moved mails can be moved back manually.
- **Moving can act like deleting.** Technically the server can also move into the trash; the run only avoids it because the prompt forbids it. If you write a rule that moves mails to the trash, they are only recoverable for as long as your provider keeps the trash.
- **Credentials are stored in plain text.** The password is in the mail server's `config.toml`. Use an **app password** instead of your main password, set restrictive file permissions (e.g. `chmod 600`, on Windows via `icacls` for your user only), and **never** put the file in a Git repository or share it.
- **Passwords do not belong in the chat.** Everything in the chat ends up in the conversation transcript on disk. The skill therefore writes the config with a placeholder; you enter the app password yourself in your own terminal. If you did mention it in the chat: revoke the app password at your provider and create a new one.
- **The run log contains sender domains.** `mail-sort.log` shows domains and counts of unsorted mails (created with restrictive permissions, rotated at 5 MB). Do not share the log unreviewed.
- **The mail server has no login of its own.** In the Docker path it is reachable over HTTP inside the container network. Anyone who can reach it can use all its tools, including delete. Do not publish its port to the outside and put it in a **dedicated Docker network** containing only it and the loop's container (no network shared with other services or a reverse proxy).
- **Usage limits and errors.** If an automatic run does not complete, the mail simply stays where it is and is considered again on the next run. That is an outage, not a security issue.
