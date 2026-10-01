---
name: setup
description: Führt eine geführte, interviewbasierte Einrichtung einer automatischen, read-only E-Mail-Sortierung durch (IMAP via mcp-email-server, periodischer Claude-Lauf). Nutzen, wenn jemand eine automatische Mail-Sortierung durch Claude für sich selbst einrichten möchte, egal ob in einem Docker-Container mit selbstheilenden Claude-Sessions oder mit einer lokalen Claude-Code-Instanz.
---

# Mail-Sort-Setup — geführte Einrichtung

Dieser Skill baut für den Nutzer eine eigenständige, automatische E-Mail-
Sortierung: ein wiederkehrender Claude-Lauf, der neue Mails anhand
selbstdefinierter Regeln in Unterordner einsortiert — **ohne jemals eine
Mail zu senden, zu löschen oder weiterzuleiten.** Das Vorbild ist ein
bereits produktiv laufendes Setup (GMX + Gmail, seit Wochen fehlerfrei im
Betrieb), hier verallgemeinert für beliebige IMAP-Konten und beliebige
Umgebungen.

**Zielgruppe dieses Skills selbst:** unerfahrene Nutzer. Sprich während der
Einrichtung in einfachen Worten, erkläre *warum* du etwas fragst, zeig
niemals rohe Passwörter im Chat an (nur entgegennehmen und direkt in die
Config-Datei schreiben), und fasse am Ende in 3-4 Sätzen zusammen, was
jetzt automatisch passiert.

---

## 0. Kernprinzip — nicht verhandelbar

**Diese Automatisierung darf niemals senden, löschen oder weiterleiten.**
Das wird auf zwei unabhängigen Ebenen erzwungen, nicht nur einer:

1. **Serverseitig (stärker):** Der `[emails.outgoing]`-Block (SMTP) wird in
   `config.toml` standardmäßig **weggelassen**. Ohne SMTP-Zugangsdaten kann
   der MCP-Server `send_email`/`forward_email` technisch gar nicht
   ausführen — das ist keine Höflichkeitsregel, sondern eine strukturelle
   Unmöglichkeit.
2. **Clientseitig:** Der generierte Lauf-Loop ruft `claude -p` immer mit
   `--allowedTools` ein, beschränkt auf genau:
   `mcp__mail__list_available_accounts mcp__mail__list_emails_metadata
   mcp__mail__list_mailboxes mcp__mail__list_email_tags
   mcp__mail__move_emails mcp__mail__set_email_tags`
   — explizit **nicht** enthalten: `send_email`, `forward_email`,
   `delete_emails`, `archive_emails`, `save_to_mailbox`,
   `download_attachment`, `get_attachment_content`, `mark_emails_as_read`,
   `set_email_flags`. (`mcp-email-server` hat *keinen* eingebauten
   Read-Only-Modus — diese beiden Ebenen sind der einzige verlässliche Weg.)

**Was "read-only" hier genau bedeutet** (das musst du dem Nutzer explizit
so erklären, nicht nur "read-only" sagen): Mails werden **gelesen**,
zwischen **den eigenen Ordnern desselben Kontos verschoben** und mit
Labels/Tags markiert. Nichts verlässt das Konto, nichts wird
unwiderruflich gelöscht, nichts wird an Dritte verschickt. Verschobene
Mails sind weiterhin da — nur in einem anderen Ordner, jederzeit manuell
zurückverschiebbar.

**Falls der Nutzer ausdrücklich SMTP/Senden für andere Zwecke will:** dann
nur in einem *separaten* MCP-Server-Eintrag, niemals im selben
Account-Block, der von diesem Sortier-Loop benutzt wird. Wenn er darauf
besteht, den Sende-Zugriff im selben Konto zu haben, zusätzlich
`allowed_recipients = []` in `config.toml` setzen (blockiert Senden
serverseitig auch bei vorhandenem SMTP) und das im Abschlussbericht als
Abweichung vom Standard deutlich benennen.

---

## Ablauf-Überblick

0. Umgebung prüfen (Docker-Pfad vs. lokaler Pfad)
1. Interview: Konten, IMAP-Zugang, Ordnerstruktur, Ton (vorsichtig/aggressiv)
2. `mcp-email-server` aufsetzen + bei Claude Code registrieren
3. Sortier-Regeln als Prompt-Datei generieren
4. Eigenes Projekt/Session anlegen (manueller Start, Fehler-Log, Anpassungen)
5. Zeitplan für automatischen Lauf festlegen
6. Manueller Testlauf, gemeinsam mit dem Nutzer geprüft
7. Automatisierung scharfschalten + Abschlussbericht an den Nutzer

---

## Phase 0 — Umgebung feststellen

Frage nicht raten — prüfe zuerst technisch, frage nur wenn unklar:

```bash
[ -f /.dockerenv ] && echo "läuft in Docker" || echo "kein Docker erkennbar"
command -v tmux >/dev/null && echo "tmux verfügbar" || echo "kein tmux"
uname -s   # Linux / Darwin (macOS) / ...
```

- **Docker-Pfad**, wenn `/.dockerenv` existiert (oder der Nutzer bestätigt,
  dass Claude Code in einem Container läuft, der Sessions bei Absturz neu
  startet — frag nach, ob es sowas wie ein `entrypoint.sh` mit
  Neustart-Schleife gibt, das pro Projekt ein eigenes `tmux`-Fenster startet).
- **Lokaler Pfad**, wenn keine Container-Umgebung erkennbar ist — dann
  zählt das Betriebssystem für die Zeitplan-Mechanik (Phase 5).

Falls beides unklar bleibt: **fragen, nicht raten.** Voraussetzung laut
diesem Skill ist eines von beidem — ohne eine Form von Persistenz
(Container-Neustart-Schleife oder OS-Scheduler) kann kein verlässlicher
automatischer Lauf zugesichert werden.

---

## Phase 1 — Interview

Stelle diese Fragen der Reihe nach, nicht alle auf einmal als Wand aus
Text. Erkläre kurz *warum* du etwas brauchst, bevor du fragst.

### 1.1 Konten

Pro E-Mail-Konto:

- E-Mail-Adresse
- IMAP-Host + Port + SSL/TLS (siehe Tabelle unten für bekannte Provider —
  wenn der Provider dort steht, das den Nutzer nicht extra fragen)
- Passwort — **Hinweis geben:** viele Provider (Gmail, GMX, Outlook, ...)
  verlangen bei aktivierter 2-Faktor-Authentifizierung ein separates
  **App-Passwort** statt des normalen Kontopassworts. Erkläre kurz, wo man
  das üblicherweise findet ("Konto-Sicherheitseinstellungen des
  Providers → 'App-Passwörter' oder 'IMAP-Zugriff'"), aber nicht
  provider-spezifisch vorspulen, das ändert sich zu oft.
- **Ton dieses Kontos:** "Ist das ein wichtiges Konto (Bank, Verträge,
  Bewerbungen — lieber vorsichtig, im Zweifel nichts anfassen) oder eher
  ein Wegwerf-/Freizeit-Konto (Gaming, Newsletter, Social Media — darf
  aggressiver aufräumen)?" Das bestimmt später die Formulierung der
  Sortier-Regeln (siehe `templates/mail-sort-prompt.template.txt`).

**Bekannte IMAP-Server (nicht extra abfragen, falls Provider erkannt):**

| Provider | Host | Port | SSL |
|---|---|---|---|
| Gmail | `imap.gmail.com` | 993 | ja |
| GMX | `imap.gmx.net` | 993 | ja |
| Web.de | `imap.web.de` | 993 | ja |
| Outlook/Microsoft 365 | `outlook.office365.com` | 993 | ja |
| Yahoo Mail | `imap.mail.yahoo.com` | 993 | ja |
| iCloud Mail | `imap.mail.me.com` | 993 | ja |

### 1.2 Zielordner & Zuordnungsregeln

Pro Konto: "In welche Unterordner soll einsortiert werden, und woran soll
ich eine Mail als zugehörig erkennen?" Konkret nachfragen:

- Liste der gewünschten Zielordner (z. B. "Rechnungen", "Newsletter",
  "Bestellungen", ...)
- Pro Ordner, falls der Nutzer es nicht von selbst sagt: nach typischen
  Absender-Domains fragen ("welche Absender/Firmen landen normalerweise in
  '<Ordner>'?") — das wird die Kern-Erkennungsregel, exakt wie im
  Referenz-Setup (Domain-Zuordnung statt Volltextsuche, weil zuverlässiger
  und günstiger).
- **Immer erklären:** "Was nicht eindeutig zuordenbar ist, bleibt im
  Posteingang liegen — das System rät nie, im Zweifel passiert nichts."
  Das ist eine Sicherheitseigenschaft, keine Einschränkung, und sollte dem
  Nutzer so kommuniziert werden.
- Bei "wichtigen" Konten (siehe 1.1) zusätzlich fragen: "Gibt es
  zeitkritische Mails (Frist, Mahnung, Kündigungsfrist), die NICHT
  verschoben, sondern nur markiert werden sollen, damit sie im
  Posteingang sichtbar bleiben?" Falls ja: Das braucht ein beschreibbares
  Semantic Tag in `config.toml` (siehe Phase 2) — nicht jeder IMAP-Server
  unterstützt das gleich gut, im Zweifel als optionales Feature behandeln.

### 1.3 Sprache

In welcher Sprache soll die generierte Sortier-Logik/Prompt-Datei verfasst
sein (beeinflusst nur die internen Regeltexte, nicht die Bedienung dieses
Interviews)? Default: gleiche Sprache wie das Interview selbst.

---

## Phase 2 — `mcp-email-server` aufsetzen

Server-Projekt: [ai-zerolab/mcp-email-server](https://github.com/ai-zerolab/mcp-email-server)
(`serverInfo.name` meldet sich als `"email"`). Kein eingebauter Read-Only-
Modus (siehe Phase 0) — Sicherheit kommt aus der Konfiguration selbst.

### Config-Datei

Für jedes Konto aus Phase 1 einen Block nach
`templates/config.toml.example` — **ohne** `[emails.outgoing]`, außer der
Nutzer hat das in 1.1 explizit anders verlangt (siehe Kernprinzip oben).
Zeig die generierte `config.toml` dem Nutzer NICHT mit Klartext-Passwort
im Chat — schreib sie direkt in die Datei, bestätige nur "Konto X
konfiguriert, Passwort gespeichert" ohne den Wert zu wiederholen.

### Docker-Pfad

Eigener Container neben dem bestehenden Claude-Code-Setup, HTTP-Transport:

```yaml
mail-mcp-sort:
  image: ghcr.io/wh1isper/mcp-email-server:latest
  container_name: mail-mcp-sort
  restart: unless-stopped
  command: streamable-http
  environment:
    - MCP_HOST=0.0.0.0
    - MCP_PORT=8000
    - MCP_ALLOWED_HOSTS=mail-mcp-sort:8000,localhost:8000
    - MCP_ALLOWED_ORIGINS=http://mail-mcp-sort:8000
    - MCP_EMAIL_SERVER_CONFIG_PATH=/config/config.toml
  volumes:
    - <config-verzeichnis-des-nutzers>:/config
  networks: [<gleiches-netz-wie-claude-code>]
```

`MCP_EMAIL_SERVER_CONFIG_PATH` ist nötig: ohne diese Variable liest der
Server `~/.config/mcp-email-server/config.toml` im Container und findet die
gemountete Datei nicht. Das Config-Verzeichnis muss für den Container
schreibbar sein (der Server legt dort Hilfsdateien neben der `config.toml`
an). Aus Reproduzierbarkeitsgründen kann das Image statt `latest` auf eine
konkrete Version gepinnt werden.

Kein published Port nötig, wenn Claude Code im selben Docker-Netz hängt —
dann intern über den Containernamen erreichbar. Danach registrieren
(`-s local` gilt nur für das aktuelle Projektverzeichnis: den Befehl **im
Projektverzeichnis aus Phase 4** ausführen, das dafür vorher angelegt
werden muss):

```bash
claude mcp add --transport http mail http://mail-mcp-sort:8000/mcp -s local
```

**Der Registrierungsname muss `mail` lauten** — daraus ergibt sich das
Tool-Präfix `mcp__mail__*`, auf das `--allowedTools` im Loop (Abschnitt 0)
und der Prompt zugeschnitten sind. Jeder andere Name würde dazu führen, dass
alle Tool-Aufrufe abgelehnt werden. Falls der Nutzer bereits einen MCP-Server
namens `mail` für dasselbe Postfach registriert hat, diesen wiederverwenden
(`claude mcp list` prüfen), nicht doppelt anlegen.

### Lokaler Pfad (keine Docker nötig)

```bash
claude mcp add mail -s local -- uvx mcp-email-server@latest stdio
```

`uvx` braucht [uv](https://docs.astral.sh/uv/) — falls nicht installiert,
kurz erklären/installieren lassen. Die Config-Datei liegt dann lokal unter
`~/.config/mcp-email-server/config.toml` (ältere Versionen nutzten
`~/.config/zerolib/mcp_email_server/config.toml`; der Server kopiert die
alte Datei beim ersten Start selbst). Auch hier den `claude mcp add`-Befehl
im Projektverzeichnis aus Phase 4 ausführen.

### Verifizieren

Nach dem Einrichten: `list_available_accounts` aufrufen (im neuen Projekt,
siehe Phase 4) und bestätigen, dass alle Konten aus Phase 1 erscheinen,
bevor es weitergeht.

---

## Phase 3 — Sortier-Regeln generieren

Aus den Antworten von Phase 1.2 eine Prompt-Datei bauen, Vorlage:
`templates/mail-sort-prompt.template.txt`. Grundprinzipien, die immer
gelten, unabhängig vom Nutzer:

- Absenderdomain vor Volltext-Heuristik (zuverlässiger, günstiger).
- "Wichtig" = vorsichtig, Unsicherheit → Posteingang lassen. "Wegwerf" =
  aggressiver sortieren, Risiko gering.
- Zeitkritisches (falls in 1.2 gewünscht) wird **markiert, nicht
  verschoben** — sonst verschwindet der Fristbezug aus dem Blickfeld.
- Am Ende jedes Laufs eine kurze Zusammenfassung ausgeben (wie viele Mails
  wohin verschoben wurden) — landet im Lauf-Log, nicht nur im Chat.

---

## Phase 4 — Eigenes Projekt/Session anlegen

Verzeichnis (Namensvorschlag mit dem Nutzer abstimmen, z. B.
`<konto-kurzname>-mail-sort`) unter dem Projekte-Verzeichnis der
jeweiligen Claude-Code-Installation anlegen mit:

| Datei | Zweck |
|---|---|
| `mail-sort-loop.sh` | aus `templates/mail-sort-loop.sh`, mit den Werten aus Phase 1/5 befüllt |
| `mail-sort-prompt.txt` | aus Phase 3 |
| `mail-sort-last-run.txt` | leer anlegen — Watermark, wird vom Loop selbst befüllt |
| `mail-sort.log` | leer anlegen |
| `README.md` | für den Menschen, siehe unten |

`README.md` muss in einfachen Worten enthalten:

- Was das hier ist und dass es **niemals sendet oder löscht**.
- **Manuell starten:** `bash mail-sort-loop.sh --once` (Loop-Skript
  unterstützt einen Einmal-Modus für Tests/manuelle Läufe, statt der
  Endlosschleife).
- **Fehler ansehen:** `tail -f mail-sort.log`.
- **Anpassen:** welche Zeile in `mail-sort-prompt.txt` für neue
  Ordner/Regeln geändert wird, wie eine neue Mailadresse als weiterer
  `[[emails]]`-Block in `config.toml` ergänzt wird (+ Neustart des
  MCP-Servers danach nötig), wie Uhrzeit/Intervall in `mail-sort-loop.sh`
  bzw. dem Scheduler (Phase 5) geändert wird.
- Wo man diesen Skill erneut aufrufen kann, um die geführte Einrichtung
  für ein weiteres Konto/Projekt zu wiederholen.

Falls Docker-Pfad mit vorhandenem `entrypoint.sh`: dem Nutzer den
konkreten Codeblock zeigen, den er dort ergänzen muss (Muster: eigenes
`tmux`-Fenster, das den Loop startet, analog zu den vorhandenen
Projekt-Fenstern in diesem `entrypoint.sh`). Falls kein `entrypoint.sh` vorhanden: minimal
anleiten, wie man den Loop in einer eigenen `tmux`-Session dauerhaft
laufen lässt (`tmux new-session -d -s mail-sort 'bash mail-sort-loop.sh'`).

---

## Phase 5 — Zeitplan festlegen

Fragen: **"Wann soll der erste automatische Lauf starten, und in welchem
Abstand soll er sich danach wiederholen?"** (z. B. "ab sofort, alle 4
Stunden" oder "täglich um 7 Uhr").

Je nach Umgebung (Phase 0) unterschiedlich umgesetzt:

- **Docker-Pfad / beide Pfade mit tmux-Persistenz:** `mail-sort-loop.sh`
  läuft als Endlosschleife (`sleep <intervall>` zwischen den Läufen, wie
  in `templates/mail-sort-loop.sh`) — die "Startzeit" wird durch einen
  einmaligen `sleep` bis zum gewünschten ersten Zeitpunkt vor der
  Hauptschleife realisiert, falls der Nutzer nicht "sofort" möchte.
- **Lokaler Pfad, Linux mit systemd:** `templates/systemd/mail-sort.service`
  + `templates/systemd/mail-sort.timer` verwenden (Intervall im Timer,
  `OnCalendar=`), unter `~/.config/systemd/user/` ablegen, dann
  `systemctl --user enable --now mail-sort.timer`. User-Timer laufen nur,
  solange der Nutzer eingeloggt ist — soll der Lauf auch ohne Login
  laufen (Server, Abwesenheit): `loginctl enable-linger "$USER"`.
- **Lokaler Pfad, klassisches Cron (Linux/macOS):** Zeile aus
  `templates/crontab-example.txt` anpassen, `crontab -e`.
- **Lokaler Pfad, macOS ohne Cron-Präferenz:** `launchd` ist möglich, aber
  deutlich komplexer als Cron — nur anbieten, wenn der Nutzer das
  ausdrücklich will, sonst Cron empfehlen (niedrigere Einstiegshürde).

In jedem Fall am Ende **den erwarteten nächsten Lauf-Zeitpunkt konkret
nennen** ("Der erste automatische Lauf ist heute um 18:00 Uhr, danach
alle 4 Stunden"), nicht nur die Konfiguration abstrakt beschreiben.

---

## Phase 6 — Testlauf vor Scharfschaltung

**Nicht überspringen, auch wenn der Nutzer es eilig hat.** Vor dem
Aktivieren des automatischen Zeitplans:

1. `bash mail-sort-loop.sh --once` gemeinsam mit dem Nutzer ausführen.
2. Ergebnis zusammen durchgehen: wie viele Mails erkannt, wie viele
   verschoben/markiert, wie viele blieben unangetastet.
3. Dem Nutzer erklären, dass send/delete/forward-Aufrufe durch
   `--allowedTools` bzw. `--disallowedTools` technisch gesperrt sind. Das
   Log (`mail-sort.log`) enthält nur die Textausgabe des Laufs, keine
   Liste der Tool-Aufrufe — den Nachweis liefert also die Sperre selbst,
   nicht das Log. Meldet das Log am Ende die Abschlussmarke
   `MAIL_SORT_LAUF_OK`, ist der Lauf vollständig durchgelaufen; fehlt sie,
   wurde der Watermark bewusst nicht fortgeschrieben.
4. Weiter mit Phase 6b — **nicht direkt aktivieren.**

---

## Phase 6b — Rückfragen & Korrektur-Runde (Pflicht nach dem ersten Lauf)

Der erste Testlauf ist die einzige Gelegenheit, die generierten Regeln
gegen die echte Mailbox des Nutzers zu prüfen, bevor sie unbeaufsichtigt
läuft. Zwei getrennte Schritte, beide **aktiv von dir angestoßen**, nicht
nur beiläufig erwähnt:

### 1. Rückfragen zu unsortiert gebliebenen Mails

Die Prompt-Vorlage (`templates/mail-sort-prompt.template.txt`) enthält
dafür bereits eine feste Anweisung: der Lauf meldet am Ende zusätzlich zur
normalen Zusammenfassung, welche unsortiert gebliebenen Mails nach
Absenderdomain gruppiert sind (kein Platzhalter — gilt unverändert für
jede Einrichtung). Gehe diese Liste mit dem Nutzer durch, domainweise, nicht jede einzelne
Mail: *"X Mails von \<domain\> blieben im Posteingang, weil ich keine
eindeutige Regel dafür hatte — sollen die künftig nach \<Ordner\>?"* Bei
Zustimmung: passende Zeile in `mail-sort-prompt.txt` ergänzen (Domain →
Ordner). Bei Unsicherheit des Nutzers: nichts ändern, das ist weiterhin
die sichere Voreinstellung.

### 2. Bitte um Korrektur-Feedback zu tatsächlich verschobenen Mails

Bitte den Nutzer explizit und konkret darum, die soeben befüllten
Zielordner selbst kurz durchzusehen: *"Schau bitte kurz in die Ordner, in
die gerade einsortiert wurde — ist etwas falsch gelandet? Wenn ja, sag mir
welche Mail(s) und wohin sie stattdessen gehören, dann korrigiere ich die
Regel."* Das ist keine optionale Höflichkeitsfloskel, sondern der einzige
Mechanismus, mit dem falsch generalisierte Domain-Regeln (z. B. ein
Absender, der fälschlich pauschal einem Ordner zugeordnet wurde) vor der
Automatisierung auffallen.

Bei gemeldeten Fehlern: Regel in `mail-sort-prompt.txt` entsprechend enger
fassen (z. B. Ausnahme für einen Betreff-Fall ergänzen, wie im
Referenz-Setup üblich), betroffene Mails auf
Wunsch des Nutzers per `move_emails` zurück ins Postfach/in den korrekten
Ordner verschieben, und **Schritt 1 dieser Phase mit den korrigierten
Regeln wiederholen** (erneuter `--once`-Lauf), bis der Nutzer zufrieden
ist. Erst danach zu Phase 7.

---

## Phase 7 — Abschlussbericht

Kurze, für Laien verständliche Zusammenfassung, keine Wall of Text:

- Welche Konten sind eingebunden.
- Was automatisch passiert und wie oft.
- **Ausdrücklich:** "Es werden nie E-Mails gesendet, gelöscht oder
  weitergeleitet — nur gelesen, in deine eigenen Ordner einsortiert und
  markiert."
- Wo man Fehler sieht (`mail-sort.log`).
- Wie man es manuell anstößt, ändert oder komplett stoppt.
- Hinweis, dass dieser Skill jederzeit erneut aufgerufen werden kann, um
  ein weiteres Konto oder eine komplett neue Einrichtung durchzuführen.
- Hinweis, dass auch **nach** der Scharfschaltung jeder künftige
  automatische Lauf dieselbe Domain-Zusammenfassung ins Log schreibt
  (Phase 6b, Schritt 1) — der Nutzer kann jederzeit im Log nachsehen, was
  zuletzt unsortiert blieb, auch ohne Claude erneut dafür aufzurufen.

---


## Bekannte Fallstricke (aus dem Referenz-Betrieb)

- **Verschieben ≠ Kopieren.** IMAP kennt bei den meisten Servern kein
  natives Kopieren zwischen Ordnern über diesen MCP-Server — eine
  verschobene Mail ist im Ursprungsordner weg. Das ist der Grund, warum
  zeitkritische Mails (Phase 1.2) markiert statt verschoben werden.
- **Nutzungslimits bei sehr aktiven Konten:** Ein headless `claude -p`-Lauf
  kann an ein Anthropic-Nutzungslimit stoßen und dann ohne Wiederholung
  ausfallen, bis zum nächsten planmäßigen Intervall. Optional (nicht
  Voraussetzung) erwähnen: Tools wie
  [claude-auto-retry](https://github.com/cheapestinference/claude-auto-retry)
  können das abfangen, indem sie den Lauf bis zur Reset-Zeit verzögern —
  nur anbieten, nicht aufdrängen, das ist eine Komfort-Ergänzung, keine
  Voraussetzung dieses Skills.
- **Erstlauf vs. Folgeläufe:** Beim allerersten Lauf gibt es noch keinen
  Watermark (`mail-sort-last-run.txt` ist leer) — dann wird der komplette
  aktuelle Posteingang geprüft, nicht nur "neue" Mails. Bei sehr vollen
  Posteingängen kann das dauern; das dem Nutzer vorher ankündigen.
- **App-Passwörter laufen ab / werden widerrufen.** Wenn der Loop plötzlich
  Auth-Fehler im Log zeigt, ist das meist die Ursache — im `README.md`
  erwähnen, nicht nur als generischen Fehlerfall behandeln.

---

## Dateien in diesem Skill

```
templates/
  config.toml.example              # ein Konto, IMAP-only, mit Tag-Beispiel
  mail-sort-prompt.template.txt    # Regelwerk-Vorlage mit Platzhaltern
  mail-sort-loop.sh                # generischer Endlos-/Einmal-Loop
  systemd/mail-sort.service        # lokaler Pfad, Linux
  systemd/mail-sort.timer          # lokaler Pfad, Linux
  crontab-example.txt              # lokaler Pfad, klassisches Cron
```
