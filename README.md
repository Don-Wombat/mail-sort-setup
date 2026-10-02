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

**Der Setup-Skill** (die geführte Einrichtung in diesem Repository) wurde dagegen am 2026-09-28 gegen ein echtes Gmail-Konto validiert (Docker-Pfad): Erstlauf-Erkennung, Domain-basierte Klassifizierung, Login-Ausnahmen, die Rückfrage-Runde nach unsortierten Mails — alles wie vorgesehen. Dieses Datum gilt nur für den Test des Setup-Skills, nicht für den Algorithmus. **Seit Version 1.1.0** wurde der Loop deutlich überarbeitet (gehärteter `claude`-Aufruf, Paging, Lock, Zeitlimit); der Docker-Pfad wurde deshalb am 2026-10-02 (Version 1.2.1) erneut gegen ein echtes Gmail-Konto validiert: Server-Container laut Snippet, gehärteter Vollauf über 126 Mails, Abschlussmarke und Watermark; danach nochmals mit einem frischen Test-Konto und frisch gestartetem `mail-mcp-sort`-Container (Vollauf, Folgelauf, Fehlerfall ohne Marke). Dabei fiel die Gmail-Antwort `warning: reconciliation needed` auf (in 1.2.1 behoben). Der lokale Pfad (ohne Docker) ist bisher nur nach Dokumentationslage gebaut, noch nicht real durchgespielt. Der Windows-Pfad (ab 1.2.0) wurde am 2026-10-02 auf einem echten Windows-Runner (GitHub Actions `windows-latest`, Windows PowerShell 5.1 und PowerShell 7) gegen einen Test-Stub von `claude` geprüft: Loop-Verhalten, Argument-Quotierung, `.cmd`-Shim, Timeout mit Prozessbaum-Ende sowie Registrierung in der echten Aufgabenplanung. Zusätzlich lief der Loop am selben Tag auf einer echten Windows-11-VM (deutsch, Windows PowerShell 5.1) mit dem echten `claude.exe` 2.1.286 (Exit 0, Abschlussmarke, Watermark, UTF-8-Log mit Umlauten) und ein echter Start über die Aufgabenplanung (Ergebnis 0, nächster Lauf korrekt berechnet); die `icacls`-Zeile aus der SKILL.md funktioniert auch auf deutschem Windows. Dort lief zunächst kein Mail-Konto mit. Am 2026-10-02 wurde der Windows-Pfad deshalb zusätzlich als Standardnutzer ohne Adminrechte (Installation von `claude` und `uv` per `winget`, Aufgabenplanung, `uvx mcp-email-server` per stdio) gegen ein echtes Gmail-Testkonto bis zur sortierten Mail durchgespielt. Offen: Windows 10, englisches Windows, echte Firmenrechner (auf der VM nur nachgestellt, siehe unten), macOS und der lokale Linux-Pfad. Von den Mail-Anbietern ist nur Gmail durchgespielt; Outlook/Microsoft 365 ist mit Passwort-Login nicht nutzbar (Microsoft hat Basic Auth für IMAP abgeschaltet, nötig wäre OAuth).

## Auf Firmenrechnern und mit geschäftlichem Claude

Wenn dein Arbeitgeber Einstellungen für Rechner oder für Claude Code vorgibt, kann das die Einrichtung ausbremsen. **Stand: nur teilweise getestet.** Der Skill wurde auf privaten Rechnern und einer Windows-VM geprüft, noch nicht auf einem echten Firmenrechner. Auf der VM wurde nachgestellt, wie `managed-mcp.json` und `allowedMcpServers` den Lauf blockieren (siehe unten). AppLocker, WDAC, TLS-Inspection und Domänen-Gruppenrichtlinien stammen dagegen aus der Dokumentation von Microsoft und Anthropic, nicht aus eigenen Tests.

**Vorab selbst prüfen (Windows):** Das Diagnose-Skript [`diagnose-windows.ps1`](skills/setup/templates/windows/diagnose-windows.ps1) prüft vor der Einrichtung, ob der Rechner mitspielt. Ohne Schalter liest es nur (keine Installation, keine Änderung, keine Adminrechte nötig) und zeigt Richtlinien, Werkzeuge, verwaltete Claude-Einstellungen und die TLS-Zertifikate. Mit `-All` macht es zusätzlich drei kleine Praxistests: eine Testaufgabe in der Aufgabenplanung (wird sofort wieder entfernt), `uvx mcp-email-server` und einen `claude -p`-Aufruf mit denselben Schutz-Schaltern wie der echte Lauf (ein winziger API-Aufruf, kein Mail-Zugriff). Am besten als normaler Nutzer starten, nicht als Admin:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\diagnose-windows.ps1 -All
```

Der Bericht landet zusätzlich in `%TEMP%\mail-sort-diagnose.txt` und enthält keine Passwörter, Mail-Inhalte oder Benutzernamen. Er nennt aber die Aussteller der TLS-Zertifikate (daran erkennt man eine Firmen-CA); vor dem Weitergeben kurz durchlesen.

**Vorab klären (am besten mit der IT):**

- **Darf Claude Code überhaupt Mails lesen?** Die Mails gehen bei jedem Lauf an die Anthropic-API. Bei Firmenpostfächern ist das eine Frage des Datenschutzes und der Compliance, nicht nur der Technik. Hol dir vorher eine Freigabe.
- **Geschäftliche Postfächer bei Microsoft 365/Exchange Online funktionieren nicht.** Microsoft hat Passwort-Login (auch App-Passwörter) für IMAP abgeschaltet, nötig wäre OAuth, das dieser Skill nicht kann. Der Skill sagt das im Interview offen und richtet dann nichts ein.
- **Programme aus dem Benutzerordner:** Der Windows-Pfad startet `claude`, `uv`/`uvx` und Python aus dem Profil des Nutzers. AppLocker oder WDAC können das blockieren.
- **Netzwerk:** Erreichbar sein müssen `api.anthropic.com` sowie für `uvx` auch `pypi.org` und `github.com`. Prüft die Firma TLS-Verbindungen mit eigenem Zertifikat (TLS-Inspection), scheitern `uv` und Python oft an der unbekannten Zertifizierungsstelle.
- **Aufgabenplanung:** Standardnutzer müssen eigene Aufgaben anlegen dürfen. `winget` oder der Store müssen erlaubt sein, sonst `uv` und `claude` anders installieren lassen.

**PowerShell:**

- Das Registrierungsskript startet den Loop mit `-ExecutionPolicy Bypass`. Setzt eine Gruppenrichtlinie die Ausführungsrichtlinie auf Computer- oder Benutzerebene (`MachinePolicy`/`UserPolicy`), hat sie Vorrang und der Loop startet nicht. Prüfen: `Get-ExecutionPolicy -List`.
- Im Constrained Language Mode (typisch mit AppLocker/WDAC) laufen die Skripte vermutlich nicht. Prüfen: `$ExecutionContext.SessionState.LanguageMode` muss `FullLanguage` sein.

**Verwaltete Claude-Code-Einstellungen (auf einer Windows-11-VM nachgestellt):**

Admins können Claude Code zentral vorgeben, per Datei (`C:\Program Files\ClaudeCode\managed-settings.json`, `managed-mcp.json`) oder über die Registry (`HKLM\SOFTWARE\Policies\ClaudeCode`). Diese Werte stehen über allem, was der Nutzer oder der Skill einstellt. Mögliche Folgen:

- Mit `managed-mcp.json` bricht `claude` beim Start ab (Meldung `You cannot dynamically configure MCP servers when an enterprise MCP config is present`), weil der Lauf seinen Mail-Server per `--mcp-config` mitgibt. Auf der VM bestätigt. `claude mcp add` wird laut Dokumentation ebenfalls abgelehnt. Die IT müsste den Mail-Server dort aufnehmen.
- Mit `allowedMcpServers` muss der Mail-Server freigegeben sein. Auf der VM bestätigt: ohne Freigabe meldet `claude` nur `Warning: MCP server blocked by enterprise policy: mail`, endet aber trotzdem mit Exit 0 und läuft ohne Mail-Werkzeuge weiter. Der Lauf kann dann nichts sortieren und gibt die Abschlussmarke nicht aus. Für den lokalen Pfad ist die Freigabe der Befehl `uvx mcp-email-server@...` (`serverCommand`, exakter Treffer inklusive aller Argumente), für den Docker-Pfad die URL (`serverUrl`); die Treffer-Regeln selbst sind nicht getestet.
- Verwaltete Berechtigungsregeln (`allowManagedPermissionRulesOnly`, `permissions.disableBypassPermissionsMode`) oder `allowManagedHooksOnly` können die Werkzeugfreigaben des Laufs verändern. Dann stoppt der Lauf, ohne die Abschlussmarke `MAIL_SORT_LAUF_OK` auszugeben. Das ist der sichere Ausgang: der Watermark bleibt stehen, es geht nichts verloren.

Das Diagnose-Skript erkennt beide Fälle. Von Hand lässt sich vorab prüfen mit `claude mcp list` (zeigt nur die erlaubten Server) und `/status` in Claude Code (zeigt, welche verwalteten Quellen aktiv sind). Dokumentation: [Managed settings](https://code.claude.com/docs/en/managed-settings) und [Managed MCP](https://code.claude.com/docs/en/managed-mcp).

**Faustregel:** Erst `/mail-sort-setup:setup` mit einem privaten Testkonto durchspielen, nicht mit dem Firmenpostfach. Läuft das, ist der Rest eine Frage der Freigabe durch die IT. Erfahrungen von Firmenrechnern gern als Issue melden.

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

## On company machines and with business Claude

If your employer enforces settings on machines or on Claude Code, setup may get blocked. **Status: only partly tested.** The skill was checked on private machines and on a Windows VM, not yet on a real company machine. On the VM we reproduced how `managed-mcp.json` and `allowedMcpServers` block the run (see below). AppLocker, WDAC, TLS inspection and domain Group Policies come from Microsoft's and Anthropic's documentation, not from our own tests.

**Check it yourself first (Windows):** the diagnostic script [`diagnose-windows.ps1`](skills/setup/templates/windows/diagnose-windows.ps1) checks before setup whether the machine will cooperate. Without switches it only reads (no installation, no changes, no admin rights needed) and shows policies, tools, managed Claude settings and the TLS certificates. With `-All` it also runs three small live tests: a test task in Task Scheduler (removed immediately), `uvx mcp-email-server` and a `claude -p` call with the same safety switches as the real run (one tiny API call, no mail access). Best started as a normal user, not as admin:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\diagnose-windows.ps1 -All
```

The report is also saved to `%TEMP%\mail-sort-diagnose.txt` and contains no passwords, mail content or user names. It does name the issuers of the TLS certificates (that is how a company CA shows up); skim it before passing it on.

**Clarify first (ideally with IT):**

- **Is Claude Code allowed to read mail at all?** Every run sends mail content to the Anthropic API. For business mailboxes that is a data-protection and compliance question, not just a technical one. Get approval first.
- **Business mailboxes on Microsoft 365/Exchange Online do not work.** Microsoft disabled password login (including app passwords) for IMAP; OAuth would be required, which this skill cannot do. The skill says so openly during the interview and sets nothing up.
- **Programs from the user profile:** the Windows path runs `claude`, `uv`/`uvx` and Python from the user's profile. AppLocker or WDAC may block that.
- **Network:** `api.anthropic.com` must be reachable, and for `uvx` also `pypi.org` and `github.com`. If the company inspects TLS with its own certificate (TLS inspection), `uv` and Python often fail on the unknown certificate authority.
- **Task Scheduler:** standard users must be allowed to create their own tasks. `winget` or the Store must be allowed, otherwise have `uv` and `claude` installed another way.

**PowerShell:**

- The registration script starts the loop with `-ExecutionPolicy Bypass`. If a Group Policy sets the execution policy at machine or user level (`MachinePolicy`/`UserPolicy`), that takes precedence and the loop will not start. Check with `Get-ExecutionPolicy -List`.
- In Constrained Language Mode (typical with AppLocker/WDAC) the scripts probably will not run. Check that `$ExecutionContext.SessionState.LanguageMode` is `FullLanguage`.

**Managed Claude Code settings (reproduced on a Windows 11 VM):**

Admins can enforce Claude Code settings centrally, via files (`C:\Program Files\ClaudeCode\managed-settings.json`, `managed-mcp.json`) or the registry (`HKLM\SOFTWARE\Policies\ClaudeCode`). These values rank above anything the user or the skill sets. Possible effects:

- With a `managed-mcp.json`, `claude` exits at startup (`You cannot dynamically configure MCP servers when an enterprise MCP config is present`) because the run passes its mail server via `--mcp-config`. Confirmed on the VM. `claude mcp add` is rejected as well according to the documentation. IT would have to add the mail server there.
- With `allowedMcpServers`, the mail server must be approved. Confirmed on the VM: without approval `claude` only prints `Warning: MCP server blocked by enterprise policy: mail`, but still exits with 0 and carries on without mail tools. The run then cannot sort anything and does not print the completion marker. For the local path the approval is the command `uvx mcp-email-server@...` (`serverCommand`, exact match including all arguments), for the Docker path the URL (`serverUrl`); the matching rules themselves are untested.
- Managed permission rules (`allowManagedPermissionRulesOnly`, `permissions.disableBypassPermissionsMode`) or `allowManagedHooksOnly` may change the run's tool approvals. The run then stops without printing the completion marker `MAIL_SORT_LAUF_OK`. That is the safe outcome: the watermark stays put and nothing is lost.

The diagnostic script detects both cases. By hand you can check up front with `claude mcp list` (shows only the permitted servers) and `/status` in Claude Code (shows which managed sources are active). Documentation: [Managed settings](https://code.claude.com/docs/en/managed-settings) and [Managed MCP](https://code.claude.com/docs/en/managed-mcp).

**Rule of thumb:** first run `/mail-sort-setup:setup` with a private test account, not the company mailbox. If that works, the rest is a matter of approval by IT. Reports from company machines are welcome as issues.
