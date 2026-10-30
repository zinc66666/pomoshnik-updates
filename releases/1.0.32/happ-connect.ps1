# При входе: дождаться Happ (его автозапуск) и подключить его ссылкой happ://connect; одна повторная попытка.
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
$pt = PctSocksPort
Step -Plan 'Жду, пока откроется Happ', 'Жду, пока Happ загрузится', 'Подключаю Happ', 'Сворачиваю окно Happ'
Step 'Жду, пока откроется Happ' -Hint 'Сам Happ открывается при входе, до 2 минут'
for ($i = 0; $i -lt 60 -and -not (Get-Process Happ); $i++) { Start-Sleep 2 }
# Happ так и не запустился — ищу Happ.exe: Program Files, программы пользователя, папка Happ в корне каждого локального диска
if (Get-Process Happ) { Step -Done 'Happ открыт' } else { Step -Warn 'Happ сам не открылся'; Step 'Ищу и открываю Happ' -Hint 'Program Files, программы пользователя, папка Happ на дисках' }
if (-not (Get-Process Happ)) { $hx = @("$env:ProgramFiles\Happ", "${env:ProgramFiles(x86)}\Happ", "$env:LOCALAPPDATA\Programs\Happ") + @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object { "$($_.Name)Happ" }) | ForEach-Object { "$_\Happ.exe" } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if ($hx) { Start-Process $hx -ArgumentList '--autostart'; Start-Sleep 15; if (Get-Process Happ) { Step -Done 'Happ открыт' } else { Step -Warn 'Happ не открылся' } }
  else { Step -Warn 'Happ не нашёл' } }
Step 'Жду, пока Happ загрузится' -Hint '10 с'; Start-Sleep 10; Step -Done 'дождался'
$on = [bool](Get-NetTCPConnection -State Listen -LocalPort $pt); if ($on) { Step 'Подключаю Happ'; Step -Done 'уже подключён' }
foreach ($try in 1, 2) {
  if ($on) { break }
  Step "Подключаю Happ, попытка $try из 2" -Hint 'Жду подключения, до 30 с'; Start-Process 'happ://connect'
  for ($i = 0; $i -lt 15 -and -not (Get-NetTCPConnection -State Listen -LocalPort $pt); $i++) { Start-Sleep 2 }
  $on = [bool](Get-NetTCPConnection -State Listen -LocalPort $pt)
  if ($on) { Step -Done 'Happ подключён' } elseif ($try -lt 2) { Step -Warn 'не подключился, пробую ещё раз' } else { Step -Fail 'Happ не подключился' -Do 'Открой Happ и нажми большую кнопку подключения.' } }
Step 'Сворачиваю окно Happ'
# свернуть окно Happ, которое открывается после happ://connect
Add-Type -Namespace PCT -Name Win -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int c);'
Start-Sleep 2
Get-Process Happ | Where-Object MainWindowHandle -ne 0 | ForEach-Object { [PCT.Win]::ShowWindow($_.MainWindowHandle, 6) | Out-Null }
Step -Done 'готово'
