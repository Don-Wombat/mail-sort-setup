# Diagnose: Kann der Mail-Sort-Skill auf diesem Windows-Rechner laufen?
# Prueft Firmenrichtlinien, Netzwerk und Werkzeuge, BEVOR etwas eingerichtet wird.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\diagnose-windows.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\diagnose-windows.ps1 -All
#
# Nicht ".\diagnose-windows.ps1" direkt starten: die Standard-Richtlinie
# Restricted meldet sonst "Ausfuehrung von Skripts ist deaktiviert". Greift
# auch -ExecutionPolicy Bypass nicht (Gruppenrichtlinie), ohne Dateistart:
#   & ([scriptblock]::Create((Get-Content .\diagnose-windows.ps1 -Raw))) -All
#
# Standard (ohne Schalter): nur Lesen. Es wird nichts installiert, nichts
# geaendert, kein Passwort und kein Mail-Konto angefasst. Keine Adminrechte noetig.
#
# Optionale Tests (jeweils eigener Schalter, -All = alle drei):
#   -TaskTest    legt kurz eine harmlose Aufgabe 'mail-sort-diagnose' in der
#                Aufgabenplanung an, startet sie und entfernt sie wieder.
#   -UvTest      startet 'uvx --from mcp-email-server==1.11.0 mcp-email-server --help' (laedt beim ersten
#                Mal Pakete aus dem Internet, kann Minuten dauern; nur wenn uvx da ist).
#   -ClaudeTest  ruft 'claude -p' mit denselben Schutz-Schaltern wie der echte
#                Lauf auf (ein winziger API-Aufruf "Antworte OK", kein Mail-Zugriff;
#                nur wenn claude da und angemeldet ist). Zeigt, ob verwaltete
#                Claude-Einstellungen (managed-mcp.json usw.) den Lauf blockieren.
#
# Der Bericht (Konsole + Datei) enthaelt: Windows-/PowerShell-Version, ob der
# Rechner in einer Domaene/MDM ist (ja/nein), Richtlinien-Ergebnisse und die
# Aussteller der TLS-Zertifikate von api.anthropic.com, github.com, pypi.org
# (daran erkennt man TLS-Inspection; der Name der Firmen-CA kann auftauchen).
# Keine Passwoerter, Mail-Inhalte, IP-Adressen oder Benutzernamen. Vor dem
# Weitergeben trotzdem kurz durchlesen.
# Datei bewusst nur ASCII (Windows PowerShell 5.1).
param(
  [switch]$TaskTest,
  [switch]$UvTest,
  [switch]$ClaudeTest,
  [switch]$All,
  [string]$ReportPath = (Join-Path ([IO.Path]::GetTempPath()) 'mail-sort-diagnose.txt')
)
$ErrorActionPreference = 'Continue'
if ($All) { $TaskTest = $true; $UvTest = $true; $ClaudeTest = $true }

$script:Report = New-Object System.Collections.Generic.List[string]
$script:Counts = @{ OK = 0; WARN = 0; FAIL = 0; INFO = 0 }

function Out-Line([string]$text, [string]$color = 'Gray') {
  $script:Report.Add($text)
  Write-Host $text -ForegroundColor $color
}
function Add-Section([string]$title) {
  Out-Line ''
  Out-Line ("== " + $title + " ==") 'Cyan'
}
function Add-Result([string]$status, [string]$name, [string]$detail = '') {
  $script:Counts[$status]++
  $color = @{ OK = 'Green'; WARN = 'Yellow'; FAIL = 'Red'; INFO = 'Gray' }[$status]
  $line = ('[{0,-4}] {1}' -f $status, $name)
  if ($detail) { $line += ' - ' + $detail }
  Out-Line $line $color
}

# --- Hilfsfunktionen (wie im Loop) -------------------------------------
function ConvertTo-WinArg([string]$a) {
  if ($a -eq '') { return '""' }
  if ($a -notmatch '[\s"]') { return $a }
  $s = [regex]::Replace($a, '(\\*)"', { param($m) ($m.Groups[1].Value * 2) + '\"' })
  $s = [regex]::Replace($s, '(\\+)$', { param($m) $m.Groups[1].Value * 2 })
  return '"' + $s + '"'
}

function Stop-ProcessTree([System.Diagnostics.Process]$p) {
  if ($PSVersionTable.PSEdition -eq 'Core') { try { $p.Kill($true) } catch { } }
  else { try { & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null } catch { } }
}

# Startet ein Programm (auch .cmd-Shims) mit Timeout. Rueckgabe: Code, Out, Err, TimedOut, Seconds
function Invoke-Native([string]$file, [string[]]$argList, [int]$timeoutSec, [string]$stdinText = '') {
  $utf8 = New-Object System.Text.UTF8Encoding $false
  $argString = ($argList | ForEach-Object { ConvertTo-WinArg $_ }) -join ' '
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $ext = [IO.Path]::GetExtension($file).ToLowerInvariant()
  if ($ext -eq '.cmd' -or $ext -eq '.bat') {
    $psi.FileName = $env:ComSpec
    $psi.Arguments = '/d /s /c "' + (ConvertTo-WinArg $file) + ' ' + $argString + '"'
  } else {
    $psi.FileName = $file
    $psi.Arguments = $argString
  }
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $utf8
  $psi.StandardErrorEncoding = $utf8
  $sw = [Diagnostics.Stopwatch]::StartNew()
  try { $p = [System.Diagnostics.Process]::Start($psi) }
  catch { return @{ Code = 126; Out = ''; Err = $_.Exception.Message; TimedOut = $false; Seconds = 0 } }
  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()
  try {
    $bytes = $utf8.GetBytes($stdinText)
    if ($bytes.Length -gt 0) { $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length); $p.StandardInput.BaseStream.Flush() }
    $p.StandardInput.Close()
  } catch { }
  $timedOut = $false
  if (-not $p.WaitForExit($timeoutSec * 1000)) {
    $timedOut = $true
    Stop-ProcessTree $p
    [void]$p.WaitForExit(15000)
    $code = 124
  } else {
    $p.WaitForExit()
    $code = $p.ExitCode
  }
  [void]$outTask.Wait(15000); [void]$errTask.Wait(15000)
  $o = ''; $e = ''
  if ($outTask.IsCompleted) { $o = $outTask.Result }
  if ($errTask.IsCompleted) { $e = $errTask.Result }
  $sw.Stop()
  return @{ Code = $code; Out = $o.Trim(); Err = $e.Trim(); TimedOut = $timedOut; Seconds = [int]$sw.Elapsed.TotalSeconds }
}

function Get-ShortText([string]$t, [int]$max = 300) {
  $t = ($t -replace '\s+', ' ').Trim()
  if ($t.Length -gt $max) { return $t.Substring(0, $max) + '...' }
  return $t
}

# Aussteller des TLS-Zertifikats + ob die Kette gegen den Windows-Zertifikatspeicher gueltig ist.
function Get-TlsInfo([string]$hostName) {
  $tcp = New-Object Net.Sockets.TcpClient
  try {
    $iar = $tcp.BeginConnect($hostName, 443, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne(8000)) { throw 'Zeitueberschreitung beim Verbinden (8 s)' }
    $tcp.EndConnect($iar)
    $cb = [Net.Security.RemoteCertificateValidationCallback]{ param($s, $c, $ch, $e) $true }
    $ssl = New-Object Net.Security.SslStream($tcp.GetStream(), $false, $cb)
    $ssl.ReadTimeout = 8000
    $ssl.AuthenticateAsClient($hostName)
    $cert = New-Object Security.Cryptography.X509Certificates.X509Certificate2($ssl.RemoteCertificate)
    $chain = New-Object Security.Cryptography.X509Certificates.X509Chain
    $trusted = $chain.Build($cert)
    $issuer = $cert.Issuer
    if ($issuer -match 'CN=([^,]+)') { $issuer = $Matches[1] }
    $root = ''
    if ($chain.ChainElements.Count -gt 0) {
      $root = $chain.ChainElements[$chain.ChainElements.Count - 1].Certificate.Subject
      if ($root -match 'CN=([^,]+)') { $root = $Matches[1] }
    }
    return @{ Ok = $true; Trusted = $trusted; Issuer = $issuer; Root = $root }
  } catch {
    return @{ Ok = $false; Error = $_.Exception.Message }
  } finally { $tcp.Close() }
}

$KnownPublicCa = 'Let.s Encrypt|DigiCert|Amazon|Google Trust|GTS |WE1|WR1|Microsoft|Sectigo|COMODO|USERTrust|GlobalSign|Cloudflare|GoDaddy|Starfield|ISRG|Baltimore|Entrust|Certum|SSL\.com|Buypass|IdenTrust'

# ========================================================================
Out-Line 'Mail-Sort Windows-Diagnose' 'White'
Out-Line ('Zeit: ' + (Get-Date).ToString('yyyy-MM-dd HH:mm') + '   Schalter: TaskTest=' + $TaskTest + ' UvTest=' + $UvTest + ' ClaudeTest=' + $ClaudeTest)

# === 1. SYSTEM =========================================================
Add-Section '1. System'
try {
  $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
  $winName = if ([int]$cv.CurrentBuild -ge 22000) { 'Windows 11' } else { 'Windows 10' }
  Add-Result 'INFO' 'Windows' ("{0} {1} ({2}), Build {3}, Sprache {4}" -f $winName, $cv.DisplayVersion, $cv.EditionID, $cv.CurrentBuild, (Get-Culture).Name)
} catch { Add-Result 'INFO' 'Windows' 'nicht lesbar' }
Add-Result 'INFO' 'PowerShell' ("{0} {1}" -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) { Add-Result 'INFO' 'Adminrechte' 'ja (der Skill braucht keine; fuer einen realistischen Test als Standardnutzer starten)' }
else { Add-Result 'INFO' 'Adminrechte' 'nein (Standardnutzer)' }

try {
  $inDomain = $null
  try { $inDomain = [bool](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).PartOfDomain } catch { }
  if ($null -eq $inDomain) {
    $dnsSuffix = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -ErrorAction SilentlyContinue).Domain
    $inDomain = [bool]$dnsSuffix
  }
  Add-Result 'INFO' 'Active-Directory-Domaene' $(if ($inDomain) { 'ja' } else { 'nein' })
} catch { }
try {
  $mdm = $false
  $enr = 'HKLM:\SOFTWARE\Microsoft\Enrollments'
  if (Test-Path $enr) {
    foreach ($k in Get-ChildItem $enr -ErrorAction SilentlyContinue) {
      $prov = (Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue).ProviderID
      if ($prov -eq 'MS DM Server') { $mdm = $true }
    }
  }
  Add-Result 'INFO' 'MDM/Intune-Anmeldung' $(if ($mdm) { 'ja' } else { 'nein erkannt' })
} catch { }

# === 2. POWERSHELL-RICHTLINIEN =========================================
Add-Section '2. PowerShell-Richtlinien'
try {
  $lm = $ExecutionContext.SessionState.LanguageMode
  if ($lm -eq 'FullLanguage') { Add-Result 'OK' 'Language Mode' 'FullLanguage' }
  else { Add-Result 'FAIL' 'Language Mode' ("$lm - die Skripte des Skills laufen so voraussichtlich nicht (AppLocker/WDAC-Skriptregeln?)") }
} catch { }

$lines = @()
foreach ($e in (Get-ExecutionPolicy -List)) { $lines += ("{0}={1}" -f $e.Scope, $e.ExecutionPolicy) }
Add-Result 'INFO' 'Ausfuehrungsrichtlinie' ($lines -join ', ')
$mp = Get-ExecutionPolicy -Scope MachinePolicy
$up = Get-ExecutionPolicy -Scope UserPolicy
if ($mp -ne 'Undefined' -or $up -ne 'Undefined') {
  Add-Result 'WARN' 'Richtlinie per Gruppenrichtlinie' "MachinePolicy=$mp UserPolicy=$up - hat Vorrang vor '-ExecutionPolicy Bypass'; Test unten zeigt, ob der Start trotzdem klappt"
} else {
  Add-Result 'OK' 'Keine Ausfuehrungsrichtlinie per Gruppenrichtlinie' ''
}

# Praxistest: genau der Aufruf, den die Aufgabenplanung spaeter macht.
$tmpDir = Join-Path ([IO.Path]::GetTempPath()) ('mail-sort-diag-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
try {
  $probe = Join-Path $tmpDir 'probe.ps1'
  [IO.File]::WriteAllText($probe, "Write-Output 'probe-ok'", (New-Object Text.UTF8Encoding $true))
  $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $r = Invoke-Native $psExe @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $probe) 30
  if ($r.Code -eq 0 -and $r.Out -match 'probe-ok') { Add-Result 'OK' 'Skriptstart mit -ExecutionPolicy Bypass' 'funktioniert' }
  else { Add-Result 'FAIL' 'Skriptstart mit -ExecutionPolicy Bypass' ("Exit {0}: {1}" -f $r.Code, (Get-ShortText ($r.Err + ' ' + $r.Out))) }
} catch { Add-Result 'FAIL' 'Skriptstart mit -ExecutionPolicy Bypass' $_.Exception.Message }

# === 3. PROGRAMMSPERREN ================================================
Add-Section '3. AppLocker / WDAC'
$candidates = @()
$psExePath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$candidates += $psExePath
foreach ($n in 'claude', 'uv', 'uvx') {
  $c = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { $candidates += $c.Source }
}
# Typische Installationsorte (winget/Installer), falls noch nicht im PATH
foreach ($p in @("$env:LOCALAPPDATA\Programs\claude\claude.exe", "$env:USERPROFILE\.local\bin\claude.exe", "$env:USERPROFILE\.local\bin\uv.exe", "$env:LOCALAPPDATA\Microsoft\WinGet\Links\uv.exe")) {
  if ((Test-Path -LiteralPath $p) -and ($candidates -notcontains $p)) { $candidates += $p }
}
try {
  $pol = Get-AppLockerPolicy -Effective -ErrorAction Stop
  $ruleCount = 0
  foreach ($rc in $pol.RuleCollections) { $ruleCount += @($rc).Count }
  if ($ruleCount -eq 0) {
    Add-Result 'OK' 'AppLocker' 'keine wirksamen Regeln'
  } else {
    Add-Result 'WARN' 'AppLocker' "$ruleCount wirksame Regeln - Pruefung der Zielprogramme:"
    foreach ($p in $candidates) {
      try {
        $res = $pol | Test-AppLockerPolicy -Path $p -ErrorAction Stop
        $dec = $res.PolicyDecision
        $st = if ($dec -match 'Allowed') { 'OK' } else { 'FAIL' }
        Add-Result $st ('AppLocker: ' + (Split-Path $p -Leaf)) ([string]$dec)
      } catch { Add-Result 'INFO' ('AppLocker: ' + (Split-Path $p -Leaf)) 'nicht pruefbar' }
    }
  }
} catch {
  # Cmdlet fehlt (z.B. Windows-Edition ohne AppLocker-Modul): Regeln direkt in der Registry zaehlen.
  $srp = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SrpV2'
  $cnt = 0
  if (Test-Path $srp) {
    foreach ($col in Get-ChildItem $srp -ErrorAction SilentlyContinue) {
      $cnt += @(Get-ChildItem $col.PSPath -ErrorAction SilentlyContinue).Count
    }
  }
  if ($cnt -gt 0) { Add-Result 'WARN' 'AppLocker' "$cnt Regeln in der Registry (SrpV2), Cmdlet zum Pruefen fehlt - bitte mit der IT klaeren, ob claude.exe/uvx.exe/Python aus dem Benutzerprofil erlaubt sind" }
  else { Add-Result 'OK' 'AppLocker' 'keine Regeln in der Registry (SrpV2) gefunden' }
}
try {
  $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop
  $st = $dg.CodeIntegrityPolicyEnforcementStatus
  if ($st -eq 1) { Add-Result 'WARN' 'WDAC (Code Integrity)' 'Richtlinie wird erzwungen - nur freigegebene Programme laufen' }
  elseif ($st -eq 2) { Add-Result 'INFO' 'WDAC (Code Integrity)' 'nur Audit-Modus' }
  else { Add-Result 'OK' 'WDAC (Code Integrity)' 'keine erzwungene Richtlinie' }
} catch { Add-Result 'INFO' 'WDAC (Code Integrity)' 'nicht abfragbar' }

# === 4. WERKZEUGE ======================================================
Add-Section '4. Werkzeuge'
$claudeCmd = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($claudeCmd) {
  $r = Invoke-Native $claudeCmd.Source @('--version') 30
  Add-Result 'OK' 'claude' ("gefunden, Version: " + (Get-ShortText $r.Out 60))
} else {
  Add-Result 'FAIL' 'claude' 'nicht im PATH (Claude Code muss auf diesem Rechner/in dieser Umgebung installiert sein)'
}
$uvxCmd = Get-Command uvx -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$uvCmd = Get-Command uv -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($uvxCmd) {
  $r = Invoke-Native $uvxCmd.Source @('--version') 30
  Add-Result 'OK' 'uvx' ("gefunden: " + (Get-ShortText $r.Out 60))
} else {
  Add-Result 'WARN' 'uvx' 'nicht gefunden (wird fuer mcp-email-server gebraucht; Installation: winget install astral-sh.uv --skip-dependencies)'
}
$wg = Get-Command winget -ErrorAction SilentlyContinue
if ($wg) { Add-Result 'OK' 'winget' 'vorhanden' } else { Add-Result 'WARN' 'winget' 'nicht vorhanden - claude/uv muessen anders installiert werden' }
$py = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($py) { Add-Result 'INFO' 'python' 'im PATH (nicht noetig, uv bringt eigenes Python mit)' }

# === 5. CLAUDE-CODE-EINSTELLUNGEN VON DER FIRMA ========================
Add-Section '5. Verwaltete Claude-Code-Einstellungen'
$relevant = 'allowedMcpServers|deniedMcpServers|allowManagedMcpServersOnly|allowManagedPermissionRulesOnly|allowManagedHooksOnly|permissions|strictPluginOnlyCustomization|managedMcpServers|disableBypassPermissionsMode|defaultMode'
function Show-ManagedJson([string]$label, [string]$json) {
  try {
    $obj = $json | ConvertFrom-Json -ErrorAction Stop
    $keys = @($obj.PSObject.Properties.Name)
    Add-Result 'WARN' $label ("vorhanden, oberste Schluessel: " + ($keys -join ', '))
    $hits = @($keys | Where-Object { $_ -match "^($relevant)$" })
    if ($hits.Count -gt 0) { Add-Result 'WARN' ($label + ' / relevant fuer den Skill') ($hits -join ', ') }
    return $obj
  } catch {
    Add-Result 'FAIL' $label 'vorhanden, aber nicht als JSON lesbar (Claude Code startet dann gar nicht)'
    return $null
  }
}
$cdir = Join-Path $env:ProgramFiles 'ClaudeCode'
$ms = Join-Path $cdir 'managed-settings.json'
$mm = Join-Path $cdir 'managed-mcp.json'
$md = Join-Path $cdir 'managed-settings.d'
$anyManaged = $false
if (Test-Path -LiteralPath $ms) {
  $anyManaged = $true
  try { [void](Show-ManagedJson 'managed-settings.json' ([IO.File]::ReadAllText($ms))) } catch { Add-Result 'WARN' 'managed-settings.json' 'vorhanden, nicht lesbar' }
}
if (Test-Path -LiteralPath $md) {
  $anyManaged = $true
  $n = @(Get-ChildItem -LiteralPath $md -Filter *.json -ErrorAction SilentlyContinue).Count
  Add-Result 'WARN' 'managed-settings.d' "vorhanden, $n JSON-Dateien"
  foreach ($f in Get-ChildItem -LiteralPath $md -Filter *.json -ErrorAction SilentlyContinue) {
    try { [void](Show-ManagedJson ('managed-settings.d/' + $f.Name) ([IO.File]::ReadAllText($f.FullName))) } catch { }
  }
}
if (Test-Path -LiteralPath $mm) {
  $anyManaged = $true
  try {
    $obj = Show-ManagedJson 'managed-mcp.json' ([IO.File]::ReadAllText($mm))
    if ($obj -and $obj.mcpServers) {
      $names = @($obj.mcpServers.PSObject.Properties.Name)
      Add-Result 'FAIL' 'managed-mcp.json: Folge' ("Claude Code erlaubt nur diese Server: " + ($names -join ', ') + ". Der Skill uebergibt seinen Mail-Server per --mcp-config und wird so abgelehnt; die IT muesste ihn in die Datei aufnehmen.")
    }
  } catch { Add-Result 'WARN' 'managed-mcp.json' 'vorhanden, nicht lesbar' }
}
foreach ($hive in 'HKLM', 'HKCU') {
  $rk = $hive + ':\SOFTWARE\Policies\ClaudeCode'
  if (Test-Path $rk) {
    $v = (Get-ItemProperty -Path $rk -ErrorAction SilentlyContinue).Settings
    if ($v) {
      if ($hive -eq 'HKLM') { $anyManaged = $true }
      [void](Show-ManagedJson ($hive + ' Registry (Policies\ClaudeCode)') ([string]$v))
    } else { Add-Result 'INFO' ($hive + ' Registry (Policies\ClaudeCode)') 'Schluessel vorhanden, aber kein Settings-Wert' }
  }
}
if (-not $anyManaged) {
  Add-Result 'OK' 'Keine lokalen verwalteten Claude-Einstellungen gefunden' 'Datei/Registry leer. Server-managed Settings (claude.ai-Admin-Konsole) sieht man nur in Claude Code unter /status.'
}

# === 6. NETZWERK =======================================================
Add-Section '6. Netzwerk und TLS'
try {
  $proxyUri = [Net.WebRequest]::GetSystemWebProxy().GetProxy([Uri]'https://pypi.org')
  $viaProxy = ($proxyUri -and $proxyUri.Host -ne 'pypi.org')
  Add-Result 'INFO' 'System-Proxy fuer HTTPS' $(if ($viaProxy) { 'ja (uv/Python/claude muessen ihn nutzen: HTTPS_PROXY)' } else { 'nein' })
} catch { }
if ($env:HTTPS_PROXY -or $env:https_proxy) { Add-Result 'INFO' 'Umgebungsvariable HTTPS_PROXY' 'gesetzt' }
if ($env:SSL_CERT_FILE -or $env:NODE_EXTRA_CA_CERTS -or $env:UV_NATIVE_TLS) {
  Add-Result 'INFO' 'CA-Variablen' (((@('SSL_CERT_FILE', 'NODE_EXTRA_CA_CERTS', 'UV_NATIVE_TLS') | Where-Object { [Environment]::GetEnvironmentVariable($_) }) -join ', ') + ' gesetzt')
}
$inspection = $false
foreach ($h in 'api.anthropic.com', 'github.com', 'pypi.org', 'files.pythonhosted.org') {
  $t = Get-TlsInfo $h
  if (-not $t.Ok) { Add-Result 'FAIL' ("TLS " + $h) (Get-ShortText $t.Error 150); continue }
  $known = ($t.Issuer -match $KnownPublicCa) -or ($t.Root -match $KnownPublicCa)
  if (-not $t.Trusted) { Add-Result 'FAIL' ("TLS " + $h) ("Zertifikatskette nicht vertrauenswuerdig. Aussteller: " + $t.Issuer) }
  elseif ($known) { Add-Result 'OK' ("TLS " + $h) ("Aussteller: " + $t.Issuer) }
  else { $inspection = $true; Add-Result 'WARN' ("TLS " + $h) ("Aussteller '" + $t.Issuer + "' (Root '" + $t.Root + "') ist keine bekannte oeffentliche CA - vermutlich TLS-Inspection der Firma") }
}
if ($inspection) {
  Out-Line '       Hinweis: Bei TLS-Inspection vertraut Windows der Firmen-CA, uv/Python aber oft nicht.' 'Yellow'
  Out-Line '       Moegliche Abhilfe (ungetestet): Umgebungsvariable UV_NATIVE_TLS=1 (uv nutzt den Windows-Zertifikatspeicher) bzw. SSL_CERT_FILE auf die CA-Datei der IT.' 'Yellow'
}

# === 7. OPTIONALE TESTS ================================================
Add-Section '7. Optionale Praxistests'

if ($TaskTest) {
  # schtasks.exe statt ScheduledTasks-Cmdlets: die Cmdlets brauchen WMI/CIM-Zugriff, den
  # Standardnutzer in manchen Sitzungen (z.B. per SSH) nicht haben.
  $tn = 'mail-sort-diagnose'
  $st = Join-Path $env:SystemRoot 'System32\schtasks.exe'
  try {
    $marker = Join-Path $tmpDir 'task-ran.txt'
    $taskScript = Join-Path $tmpDir 'task.ps1'
    [IO.File]::WriteAllText($taskScript, ("Set-Content -LiteralPath '" + $marker + "' -Value 'ok'"), (New-Object Text.UTF8Encoding $true))
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $tr = (ConvertTo-WinArg $psExe) + ' -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File ' + (ConvertTo-WinArg $taskScript)
    $r = Invoke-Native $st @('/Create', '/TN', $tn, '/SC', 'DAILY', '/ST', '03:00', '/F', '/TR', $tr) 30
    if ($r.Code -ne 0) { throw ("Anlegen fehlgeschlagen (Exit {0}): {1}" -f $r.Code, (Get-ShortText ($r.Err + ' ' + $r.Out) 200)) }
    Add-Result 'OK' 'Aufgabenplanung: Aufgabe anlegen' 'funktioniert als dieser Nutzer'
    $r = Invoke-Native $st @('/Run', '/TN', $tn) 30
    if ($r.Code -ne 0) { throw ("Starten fehlgeschlagen (Exit {0}): {1}" -f $r.Code, (Get-ShortText ($r.Err + ' ' + $r.Out) 200)) }
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $marker)) { Start-Sleep -Milliseconds 500 }
    if (Test-Path -LiteralPath $marker) { Add-Result 'OK' 'Aufgabenplanung: Aufgabe starten' 'Skript lief' }
    else { Add-Result 'FAIL' 'Aufgabenplanung: Aufgabe starten' 'Skript lief nicht innerhalb von 30 s (Richtlinie? Nutzer nicht angemeldet?)' }
  } catch {
    Add-Result 'FAIL' 'Aufgabenplanung' (Get-ShortText $_.Exception.Message 250)
  } finally {
    $r = Invoke-Native $st @('/Delete', '/TN', $tn, '/F') 30
    $q = Invoke-Native $st @('/Query', '/TN', $tn) 30
    if ($q.Code -eq 0) { Add-Result 'WARN' 'Aufgabenplanung' "Testaufgabe '$tn' konnte nicht entfernt werden - bitte manuell: schtasks /Delete /TN $tn /F" }
  }
} else { Add-Result 'INFO' 'Aufgabenplanung' 'uebersprungen (-TaskTest)' }

if ($UvTest) {
  if ($uvxCmd) {
    Out-Line '       (uvx-Start laeuft, beim ersten Mal kann das mehrere Minuten dauern ...)' 'Gray'
    $r = Invoke-Native $uvxCmd.Source @('--from', 'mcp-email-server==1.11.0', 'mcp-email-server', '--help') 600
    if ($r.TimedOut) { Add-Result 'FAIL' 'uvx mcp-email-server==1.11.0' 'Zeitueberschreitung nach 600 s (Download blockiert? Proxy/TLS-Inspection?)' }
    elseif ($r.Code -eq 0) { Add-Result 'OK' 'uvx mcp-email-server==1.11.0' ("startet, " + $r.Seconds + " s") }
    elseif (($r.Err + ' ' + $r.Out) -match 'os error 448|nicht vertrauensw|untrusted mount point') { Add-Result 'WARN' 'uvx mcp-email-server==1.11.0' 'Windows meldet "nicht vertrauenswuerdiger Bereitstellungspunkt" (Fehler 448) beim Zugriff auf uvs Python-Ordner. Das tritt in Remote-/SSH-Sitzungen auf; bitte den Test in einer normalen, lokal angemeldeten PowerShell wiederholen.' }
    else { Add-Result 'FAIL' 'uvx mcp-email-server==1.11.0' ("Exit {0}: {1}" -f $r.Code, (Get-ShortText ($r.Err + ' ' + $r.Out) 400)) }
  } else { Add-Result 'INFO' 'uvx-Test' 'uebersprungen (uvx fehlt)' }
} else { Add-Result 'INFO' 'uvx-Test' 'uebersprungen (-UvTest)' }

if ($ClaudeTest) {
  if ($claudeCmd) {
    $cfg = Join-Path $tmpDir 'mcp.json'
    [IO.File]::WriteAllText($cfg, '{"mcpServers":{"mail":{"command":"uvx","args":["--from","mcp-email-server==1.11.0","mcp-email-server","stdio"]}}}', (New-Object Text.UTF8Encoding $false))
    $allowed = @('mcp__mail__list_available_accounts', 'mcp__mail__list_emails_metadata', 'mcp__mail__list_mailboxes', 'mcp__mail__list_email_tags', 'mcp__mail__move_emails', 'mcp__mail__set_email_tags')
    $denied = @('mcp__mail__send_email', 'mcp__mail__forward_email', 'mcp__mail__save_to_mailbox', 'mcp__mail__delete_emails', 'mcp__mail__archive_emails', 'mcp__mail__set_email_flags', 'mcp__mail__mark_emails_as_read', 'mcp__mail__get_emails_content', 'mcp__mail__download_attachment', 'mcp__mail__get_attachment_content')
    $cargs = @('-p', '--permission-mode', 'dontAsk', '--tools', '', '--strict-mcp-config', '--mcp-config', $cfg, '--allowedTools') + $allowed + @('--disallowedTools') + $denied
    $r = Invoke-Native $claudeCmd.Source $cargs 120 'Antworte nur mit dem Wort OK.'
    $combined = ($r.Out + ' ' + $r.Err)
    if ($r.TimedOut) { Add-Result 'FAIL' 'claude -p (gehaerteter Aufruf)' 'Zeitueberschreitung nach 120 s (Netzwerk? Anmeldung?)' }
    elseif ($combined -match 'enterprise MCP config|dynamically configure MCP') { Add-Result 'FAIL' 'claude -p (gehaerteter Aufruf)' 'durch managed-mcp.json blockiert: --mcp-config ist verboten. Die IT muesste den Mail-Server in managed-mcp.json aufnehmen.' }
    elseif ($combined -match 'not allowed by enterprise policy|blocked by enterprise') { Add-Result 'FAIL' 'claude -p (gehaerteter Aufruf)' ('Mail-Server per Unternehmensrichtlinie blockiert (allowedMcpServers/deniedMcpServers in den verwalteten Einstellungen) - die IT muesste ihn freigeben: ' + (Get-ShortText $combined 200)) }
    elseif ($r.Code -eq 0 -and $r.Out -match 'OK') { Add-Result 'OK' 'claude -p (gehaerteter Aufruf)' ("laeuft mit allen Schutz-Schaltern, " + $r.Seconds + " s") }
    elseif ($combined -match 'login|Not logged in|authenticat|API key|credit') { Add-Result 'WARN' 'claude -p (gehaerteter Aufruf)' ('nicht angemeldet oder Konto-Problem - erst "claude" starten und /login: ' + (Get-ShortText $combined 200)) }
    else { Add-Result 'FAIL' 'claude -p (gehaerteter Aufruf)' ("Exit {0}: {1}" -f $r.Code, (Get-ShortText $combined 300)) }
  } else { Add-Result 'INFO' 'claude-Test' 'uebersprungen (claude fehlt)' }
} else { Add-Result 'INFO' 'claude-Test' 'uebersprungen (-ClaudeTest)' }

# === ZUSAMMENFASSUNG ===================================================
Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
Add-Section 'Zusammenfassung'
Out-Line ("OK: {0}   WARN: {1}   FAIL: {2}" -f $script:Counts.OK, $script:Counts.WARN, $script:Counts.FAIL) 'White'
if ($script:Counts.FAIL -gt 0) { Out-Line 'Es gibt FAIL-Punkte: Der Skill laeuft hier voraussichtlich nicht, bevor sie geklaert sind (mit der IT besprechen).' 'Red' }
elseif ($script:Counts.WARN -gt 0) { Out-Line 'Keine harten Blocker, aber WARN-Punkte pruefen.' 'Yellow' }
else { Out-Line 'Keine Auffaelligkeiten gefunden.' 'Green' }
Out-Line 'Nicht pruefbar von hier aus: server-managed Settings (in Claude Code /status), Netzwerkfilter pro Zielseite jenseits der getesteten Hosts, Datenschutz-/Compliance-Freigabe.' 'Gray'
try {
  [IO.File]::WriteAllText($ReportPath, (($script:Report -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding $true))
  Write-Host ''
  Write-Host ("Bericht gespeichert: " + $ReportPath) -ForegroundColor White
} catch { Write-Host 'Bericht konnte nicht gespeichert werden.' -ForegroundColor Yellow }
