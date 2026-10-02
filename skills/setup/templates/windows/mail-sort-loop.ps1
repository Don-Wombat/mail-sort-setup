# Mail-Sortier-Loop fuer Windows (nativ, ohne Git Bash/WSL). Gleiches
# Verhalten wie ../mail-sort-loop.sh. Laeuft mit Windows PowerShell 5.1
# (vorinstalliert) und PowerShell 7. Die $MailSort*-Variablen unten sind die
# einzigen Stellen, die pro Einrichtung angepasst werden muessen.
#
# Manueller Einzellauf (Testlauf in SKILL.md Phase 6):
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\mail-sort-loop.ps1 -Once
# Einzellauf ueber den KOMPLETTEN Posteingang (Watermark ignorieren):
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\mail-sort-loop.ps1 -Once -Full
# Dauerbetrieb (Endlosschleife) statt Aufgabenplanung:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\mail-sort-loop.ps1
#
# Exit-Codes (-Once): 0 = Lauf vollstaendig, 1 = Fehler/unvollstaendig,
# 3 = anderer Lauf aktiv.
# Datei bewusst nur ASCII: Windows PowerShell 5.1 liest Skripte ohne BOM
# nicht als UTF-8.
param(
  [switch]$Once,
  [switch]$Full
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $ScriptDir
$env:PATH = "$env:PATH;$env:USERPROFILE\.local\bin"

# --- Anpassen ---------------------------------------------------------
$MailSortPromptFile = Join-Path $ScriptDir 'mail-sort-prompt.txt'
$MailSortLogFile = Join-Path $ScriptDir 'mail-sort.log'
$MailSortStateFile = Join-Path $ScriptDir 'mail-sort-last-run.txt'
# Nur dieser MCP-Server wird im Lauf geladen (siehe SKILL.md Phase 1b).
$MailSortMcpConfig = Join-Path $ScriptDir 'mail-mcp.json'
$MailSortIntervalSeconds = 14400     # Abstand zwischen Laeufen im Dauerbetrieb. 14400 = 4h.
$MailSortFirstRunAt = ''             # "HH:MM" (Ortszeit): erster Lauf erst dann, nur solange kein Watermark existiert. Leer = sofort.
$MailSortFirstRunSince = ''          # Optional, ISO-Zeitstempel (z.B. 2026-01-01T00:00:00Z): Erstlauf nur ab diesem Datum.
$MailSortRunTimeoutSeconds = 1800    # Abbruch eines haengenden Laufs (inkl. Kindprozesse).
$MailSortLogMaxBytes = 5242880       # Log-Rotation (eine Generation: mail-sort.log.1).
$MailSortStateMarginSeconds = 300    # Sicherheitsmarge beim Watermark.
# Wer einen Retry-Wrapper nutzt, setzt MAIL_SORT_CLAUDE_BIN. Er muss die
# claude-Argumente 1:1 durchreichen, stdin weiterleiten und den Exit-Code erhalten.
$ClaudeBin = if ($env:MAIL_SORT_CLAUDE_BIN) { $env:MAIL_SORT_CLAUDE_BIN } else { 'claude' }
# Nur Lesen/Verschieben/Markieren -- siehe SKILL.md Abschnitt 0. NICHT
# erweitern, ohne die Sicherheitsbegruendung dort neu zu bewerten.
$MailSortAllowedTools = @(
  'mcp__mail__list_available_accounts'
  'mcp__mail__list_emails_metadata'
  'mcp__mail__list_mailboxes'
  'mcp__mail__list_email_tags'
  'mcp__mail__move_emails'
  'mcp__mail__set_email_tags'
)
# Zusaetzliche Sperre (deny gewinnt).
$MailSortDisallowedTools = @(
  'mcp__mail__send_email'
  'mcp__mail__forward_email'
  'mcp__mail__save_to_mailbox'
  'mcp__mail__delete_emails'
  'mcp__mail__archive_emails'
  'mcp__mail__set_email_flags'
  'mcp__mail__mark_emails_as_read'
  'mcp__mail__get_emails_content'
  'mcp__mail__download_attachment'
  'mcp__mail__get_attachment_content'
)
$MailSortDoneMarker = 'MAIL_SORT_LAUF_OK'
# -----------------------------------------------------------------------

$LockDir = Join-Path $ScriptDir '.mail-sort.lock'
$Utf8 = New-Object System.Text.UTF8Encoding $false
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$OnWindows = ($env:OS -eq 'Windows_NT')
$script:LockHeld = $false

function Get-UtcStamp([datetime]$t) { $t.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", $Inv) }

function Write-Log([string]$text) {
  [System.IO.File]::AppendAllText($MailSortLogFile, $text + [Environment]::NewLine, $Utf8)
  if ($Once) { Write-Host $text }
}

function Invoke-LogRotation {
  if ((Test-Path -LiteralPath $MailSortLogFile) -and ((Get-Item -LiteralPath $MailSortLogFile).Length -gt $MailSortLogMaxBytes)) {
    Move-Item -LiteralPath $MailSortLogFile -Destination "$MailSortLogFile.1" -Force
  }
}

function Enter-Lock {
  for ($i = 0; $i -lt 2; $i++) {
    try {
      New-Item -ItemType Directory -Path $LockDir -ErrorAction Stop | Out-Null
      [System.IO.File]::WriteAllText((Join-Path $LockDir 'pid'), "$PID", $Utf8)
      $script:LockHeld = $true
      return $true
    } catch {
      $ownerPid = 0
      try { $ownerPid = [int]([System.IO.File]::ReadAllText((Join-Path $LockDir 'pid')).Trim()) } catch { }
      if ($ownerPid -gt 0 -and (Get-Process -Id $ownerPid -ErrorAction SilentlyContinue)) { return $false }
      # Verwaistes Lock (Prozess existiert nicht mehr) entfernen und erneut versuchen.
      Remove-Item -LiteralPath $LockDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  return $false
}

function Exit-Lock {
  if ($script:LockHeld) {
    Remove-Item -LiteralPath $LockDir -Recurse -Force -ErrorAction SilentlyContinue
    $script:LockHeld = $false
  }
}

# Ein Argument nach den Windows-Regeln (CommandLineToArgvW) quoten.
function ConvertTo-WinArg([string]$a) {
  if ($a -eq '') { return '""' }
  if ($a -notmatch '[\s"]') { return $a }
  $s = [regex]::Replace($a, '(\\*)"', { param($m) ($m.Groups[1].Value * 2) + '\"' })
  $s = [regex]::Replace($s, '(\\+)$', { param($m) $m.Groups[1].Value * 2 })
  return '"' + $s + '"'
}

function Stop-ProcessTree([System.Diagnostics.Process]$p) {
  # Auch Kindprozesse beenden (z.B. per stdio gestartete MCP-Server).
  if ($PSVersionTable.PSEdition -eq 'Core') {
    try { $p.Kill($true) } catch { }
  } elseif ($OnWindows) {
    try { & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null } catch { }
  } else {
    try { $p.Kill() } catch { }
  }
}

# Startet claude mit Prompt auf stdin. Rueckgabe: @{ Code; Output }
function Invoke-Claude([string]$prompt, [string[]]$claudeArgs) {
  $cmd = Get-Command $ClaudeBin -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $cmd) { return @{ Code = 127; Output = "FEHLER: '$ClaudeBin' nicht gefunden (PATH pruefen)." } }
  $argString = ($claudeArgs | ForEach-Object { ConvertTo-WinArg $_ }) -join ' '
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $ext = [System.IO.Path]::GetExtension($cmd.Source).ToLowerInvariant()
  if ($ext -eq '.cmd' -or $ext -eq '.bat') {
    # npm-Shims (claude.cmd) laufen nur ueber cmd.exe.
    $psi.FileName = $env:ComSpec
    $psi.Arguments = '/d /s /c "' + (ConvertTo-WinArg $cmd.Source) + ' ' + $argString + '"'
  } else {
    $psi.FileName = $cmd.Source
    $psi.Arguments = $argString
  }
  $psi.WorkingDirectory = $ScriptDir
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $Utf8
  $psi.StandardErrorEncoding = $Utf8

  $p = [System.Diagnostics.Process]::Start($psi)
  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()
  $bytes = $Utf8.GetBytes($prompt)
  try {
    $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $p.StandardInput.BaseStream.Flush()
  } catch { }
  $p.StandardInput.Close()

  if (-not $p.WaitForExit($MailSortRunTimeoutSeconds * 1000)) {
    Stop-ProcessTree $p
    [void]$p.WaitForExit(30000)
    $code = 124
  } else {
    $p.WaitForExit()
    $code = $p.ExitCode
  }
  [void]$outTask.Wait(30000)
  [void]$errTask.Wait(30000)
  $out = ''
  if ($outTask.IsCompleted) { $out += $outTask.Result }
  if ($errTask.IsCompleted) { $out += $errTask.Result }
  return @{ Code = $code; Output = $out.TrimEnd() }
}

function Invoke-SortRun([bool]$full) {
  if (-not (Test-Path -LiteralPath $MailSortPromptFile)) {
    Write-Log "[mail-sort] $(Get-UtcStamp (Get-Date)) FEHLER: Prompt-Datei $MailSortPromptFile fehlt."
    return 1
  }
  if (-not (Test-Path -LiteralPath $MailSortMcpConfig)) {
    Write-Log "[mail-sort] $(Get-UtcStamp (Get-Date)) FEHLER: MCP-Konfiguration $MailSortMcpConfig fehlt (siehe SKILL.md Phase 1b)."
    return 1
  }
  $promptBody = [System.IO.File]::ReadAllText($MailSortPromptFile, $Utf8)
  if ($promptBody -cmatch '(?m)__[A-Z_]+__|^# --- Hinweise') {
    Write-Log "[mail-sort] $(Get-UtcStamp (Get-Date)) FEHLER: Prompt-Datei enthaelt noch Platzhalter oder den Hinweis-Kommentarblock. Lauf abgebrochen."
    return 1
  }

  $start = Get-Date
  $runStart = Get-UtcStamp $start
  $since = ''
  $watermark = ''
  if (-not $full -and (Test-Path -LiteralPath $MailSortStateFile)) {
    $watermark = ([System.IO.File]::ReadAllText($MailSortStateFile)).Trim()
    if ($watermark -match '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$') {
      $since = $watermark
    } elseif ($watermark) {
      Write-Log "[mail-sort] WARNUNG: Watermark-Datei hat ungueltigen Inhalt, behandle den Lauf als Erstlauf."
    }
  }
  $nl = "`n"
  if ($since) {
    $mode = "since $since"
    $hint = "${nl}${nl}Hinweis: Dies ist KEIN Erstlauf. Zeitfenster dieses Laufs (UTC): since=`"$since`" und before=`"$runStart`".${nl}Uebergib beide Werte als since- bzw. before-Parameter an list_emails_metadata.${nl}"
  } elseif (-not $full -and $MailSortFirstRunSince -and -not $watermark) {
    $mode = 'Erstlauf/Vollauf'
    $hint = "${nl}${nl}Hinweis: Dies ist der Erstlauf, begrenzt auf einen Zeitraum. Zeitfenster dieses Laufs: since=`"$MailSortFirstRunSince`" und before=`"$runStart`".${nl}Uebergib beide Werte als since- bzw. before-Parameter an list_emails_metadata.${nl}"
  } else {
    $mode = 'Erstlauf/Vollauf'
    $hint = "${nl}${nl}Hinweis: Dies ist der Erstlauf bzw. ein Vollauf (kein since-Zeitstempel). Pruefe den kompletten aktuellen Bestand in INBOX.${nl}Zeitfenster dieses Laufs (UTC): nur before=`"$runStart`" (als before-Parameter an list_emails_metadata uebergeben).${nl}"
  }

  Write-Log "[mail-sort] $runStart Starte Sortierlauf ($mode, via $ClaudeBin)..."
  $claudeArgs = @('-p', '--permission-mode', 'dontAsk', '--tools', '', '--strict-mcp-config', '--mcp-config', $MailSortMcpConfig, '--allowedTools') + $MailSortAllowedTools + @('--disallowedTools') + $MailSortDisallowedTools
  $r = Invoke-Claude ($promptBody + $hint) $claudeArgs
  if ($r.Output) { Write-Log $r.Output }

  if ($r.Code -eq 124) {
    Write-Log "[mail-sort] $(Get-UtcStamp (Get-Date)) Timeout nach ${MailSortRunTimeoutSeconds}s, Watermark NICHT aktualisiert."
    return 1
  }
  # Nur die letzte nicht-leere Zeile zaehlt (CR, Leerzeichen, Markdown-Zeichen ignoriert).
  $lines = @($r.Output -split "`n" | ForEach-Object { $_ -replace '[\s\*`]', '' } | Where-Object { $_ -ne '' })
  $last = if ($lines.Count -gt 0) { $lines[-1] } else { '' }
  if ($r.Code -eq 0 -and $last -ceq $MailSortDoneMarker) {
    $newMark = Get-UtcStamp ($start.AddSeconds(-$MailSortStateMarginSeconds))
    [System.IO.File]::WriteAllText("$MailSortStateFile.tmp", $newMark + "`n", $Utf8)
    Move-Item -LiteralPath "$MailSortStateFile.tmp" -Destination $MailSortStateFile -Force
    Write-Log "[mail-sort] $(Get-UtcStamp (Get-Date)) Lauf beendet (Watermark aktualisiert auf $newMark)."
    return 0
  }
  Write-Log "[mail-sort] $(Get-UtcStamp (Get-Date)) Lauf unvollstaendig oder mit Fehler beendet (Exit $($r.Code), Abschlussmarke $MailSortDoneMarker fehlt als letzte Zeile), Watermark NICHT aktualisiert."
  return 1
}

if ($Once) {
  Invoke-LogRotation
  if (-not (Enter-Lock)) {
    Write-Log "[mail-sort] Ein anderer Lauf ist aktiv (Lock $LockDir). Abbruch."
    exit 3
  }
  $rc = 1
  try { $rc = Invoke-SortRun $Full.IsPresent }
  catch { Write-Log "[mail-sort] $(Get-UtcStamp (Get-Date)) FEHLER: $($_.Exception.Message)" }
  finally { Exit-Lock }
  exit $rc
}

if ($MailSortFirstRunAt -and -not ((Test-Path -LiteralPath $MailSortStateFile) -and (Get-Item -LiteralPath $MailSortStateFile).Length -gt 0)) {
  $target = [datetime]::ParseExact($MailSortFirstRunAt, 'HH:mm', $Inv)
  $target = (Get-Date).Date.Add($target.TimeOfDay)
  if ($target -lt (Get-Date)) { $target = $target.AddDays(1) }
  $wait = [int]($target - (Get-Date)).TotalSeconds
  Write-Log "[mail-sort] $(Get-UtcStamp (Get-Date)) Warte ${wait}s bis zum ersten geplanten Lauf um $MailSortFirstRunAt..."
  Start-Sleep -Seconds $wait
}

$fullNow = $Full.IsPresent
while ($true) {
  Invoke-LogRotation
  if (Enter-Lock) {
    try { [void](Invoke-SortRun $fullNow) }
    catch { Write-Log "[mail-sort] $(Get-UtcStamp (Get-Date)) FEHLER: $($_.Exception.Message)" }
    finally { Exit-Lock }
  } else {
    Write-Log "[mail-sort] $(Get-UtcStamp (Get-Date)) Lauf uebersprungen, anderer Lauf aktiv."
  }
  $fullNow = $false
  Start-Sleep -Seconds $MailSortIntervalSeconds
}
