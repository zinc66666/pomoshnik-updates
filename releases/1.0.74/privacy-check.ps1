# «Кто включал камеру и микрофон»: журнал Windows о доступе программ к камере, микрофону и геолокации. Только чтение.
$ErrorActionPreference = 'SilentlyContinue'
$Host.UI.RawUI.WindowTitle = 'Кто включал камеру и микрофон'
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
$base = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'
$names = @{ 'discord' = 'Discord'; 'telegram' = 'Telegram'; 'browser' = 'Яндекс Браузер'; 'chrome' = 'Chrome'; 'msedge' = 'Edge'; 'zoom' = 'Zoom'; 'anydesk' = 'AnyDesk'; 'obs64' = 'OBS'; 'ts3client_win64' = 'TeamSpeak'; 'svchost' = 'служба Windows'; 'happ' = 'Happ' }
function Nice($k) { if ($k -match '#') { $leaf = ($k -split '#')[-1]; $b = [IO.Path]::GetFileNameWithoutExtension($leaf); if ($names.ContainsKey($b.ToLower())) { $names[$b.ToLower()] } else { $leaf } }
  else { (($k -split '_')[0] -replace '^Microsoft\.Windows', '' -replace '^Microsoft\.', '') } }
Step -Safe
Step -Plan 'Смотрю, кто пользовался камерой', 'Смотрю, кто пользовался микрофоном', 'Смотрю, кто пользовался геолокацией', 'Готовлю итог'
Write-Host "`nКТО ВКЛЮЧАЛ КАМЕРУ, МИКРОФОН И ГЕОЛОКАЦИЮ`n" -ForegroundColor Cyan
Write-Host 'Windows сама записывает, какая программа и когда этим пользовалась. Здесь — последние записи.' -ForegroundColor DarkGray
$now = @()
foreach ($cap in @(@('webcam', 'КАМЕРА', 'камерой'), @('microphone', 'МИКРОФОН', 'микрофоном'), @('location', 'ГЕОЛОКАЦИЯ', 'геолокацией'))) {
  Step "Смотрю, кто пользовался $($cap[2])"
  $glob = (Get-ItemProperty "$base\$($cap[0])").Value
  Write-Host ("`n{0}  (доступ для программ: {1})" -f $cap[1], $(if ($glob -eq 'Deny') { 'запрещён' } else { 'разрешён' })) -ForegroundColor Yellow
  $rows = foreach ($k in @(Get-ChildItem "$base\$($cap[0])") + @(Get-ChildItem "$base\$($cap[0])\NonPackaged")) {
    $p = Get-ItemProperty $k.PSPath; if (-not $p.LastUsedTimeStart) { continue }
    $s = [DateTime]::FromFileTime([int64]$p.LastUsedTimeStart); $active = [int64]$p.LastUsedTimeStop -eq 0 -or [int64]$p.LastUsedTimeStop -lt [int64]$p.LastUsedTimeStart
    [pscustomobject]@{ N = Nice $k.PSChildName; S = $s; A = $active } }
  $rows = @($rows | Sort-Object S -Descending | Select-Object -First 8)
  if (-not $rows) { Write-Host '  записей нет' -ForegroundColor DarkGray }
  foreach ($r in $rows) { if ($r.A) { $now += "$($cap[1].ToLower()): $($r.N)" }
    Write-Host ("  {0:dd.MM.yyyy HH:mm}   {1}{2}" -f $r.S, $r.N, $(if ($r.A) { '   ← ИСПОЛЬЗУЕТ СЕЙЧАС' } else { '' })) -ForegroundColor $(if ($r.A) { 'Red' } else { 'Gray' }) }
  Step -Done $(if ($rows) { "записей: $($rows.Count)" } else { 'записей нет' }) }
Step 'Готовлю итог'
Write-Host ''
if ($now) { Write-Host ("Прямо сейчас используется: {0}." -f ($now -join '; ')) -ForegroundColor Red }
Step -Done $(if ($now) { "сейчас используют: $($now.Count)" } else { 'сейчас никто' })
Write-Host 'Если видишь программу, которой ты камеру или микрофон не давала, — не трогай её и нажми «Позвать помощь».' -ForegroundColor Yellow
Write-Host 'Discord, Telegram, браузер и AnyDesk в списке — это нормально, если ты ими звонила.' -ForegroundColor DarkGray
Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null
