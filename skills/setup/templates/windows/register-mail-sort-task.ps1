# Richtet den Mail-Sort-Lauf in der Windows-Aufgabenplanung ein (lokaler
# Pfad, Windows nativ). Keine Administratorrechte noetig.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\register-mail-sort-task.ps1 -ProjectDir "C:\Users\<name>\mail-sort" -StartAt 07:00 -IntervalHours 4
#
# Wieder entfernen:  Unregister-ScheduledTask -TaskName mail-sort -Confirm:$false
# Sofort ausloesen:  Start-ScheduledTask -TaskName mail-sort
#
# Die Aufgabe laeuft nur, solange der Nutzer angemeldet ist (wie ein
# systemd-User-Timer ohne linger). Verpasste Laeufe (PC aus/Standby) werden
# nachgeholt (StartWhenAvailable, entspricht Persistent=true bei systemd).
# Datei bewusst nur ASCII (Windows PowerShell 5.1).
param(
  [Parameter(Mandatory = $true)] [string]$ProjectDir,
  [string]$StartAt = '07:00',
  [ValidateSet(1, 2, 3, 4, 6, 8, 12, 24)] [int]$IntervalHours = 4,
  [string]$TaskName = 'mail-sort'
)
$ErrorActionPreference = 'Stop'

$ProjectDir = (Resolve-Path -LiteralPath $ProjectDir).Path
$loop = Join-Path $ProjectDir 'mail-sort-loop.ps1'
if (-not (Test-Path -LiteralPath $loop)) { throw "mail-sort-loop.ps1 nicht gefunden in $ProjectDir" }

$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arg = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $loop + '" -Once'
$action = New-ScheduledTaskAction -Execute $psExe -Argument $arg -WorkingDirectory $ProjectDir

# Ein taeglicher Trigger pro Zeitpunkt (robuster als ein Wiederholungsmuster).
$first = [datetime]::ParseExact($StartAt, 'HH:mm', [Globalization.CultureInfo]::InvariantCulture)
$triggers = @()
for ($h = 0; $h -lt 24; $h += $IntervalHours) {
  $triggers += New-ScheduledTaskTrigger -Daily -At $first.AddHours($h)
}

# 35 min: etwas mehr als das Zeitlimit im Loop (30 min). Kein paralleler Start.
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -ExecutionTimeLimit (New-TimeSpan -Minutes 35) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Settings $settings -Principal $principal `
  -Description 'Mail-Sort: automatischer Sortierlauf (liest, verschiebt, markiert; sendet und loescht nie)' -Force | Out-Null

$info = Get-ScheduledTaskInfo -TaskName $TaskName
Write-Host "Aufgabe '$TaskName' eingerichtet. Naechster Lauf: $($info.NextRunTime)"
