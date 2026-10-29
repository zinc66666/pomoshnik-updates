param([switch]$Rebaseline, [switch]$Report)
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
$G = PctDir 'guard'; . (PctNotifyPath)
function Get-Autoruns {
  foreach ($k in 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce','HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce') {
    (Get-ItemProperty $k).PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { "Run | $k | $($_.Name) | $($_.Value)" } }
  foreach ($d in "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup","$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup") {
    Get-ChildItem $d -Force | Where-Object Name -ne 'desktop.ini' | ForEach-Object { "Startup | $($_.FullName)" } }
  Get-CimInstance Win32_Service | Where-Object StartMode -eq 'Auto' | ForEach-Object { "Service | $($_.Name -replace '_[0-9a-f]{4,8}$','') | $($_.PathName)" }
  Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } | ForEach-Object { "Task | $($_.TaskPath)$($_.TaskName) | " + (($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' ; ') }
  $w = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon'; "Winlogon | Shell=$($w.Shell) | Userinit=$($w.Userinit)"
  Get-ChildItem 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Image File Execution Options' | ForEach-Object { $dbg = (Get-ItemProperty $_.PSPath).Debugger; if ($dbg) { "IFEO | $($_.PSChildName) | $dbg" } }
  Get-CimInstance -Namespace root\subscription -ClassName __EventConsumer | ForEach-Object { "WMI | $($_.CimClass.CimClassName) | $($_.Name)" }
}
$base = "$G\autoruns-baseline.txt"
$now = @(Get-Autoruns | Sort-Object -Unique)
if ($Rebaseline -or -not (Test-Path $base)) { [IO.File]::WriteAllLines($base, [string[]]$now, (New-Object Text.UTF8Encoding $true)); if ($Rebaseline) { "Снимок автозапуска обновлён: $($now.Count) записей." }; return }
$old = Get-Content $base -Encoding UTF8
$new = @($now | Where-Object { $old -notcontains $_ })
$gone = @($old | Where-Object { $now -notcontains $_ })
if ($Report) { return [pscustomobject]@{ New = $new; Gone = $gone } }
if ($new.Count) {
  $short = ($new | Select-Object -First 3 | ForEach-Object { ($_ -split ' \| ')[0..2] -join ': ' }) -join "`n"
  Send-Notify "Новое в автозапуске: $($new.Count)" "$short`nЕсли вы это не ставили — откройте «Проверка безопасности» на рабочем столе."
}