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
Einrichtung in einfachen Worten, erkläre *warum* du etwas fragst, und fasse
am Ende in 3-4 Sätzen zusammen, was jetzt automatisch passiert.

**Passwörter niemals in den Chat.** Weder du noch der Nutzer sollen ein
Passwort im Chat tippen oder anzeigen: Der Chat landet im Gesprächsprotokoll
(Transkript) auf der Festplatte. Siehe Phase 2, Abschnitt „Passwort
eintragen".

---

## 0. Kernprinzip — nicht verhandelbar

**Diese Automatisierung darf niemals senden, löschen oder weiterleiten.**
Das wird auf zwei unabhängigen Ebenen erzwungen, nicht nur einer:

1. **Serverseitig (stärker):** Der `[emails.outgoing]`-Block (SMTP) wird in
   `config.toml` standardmäßig **weggelassen**, und `allowed_recipients = []`
   steht als globaler Schlüssel ganz oben in der Datei. Ohne SMTP-
   Zugangsdaten kann der MCP-Server `send_email`/`forward_email` technisch
   gar nicht ausführen — das ist keine Höflichkeitsregel, sondern eine
   strukturelle Unmöglichkeit.
2. **Clientseitig:** Der generierte Lauf-Loop startet `claude -p` bewusst
   eng gefasst: `--permission-mode dontAsk` (alles Nicht-Erlaubte wird
   abgelehnt statt nachgefragt), `--tools ""` (keine eingebauten Werkzeuge
   wie Bash oder Dateizugriff), `--strict-mcp-config --mcp-config
   mail-mcp.json` (es wird **nur** der Mail-MCP-Server geladen, keine
   anderen MCP-Server aus der Nutzer-Konfiguration) und `--allowedTools`
   beschränkt auf genau:
   `mcp__mail__list_available_accounts mcp__mail__list_emails_metadata
   mcp__mail__list_mailboxes mcp__mail__list_email_tags
   mcp__mail__move_emails mcp__mail__set_email_tags`
   — zusätzlich sperrt `--disallowedTools` (deny gewinnt immer) explizit:
   `send_email`, `forward_email`, `save_to_mailbox`, `delete_emails`,
   `archive_emails`, `set_email_flags`, `mark_emails_as_read`,
   `get_emails_content`, `download_attachment`, `get_attachment_content`.
   (`mcp-email-server` hat *keinen* eingebauten Read-Only-Modus — diese
   beiden Ebenen sind der einzige verlässliche Weg. Eine reine
   `--allowedTools`-Liste allein würde andere Werkzeuge oder MCP-Server
   **nicht** sperren; deshalb die Kombination oben.)

**Was "read-only" hier genau bedeutet** (das musst du dem Nutzer explizit
so erklären, nicht nur "read-only" sagen): Mails werden **gelesen**
(Absender, Betreff, Datum — nicht der Inhalt), zwischen **den eigenen
Ordnern desselben Kontos verschoben** und mit Labels/Tags markiert. Nichts
verlässt das Konto, nichts wird unwiderruflich gelöscht, nichts wird an
Dritte verschickt. Verschobene Mails sind weiterhin da — nur in einem
anderen Ordner, jederzeit manuell zurückverschiebbar.

**Falls der Nutzer ausdrücklich SMTP/Senden für andere Zwecke will:** dann
nur mit einer **eigenen Config-Datei und einem eigenen MCP-Server unter
einem Namen ungleich `mail`** — nie im selben Account-Block bzw. derselben
Datei, die dieser Sortier-Loop benutzt. Das im Abschlussbericht als
Abweichung vom Standard deutlich benennen. (`allowed_recipients` ist ein
globaler Schlüssel der jeweiligen Config-Datei; mit `[]` ist Senden
serverseitig auch bei vorhandenem SMTP gesperrt.)

---

## Ablauf-Überblick

0. Umgebung prüfen (Docker-Pfad vs. lokaler Pfad, Linux/macOS vs. Windows, Claude-Code-Version)
1. Interview: Konten, IMAP-Zugang, Ordnerstruktur, Ton (vorsichtig/aggressiv)
1b. Projektordner anlegen (inkl. `mail-mcp.json`)
2. `mcp-email-server` aufsetzen, Passwort eintragen lassen, registrieren,
   Zielordner prüfen
3. Sortier-Regeln als Prompt-Datei generieren
4. Loop, Prompt und README im Projektordner ablegen
5. Zeitplan für automatischen Lauf festlegen
6. Manueller Testlauf, gemeinsam mit dem Nutzer geprüft
6b. Rückfragen & Korrektur-Runde
7. Automatisierung scharfschalten + Abschlussbericht an den Nutzer

**Ein Projekt für alle Konten:** Egal wie viele Konten der Nutzer hat —
es gibt **einen** Projektordner (Name neutral: `mail-sort`), **einen**
Loop, **eine** Prompt-Datei mit je einem Konto-Block pro Konto und
**einen** MCP-Server-Container (`mail-mcp-sort`). Jeder Tool-Aufruf im Lauf
übergibt `account_name="<exakter Name>"`.

---

## Phase 0 — Umgebung feststellen

Frage nicht raten — prüfe zuerst technisch, frage nur wenn unklar:

```bash
[ -f /.dockerenv ] && echo "läuft in Docker" || echo "kein Docker erkennbar"
command -v tmux >/dev/null && echo "tmux verfügbar" || echo "kein tmux"
uname -s   # Linux / Darwin (macOS) / ...
claude --version
claude --help | grep -E -c 'dontAsk|--strict-mcp-config|--tools'   # sollte mindestens 3 ausgeben
```

- **Claude-Code-Version:** Der Loop braucht `--permission-mode dontAsk`,
  `--tools` und `--strict-mcp-config`. Zeigt `claude --help` sie nicht an
  (bzw. liefert das `grep -c` weniger als 3), den Nutzer bitten, Claude Code
  zu aktualisieren (`claude update`), bevor es weitergeht — sonst läuft die
  Absicherung aus Abschnitt 0 nicht.
- **Docker-Pfad**, wenn `/.dockerenv` existiert (oder der Nutzer bestätigt,
  dass Claude Code in einem Container läuft, der Sessions bei Absturz neu
  startet — frag nach, ob es sowas wie ein `entrypoint.sh` mit
  Neustart-Schleife gibt, das pro Projekt ein eigenes `tmux`-Fenster startet).
- **Lokaler Pfad**, wenn keine Container-Umgebung erkennbar ist — dann
  zählt das Betriebssystem für die Zeitplan-Mechanik (Phase 5).
- **Windows (nativ):** Erkennbar daran, dass deine Shell PowerShell ist
  (ohne Git for Windows nutzt Claude Code dort das PowerShell-Werkzeug)
  oder `uname -s` mit `MINGW`/`MSYS` beginnt (Git Bash). In PowerShell
  stattdessen prüfen:

  ```powershell
  $env:OS                      # Windows_NT
  $PSVersionTable.PSVersion    # 5.1 (vorinstalliert) oder 7.x
  claude --version
  (claude --help | Select-String -Pattern 'dontAsk|--strict-mcp-config|--tools').Count   # mindestens 3
  ```

  Auf Windows gilt der lokale Pfad mit den Windows-Vorlagen
  (`templates/windows/`): Der Loop ist dort ein PowerShell-Skript, die
  Zeitsteuerung übernimmt die Windows-Aufgabenplanung. Git Bash oder WSL
  sind **nicht** nötig. (Wer Claude Code ohnehin in WSL betreibt, nutzt
  dort den normalen Linux-Pfad.)

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
- Hinweis zum Passwort: viele Provider (Gmail, GMX, Outlook, ...)
  verlangen bei aktivierter 2-Faktor-Authentifizierung ein separates
  **App-Passwort** statt des normalen Kontopassworts. Erkläre kurz, wo man
  das üblicherweise findet ("Konto-Sicherheitseinstellungen des
  Providers → 'App-Passwörter' oder 'IMAP-Zugriff'"), aber nicht
  provider-spezifisch vorspulen, das ändert sich zu oft. **Das Passwort
  selbst wird hier NICHT abgefragt** — der Nutzer trägt es später selbst
  in einer Datei ein (Phase 2).
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
  "Bestellungen", ...). **Nicht erlaubt als Ziel:** Papierkorb/Trash,
  Spam/Junk, Gesendet/Sent, Entwürfe/Drafts, Archiv — falls der Nutzer so
  etwas nennt, erklären, dass der Lauf dorthin nie verschiebt (Verschieben
  kann wie Löschen wirken), und einen normalen Ordner vorschlagen.
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
  Tag in `config.toml` (siehe Phase 2) — nicht jeder IMAP-Server
  unterstützt das gleich gut, im Zweifel als optionales Feature behandeln.

### 1.3 Sprache

In welcher Sprache soll die generierte Sortier-Logik/Prompt-Datei verfasst
sein (beeinflusst nur die internen Regeltexte, nicht die Bedienung dieses
Interviews)? Default: gleiche Sprache wie das Interview selbst.

---

## Phase 1b — Projektordner anlegen

Jetzt schon, weil die lokale MCP-Registrierung (`-s local`, Phase 2)
an das Projektverzeichnis gebunden ist und der Loop `mail-mcp.json` braucht.

Verzeichnis `mail-sort` (Name mit dem Nutzer abstimmen, aber nicht
kontospezifisch — es ist ein Projekt für alle Konten) unter dem
Projekte-Verzeichnis der jeweiligen Claude-Code-Installation anlegen
(`chmod 700`), darin:

- `mail-mcp.json` — aus `templates/mail-mcp.http.json` (Docker-Pfad) bzw.
  `templates/mail-mcp.stdio.json` (lokaler Pfad). Der Servername darin
  **muss `mail` lauten** (Tool-Präfix `mcp__mail__*`). Im stdio-Fall
  `__MCP_EMAIL_SERVER_VERSION__` durch eine konkrete, aktuelle Version von
  `mcp-email-server` ersetzen (siehe PyPI) — nicht `latest`: der Loop läuft
  unbeaufsichtigt, ein stilles Upgrade soll dort nichts ändern.
- (Die übrigen Dateien folgen in Phase 4.)

Unter Windows: Ordner im eigenen Benutzerprofil anlegen (z. B.
`%USERPROFILE%\mail-sort`). Dort haben andere Benutzer standardmäßig
keinen Zugriff; `chmod` entfällt. In `mail-mcp.json` sind keine Pfade
enthalten, die Vorlagen gelten unverändert.

Danach in diesem Verzeichnis weiterarbeiten (Claude Code dorthin
starten), damit die Registrierung in Phase 2 zu diesem Projekt gehört.

---

## Phase 2 — `mcp-email-server` aufsetzen

Server-Projekt: [Wh1isper/mcp-email-server](https://github.com/Wh1isper/mcp-email-server)
(`serverInfo.name` meldet sich als `"email"` — der Registrierungsname
`mail` ist unabhängig davon und bestimmt allein das Tool-Präfix). Kein
eingebauter Read-Only-Modus (siehe Abschnitt 0) — Sicherheit kommt aus der
Konfiguration selbst.

### Config-Datei

Für jedes Konto aus Phase 1 einen Block nach
`templates/config.toml.example` — **ohne** `[emails.outgoing]`, außer der
Nutzer hat das explizit anders verlangt (siehe Kernprinzip). Die Zeile
`allowed_recipients = []` bleibt als erste aktive Zeile ganz oben (vor dem
ersten `[[emails]]`). Den `[[emails.tags]]`-Block nur einkommentieren, wenn
in 1.2 ein Tag gewünscht wurde.

Die Datei in ein Verzeichnis legen, das nur der Nutzer lesen kann
(Verzeichnis `chmod 700`, Datei `chmod 600`) und **nie** in ein
Git-Repository. Unter Windows statt `chmod` die Vererbung entfernen und nur
dem eigenen Benutzer Zugriff geben (PowerShell):
`icacls <pfad>\config.toml /inheritance:r /grant:r "$($env:USERNAME):(F)"`.

### Passwort eintragen (nicht im Chat)

1. Schreibe die Config mit dem Platzhalter `HIER-APP-PASSWORT-EINTRAGEN`
   als Passwort, `chmod 600`.
2. Sag dem Nutzer den Pfad und bitte ihn, die Datei **in seinem eigenen
   Terminal** zu öffnen (z. B. `nano <pfad>`, unter Windows
   `notepad <pfad>`) und den Platzhalter durch das App-Passwort zu
   ersetzen. Nicht in den Chat schreiben.
3. Prüfe ohne den Inhalt anzuzeigen: `grep -c 'HIER-APP-PASSWORT-EINTRAGEN'
   <pfad>` muss `0` liefern (bei mehreren Konten: Anzahl der noch offenen
   Platzhalter); unter Windows
   `(Select-String -Path <pfad> -Pattern 'HIER-APP-PASSWORT-EINTRAGEN' -SimpleMatch).Count`.
   Zeig die Datei nicht an.
4. Nur wenn der Nutzer **ausdrücklich** darauf besteht, das Passwort
   trotzdem im Chat zu nennen: zulassen, aber vorher darauf hinweisen,
   dass es im Transkript landet, und nach der Einrichtung empfehlen, das
   App-Passwort beim Provider zu widerrufen und neu zu erzeugen.

Headless-Hinweis: Auf Servern ohne Schlüsselbund (Keyring) kann
`mcp-email-server` Zugangsdaten nicht dort ablegen. Falls der Server beim
Start über den Keyring klagt, in der Upstream-Dokumentation die
Einstellung `credential_storage = "plaintext"` nachlesen und setzen.

### Docker-Pfad

Eigener Container neben dem bestehenden Claude-Code-Setup, HTTP-Transport.
Das Config-Verzeichnis (siehe oben) muss auf dem Docker-Host liegen und
dort in den Container gemountet werden. Liegt es bereits in einem Ordner,
den Claude Code im eigenen Container sieht (z. B. ein gemeinsames
Projekte-Verzeichnis), kannst du die Datei direkt dort schreiben —
andernfalls legt der Nutzer sie auf dem Host an.

```yaml
mail-mcp-sort:
  image: ghcr.io/wh1isper/mcp-email-server:<VERSION>   # konkrete Version pinnen
  container_name: mail-mcp-sort
  restart: unless-stopped
  user: "<uid>:<gid>"        # Besitzer der config.toml auf dem Host (id -u / id -g)
  command: streamable-http
  environment:
    - MCP_HOST=0.0.0.0
    - MCP_PORT=8000
    - MCP_ALLOWED_HOSTS=mail-mcp-sort:8000,localhost:8000
    - MCP_ALLOWED_ORIGINS=http://mail-mcp-sort:8000
    - MCP_EMAIL_SERVER_CONFIG_PATH=/config/config.toml
  volumes:
    - <config-verzeichnis-auf-dem-host>:/config
  networks: [<gleiches-netz-wie-claude-code>]
```

`MCP_EMAIL_SERVER_CONFIG_PATH` ist nötig: ohne diese Variable liest der
Server `~/.config/mcp-email-server/config.toml` im Container und findet die
gemountete Datei nicht. Das Verzeichnis (`700`) muss dem im Snippet
gesetzten `user:` gehören und für ihn schreibbar sein (der Server legt dort
Hilfsdateien neben der `config.toml` an); die Datei `600`.

Den Service starten **muss der Nutzer auf dem Docker-Host** (Claude Code im
Container hat den Host-Docker nicht), im Verzeichnis der Compose-Datei, ggf.
mit `sudo`:

```bash
docker compose up -d mail-mcp-sort
```

Kein published Port nötig, wenn Claude Code im selben Docker-Netz hängt —
dann intern über den Containernamen erreichbar. Danach für die
interaktive Prüfung registrieren (`-s local` gilt nur für das aktuelle
Projektverzeichnis: den Befehl **im Projektverzeichnis aus Phase 1b**
ausführen):

```bash
claude mcp add --transport http mail http://mail-mcp-sort:8000/mcp -s local
```

**Der Registrierungsname muss `mail` lauten** — daraus ergibt sich das
Tool-Präfix `mcp__mail__*`, auf das `--allowedTools` im Loop (Abschnitt 0)
und der Prompt zugeschnitten sind. Jeder andere Name würde dazu führen,
dass alle Tool-Aufrufe abgelehnt werden. (Der automatische Lauf selbst lädt
den Server nicht aus dieser Registrierung, sondern ausschließlich aus
`mail-mcp.json`.) Falls der Nutzer bereits einen MCP-Server namens `mail`
für dasselbe Postfach registriert hat, diesen wiederverwenden (`claude mcp
list` prüfen), nicht doppelt anlegen.

### Lokaler Pfad (keine Docker nötig)

```bash
claude mcp add mail -s local -- uvx mcp-email-server==<VERSION> stdio
```

`uvx` braucht [uv](https://docs.astral.sh/uv/) — falls nicht installiert,
kurz erklären/installieren lassen. `<VERSION>` ist dieselbe konkrete
Version wie in `mail-mcp.json`. Die Config-Datei liegt dann lokal unter
`~/.config/mcp-email-server/config.toml` (ältere Versionen nutzten
`~/.config/zerolib/mcp_email_server/config.toml`; der Server kopiert die
alte Datei beim ersten Start selbst). Auch hier den `claude mcp add`-Befehl
im Projektverzeichnis aus Phase 1b ausführen.

**Windows:** `uv` per `winget install --id astral-sh.uv -e` oder mit dem
offiziellen Installer aus der uv-Dokumentation installieren (danach ein
neues Terminal öffnen). `~` steht für `%USERPROFILE%`, die Config liegt also
unter `%USERPROFILE%\.config\mcp-email-server\config.toml`. Ist Claude
Code per npm installiert (`claude.cmd`/`claude.ps1`), kann PowerShell das
`--` im `claude mcp add`-Befehl verschlucken — den Befehl dann über
`cmd /c "claude mcp add mail -s local -- uvx mcp-email-server==<VERSION> stdio"`
ausführen. Der automatische Lauf ist davon nicht betroffen (er liest
`mail-mcp.json`).

### Verifizieren und Zielordner prüfen

Nach dem Einrichten:

1. `list_available_accounts` aufrufen und bestätigen, dass alle Konten
   aus Phase 1 erscheinen.
2. Pro Konto `list_mailboxes` aufrufen und **jeden Zielordner aus 1.2
   damit abgleichen** — exakte Schreibweise inkl. Trennzeichen (je nach
   Provider `/` oder `.`, z. B. `Gaming/Steam` vs. `Gaming.Steam`), so wie
   `list_mailboxes` ihn liefert. Der MCP-Server kann **keine Ordner
   anlegen**: fehlende Ordner muss der Nutzer in seinem Mail-Programm bzw.
   der Webmail-Oberfläche selbst anlegen. Erst weitermachen, wenn alle
   Zielordner existieren. Ordner wie Trash/Spam/Sent/Drafts/Archiv als
   Ziel ablehnen (siehe 1.2).

---

## Phase 3 — Sortier-Regeln generieren

Aus den Antworten von Phase 1.2 eine Prompt-Datei bauen, Vorlage:
`templates/mail-sort-prompt.template.txt` (ein Konto-Block pro Konto, alle
in derselben Datei). Grundprinzipien, die immer gelten, unabhängig vom
Nutzer:

- Absenderdomain vor Volltext-Heuristik (zuverlässiger, günstiger).
- "Wichtig" = vorsichtig, Unsicherheit → Posteingang lassen. "Wegwerf" =
  aggressiver sortieren, Risiko gering.
- Zeitkritisches (falls in 1.2 gewünscht) wird **markiert, nicht
  verschoben** — sonst verschwindet der Fristbezug aus dem Blickfeld.
- Am Ende jedes Laufs eine kurze Zusammenfassung ausgeben (wie viele Mails
  wohin verschoben wurden) — landet im Lauf-Log, nicht nur im Chat.

**Vor dem Speichern prüfen**, dass keine Platzhalter und kein
Hinweis-Kommentarblock mehr in der Datei stehen:

```bash
grep -nE '__[A-Z_]+__|^# --- Hinweise' mail-sort-prompt.txt   # darf nichts ausgeben
```

(Der Loop bricht sonst ohnehin mit einer Fehlermeldung ab.)

---

## Phase 4 — Loop, Prompt und README ablegen

Im Projektordner aus Phase 1b (neben `mail-mcp.json`):

| Datei | Zweck |
|---|---|
| `mail-sort-loop.sh` | aus `templates/mail-sort-loop.sh`, mit den Werten aus Phase 1/5 befüllt — **unter Windows stattdessen** `mail-sort-loop.ps1` aus `templates/windows/mail-sort-loop.ps1` (gleiche Variablen, gleiches Verhalten) |
| `mail-sort-prompt.txt` | aus Phase 3 |
| `mail-sort-last-run.txt` | leer anlegen — Watermark, wird vom Loop selbst befüllt |
| `mail-sort.log` | **nicht** vorab anlegen — der Loop legt es beim ersten Lauf selbst mit restriktiven Rechten an (`umask 077`) |
| `README.md` | für den Menschen, siehe unten |

`README.md` muss in einfachen Worten enthalten:

- Was das hier ist und dass es **niemals sendet oder löscht**.
- **Manuell starten:** `bash mail-sort-loop.sh --once` (Einmal-Modus für
  Tests/manuelle Läufe statt der Endlosschleife). **Alle Mails neu
  prüfen** (z. B. nach einer Regeländerung, ignoriert den Watermark):
  `bash mail-sort-loop.sh --once --full`.
- **Fehler ansehen:** `tail -f mail-sort.log`. Hinweis: das Log enthält
  Absender-Domains und Anzahlen; es wird ab 5 MB rotiert (`mail-sort.log.1`).
- **Anpassen:** welche Zeile in `mail-sort-prompt.txt` für neue
  Ordner/Regeln geändert wird, wie eine neue Mailadresse als weiterer
  `[[emails]]`-Block in der `config.toml` und als weiterer Konto-Block im
  Prompt ergänzt wird (+ Neustart des MCP-Servers danach nötig), wie
  Uhrzeit/Intervall in `mail-sort-loop.sh` bzw. dem Scheduler (Phase 5)
  geändert wird.
- **Passwort ändern/widerrufen:** App-Passwort beim Provider neu erzeugen,
  in `config.toml` (im eigenen Terminal) ersetzen, MCP-Server neu starten.
- Wo man diesen Skill erneut aufrufen kann, um die geführte Einrichtung
  für ein weiteres Konto/Projekt zu wiederholen.

Unter Windows lauten die Befehle im README (PowerShell, im Projektordner):
`powershell -NoProfile -ExecutionPolicy Bypass -File .\mail-sort-loop.ps1 -Once`
(bzw. `... -Once -Full`) und zum Mitlesen des Logs
`Get-Content .\mail-sort.log -Wait -Tail 50`.

Falls Docker-Pfad mit vorhandenem `entrypoint.sh`: dem Nutzer den
konkreten Codeblock zeigen, den er dort ergänzen muss (Muster: eigenes
`tmux`-Fenster, das den Loop startet, analog zu den vorhandenen Projekt-Fenstern in diesem
`entrypoint.sh`). Falls kein `entrypoint.sh` vorhanden: minimal
anleiten, wie man den Loop in einer eigenen `tmux`-Session dauerhaft
laufen lässt (`tmux new-session -d -s mail-sort 'bash mail-sort-loop.sh'`).

---

## Phase 5 — Zeitplan festlegen

Fragen: **"Wann soll der erste automatische Lauf starten, und in welchem
Abstand soll er sich danach wiederholen?"** (z. B. "ab sofort, alle 4
Stunden" oder "täglich um 7 Uhr").

Je nach Umgebung (Phase 0) unterschiedlich umgesetzt:

- **Docker-Pfad / beide Pfade mit tmux-Persistenz:** `mail-sort-loop.sh`
  läuft als Endlosschleife (`MAIL_SORT_INTERVAL_SECONDS` zwischen den
  Läufen). Soll der erste Lauf erst zu einer bestimmten Uhrzeit starten,
  `MAIL_SORT_FIRST_RUN_AT="HH:MM"` (Ortszeit) im Loop-Skript setzen — das
  wirkt nur, solange noch kein Watermark existiert; nach einem Neustart des
  Containers startet der Loop dann sofort.
- **Lokaler Pfad, Linux mit systemd:** `templates/systemd/mail-sort.service`
  + `templates/systemd/mail-sort.timer` verwenden (Intervall im Timer,
  `OnCalendar=`), unter `~/.config/systemd/user/` ablegen, dann
  `systemctl --user enable --now mail-sort.timer`. **Den `OnCalendar`-
  Ausdruck vorher prüfen:** `systemd-analyze calendar --iterations=3
  "<Ausdruck>"` muss die erwarteten Zeitpunkte zeigen. User-Timer laufen
  nur, solange der Nutzer eingeloggt ist — soll der Lauf auch ohne Login
  laufen (Server, Abwesenheit): `loginctl enable-linger "$USER"`.
- **Lokaler Pfad, klassisches Cron (Linux/macOS):** Zeile aus
  `templates/crontab-example.txt` anpassen, `crontab -e`.
- **Lokaler Pfad, Windows:** `templates/windows/register-mail-sort-task.ps1`
  in den Projektordner kopieren und ausführen (keine Adminrechte nötig):
  `powershell -NoProfile -ExecutionPolicy Bypass -File .\register-mail-sort-task.ps1 -ProjectDir "<projektordner>" -StartAt 07:00 -IntervalHours 4`.
  Das legt eine Aufgabe `mail-sort` in der Aufgabenplanung an (je ein
  täglicher Zeitpunkt pro Intervall, verpasste Läufe werden nachgeholt,
  Abbruch nach 35 Minuten, kein paralleler Start) und gibt den nächsten
  Lauf-Zeitpunkt aus. Die Aufgabe läuft nur, solange der Nutzer angemeldet
  ist. Alternativ (ohne Aufgabenplanung) kann `mail-sort-loop.ps1` ohne
  `-Once` als Endlosschleife in einem offenen Fenster laufen.
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

1. `bash mail-sort-loop.sh --once` gemeinsam mit dem Nutzer ausführen
   (Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File .\mail-sort-loop.ps1 -Once`).
   Bei einem sehr vollen Posteingang vorher ankündigen, dass das dauern
   kann (der Loop bricht einen Lauf nach `MAIL_SORT_RUN_TIMEOUT_SECONDS`,
   30 Minuten, ab; ein abgebrochener Lauf setzt den Watermark nicht und
   kann einfach erneut gestartet werden — schon verschobene Mails sind
   dann weg aus dem Posteingang).
2. Ergebnis zusammen durchgehen: wie viele Mails erkannt, wie viele
   verschoben/markiert, wie viele blieben unangetastet.
3. Dem Nutzer erklären, dass send/delete/forward-Aufrufe technisch
   gesperrt sind (`--tools ""`, `--strict-mcp-config`, `--allowedTools`,
   `--disallowedTools`, `--permission-mode dontAsk`). Das Log
   (`mail-sort.log`) enthält nur die Textausgabe des Laufs, keine Liste
   der Tool-Aufrufe — den Nachweis liefert also die Sperre selbst, nicht
   das Log. Meldet das Log am Ende die Abschlussmarke `MAIL_SORT_LAUF_OK`,
   ist der Lauf vollständig durchgelaufen; fehlt sie, wurde der Watermark
   bewusst nicht fortgeschrieben.
4. **Nur falls ein Tag (z. B. `handlungsbedarf`) konfiguriert ist:** das
   Tag an einer harmlosen Test-Mail setzen (`set_email_tags`) und mit
   `list_emails_metadata(semantic_tags=["handlungsbedarf"])` zurücklesen;
   bei Gmail zusätzlich den Label-Eintrag im Webmail prüfen. Erscheint die
   Mail nicht, den Tag-Block (keyword) anpassen oder das Feature weglassen.
5. Weiter mit Phase 6b — **nicht direkt aktivieren.**

---

## Phase 6b — Rückfragen & Korrektur-Runde (Pflicht nach dem ersten Lauf)

Der erste Testlauf ist die einzige Gelegenheit, die generierten Regeln
gegen die echte Mailbox des Nutzers zu prüfen, bevor sie unbeaufsichtigt
läuft. Zwei getrennte Schritte, beide **aktiv von dir angestoßen**, nicht
nur beiläufig erwähnt:

### 1. Rückfragen zu unsortiert gebliebenen Mails

Die Prompt-Vorlage (`templates/mail-sort-prompt.template.txt`) enthält dafür
bereits eine feste Anweisung: der Lauf meldet am Ende zusätzlich zur
normalen Zusammenfassung, welche unsortiert gebliebenen Mails nach
Absenderdomain gruppiert sind (kein Platzhalter — gilt unverändert für
jede Einrichtung). Gehe diese Liste mit dem Nutzer durch, domainweise,
nicht jede einzelne Mail: *"X Mails von \<domain\> blieben im Posteingang,
weil ich keine eindeutige Regel dafür hatte — sollen die künftig nach
\<Ordner\>?"* Bei Zustimmung: passende Zeile in `mail-sort-prompt.txt`
ergänzen (Domain → Ordner). Bei Unsicherheit des Nutzers: nichts ändern,
das ist weiterhin die sichere Voreinstellung.

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
fassen (z. B. Ausnahme für einen Betreff-Fall ergänzen), betroffene Mails
auf Wunsch des Nutzers per `move_emails` zurück ins Postfach/in den
korrekten Ordner verschieben, und **Schritt 1 dieser Phase mit den
korrigierten Regeln wiederholen** — mit `bash mail-sort-loop.sh --once
--full` (Windows: `... mail-sort-loop.ps1 -Once -Full`). Ein normaler `--once`-Lauf würde wegen des Watermarks nur Mails
seit dem letzten Lauf ansehen und die zuvor unsortierten Mails gar nicht
mehr betrachten; `--full` ignoriert den Watermark und prüft den ganzen
Posteingang erneut. Wiederholen, bis der Nutzer zufrieden ist. Erst danach
zu Phase 7.

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
- Wie man das App-Passwort ändert (neu erzeugen, `config.toml` im eigenen
  Terminal anpassen, MCP-Server neu starten) — und dass der Nutzer es beim
  Provider widerrufen kann, falls er es doch einmal im Chat genannt hat.
- Hinweis, dass dieser Skill jederzeit erneut aufgerufen werden kann, um
  ein weiteres Konto oder eine komplett neue Einrichtung durchzuführen.
- Hinweis, dass auch **nach** der Scharfschaltung jeder künftige
  automatische Lauf dieselbe Domain-Zusammenfassung ins Log schreibt
  (Phase 6b, Schritt 1) — der Nutzer kann jederzeit im Log nachsehen, was
  zuletzt unsortiert blieb, auch ohne Claude erneut dafür aufzurufen.

---

## Bekannte Fallstricke (aus dem Referenz-Betrieb)

- **Verschieben ≠ Kopieren.** IMAP selbst kennt zwar COPY, aber dieser
  MCP-Server bietet kein Copy-Werkzeug — eine verschobene Mail ist im
  Ursprungsordner weg. Das ist der Grund, warum zeitkritische Mails
  (Phase 1.2) markiert statt verschoben werden.
- **Nutzungslimits bei sehr aktiven Konten:** Ein headless `claude -p`-Lauf
  kann an ein Anthropic-Nutzungslimit stoßen; er bricht dann ohne
  Abschlussmarke ab (Watermark bleibt stehen), und der nächste Versuch
  folgt erst zum nächsten planmäßigen Intervall. Optional (nicht
  Voraussetzung) erwähnen: Tools wie
  [claude-auto-retry](https://github.com/cheapestinference/claude-auto-retry)
  erkennen das Limit an der Ausgabe im tmux-Fenster und wiederholen den
  Lauf danach — das funktioniert also nur, wenn der Loop in einem
  tmux-Fenster läuft (nicht unter Cron/systemd). Einen solchen Wrapper
  trägt der Nutzer als `MAIL_SORT_CLAUDE_BIN` ein; er muss alle
  `claude`-Argumente und stdin unverändert durchreichen und den Exit-Code
  erhalten. Nur anbieten, nicht aufdrängen.
- **Erstlauf vs. Folgeläufe:** Beim allerersten Lauf gibt es noch keinen
  Watermark (`mail-sort-last-run.txt` ist leer) — dann wird der komplette
  aktuelle Posteingang geprüft, nicht nur "neue" Mails. Der Lauf arbeitet
  die Seiten à 100 Mails nacheinander ab; bei sehr vollen Posteingängen
  (mehrere tausend Mails) kann das länger als das Zeitlimit dauern. Dann
  entweder `MAIL_SORT_FIRST_RUN_SINCE` im Loop auf ein Datum setzen
  (z. B. nur das letzte Jahr) oder den Lauf mehrfach starten, bis er
  durchläuft. Dem Nutzer das vorher ankündigen.
- **Windows: der Windows-Pfad ist bisher nur mit PowerShell 7 unter Linux
  gegen einen Test-Stub geprüft**, noch nicht auf einem echten
  Windows-Rechner. Bei Problemen zuerst manuell
  `mail-sort-loop.ps1 -Once` im Terminal laufen lassen und die Ausgabe
  ansehen. Das Zeitlimit beendet auch hängende Kindprozesse (u. a. als
  Schutz vor hängenden headless-`claude.exe`-Prozessen, wie sie in
  Claude-Code-Issue #68626 für einen anderen Aufrufweg beschrieben sind).
- **App-Passwörter laufen ab / werden widerrufen.** Wenn der Loop plötzlich
  Auth-Fehler im Log zeigt, ist das meist die Ursache — im `README.md`
  erwähnen, nicht nur als generischen Fehlerfall behandeln.

---

## Dateien in diesem Skill

```
templates/
  config.toml.example              # ein Konto, IMAP-only, allowed_recipients = []
  mail-mcp.http.json               # MCP-Config für den Loop (Docker-Pfad)
  mail-mcp.stdio.json              # MCP-Config für den Loop (lokaler Pfad)
  mail-sort-prompt.template.txt    # Regelwerk-Vorlage mit Platzhaltern
  mail-sort-loop.sh                # generischer Endlos-/Einmal-Loop
  systemd/mail-sort.service        # lokaler Pfad, Linux
  systemd/mail-sort.timer          # lokaler Pfad, Linux
  crontab-example.txt              # lokaler Pfad, klassisches Cron
  windows/mail-sort-loop.ps1       # lokaler Pfad, Windows (PowerShell 5.1/7)
  windows/register-mail-sort-task.ps1  # lokaler Pfad, Windows-Aufgabenplanung
```
