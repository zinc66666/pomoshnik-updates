# При входе: дождаться Happ (его автозапуск) и подключить его ссылкой happ://connect; одна повторная попытка.
$ErrorActionPreference = 'SilentlyContinue'
for ($i = 0; $i -lt 60 -and -not (Get-Process Happ); $i++) { Start-Sleep 2 }
# Happ так и не запустился — ищу Happ.exe: Program Files, программы пользователя, папка Happ в корне каждого локального диска
if (-not (Get-Process Happ)) { $hx = @("$env:ProgramFiles\Happ", "${env:ProgramFiles(x86)}\Happ", "$env:LOCALAPPDATA\Programs\Happ") + @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object { "$($_.Name)Happ" }) | ForEach-Object { "$_\Happ.exe" } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if ($hx) { Start-Process $hx -ArgumentList '--autostart'; Start-Sleep 15 } }
Start-Sleep 10
foreach ($try in 1, 2) {
  if (Get-NetTCPConnection -State Listen -LocalPort 10808) { break }
  Start-Process 'happ://connect'
  for ($i = 0; $i -lt 15 -and -not (Get-NetTCPConnection -State Listen -LocalPort 10808); $i++) { Start-Sleep 2 } }
# свернуть окно Happ, которое открывается после happ://connect
Add-Type -Namespace PCT -Name Win -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int c);'
Start-Sleep 2
Get-Process Happ | Where-Object MainWindowHandle -ne 0 | ForEach-Object { [PCT.Win]::ShowWindow($_.MainWindowHandle, 6) | Out-Null }