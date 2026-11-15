$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
function Get-RealIf { $a = Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | Sort-Object { ($r = Get-NetRoute -InterfaceIndex $_.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1); if ($r) { $r.RouteMetric + $_.InterfaceMetric } else { 99999 } } | Select-Object -First 1; if ($a) { $a.ifIndex } }
function Strip-If($a) { ($a -replace '--wf-iface=\S+\s*', '').Trim() }
$Host.UI.RawUI.WindowTitle = 'Перезапуск обхода блокировок'
$saved = "$(PctDir 'helpers')\zapret-cmd.txt"
$p = Get-CimInstance Win32_Process -Filter "Name='winws.exe'" | Select-Object -First 1
# Строка winws не читается (запущен с правами выше) — сохранённую команду не трогаю
if ($p -and $p.ExecutablePath -and $p.CommandLine) { [IO.File]::WriteAllLines($saved, [string[]]@($p.ExecutablePath, (Strip-If ($p.CommandLine -replace '^\s*"[^"]+"\s*|^\s*\S+\s*', ''))), (New-Object Text.UTF8Encoding $true)) }
$cfg = Get-Content $saved -Encoding UTF8
if (-not $cfg -or -not (Test-Path -LiteralPath $cfg[0])) { Write-Host 'Программа обхода не найдена (её папка переехала?). Запусти её .bat-файл вручную.' -ForegroundColor Red; Read-Host 'Enter — закрыть' | Out-Null; return }
Write-Host "`nПерезапускаю обход блокировок (zapret)..." -ForegroundColor Cyan
Get-Process winws | Stop-Process -Force; Start-Sleep 2
$i = Get-RealIf; $a2 = Strip-If $cfg[1]; if ($i) { $a2 = "--wf-iface=$i " + $a2 }; Start-Process -FilePath $cfg[0] -ArgumentList $a2 -WorkingDirectory (Split-Path $cfg[0]) -WindowStyle Minimized
Start-Sleep 3
if (Get-Process winws) { Write-Host 'Готово: обход работает. Обнови страницу YouTube/Discord.' -ForegroundColor Green } else { Write-Host 'Не запустился. Запусти .bat-файл из папки обхода вручную.' -ForegroundColor Red }
Start-Sleep 4