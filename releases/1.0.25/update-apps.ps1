$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = 'Обновить программы'
$wg = (Get-Command winget.exe).Source
if (-not $wg) { $wg = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe", "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" | Select-Object -Last 1 -ExpandProperty FullName }
if (-not $wg) { Write-Host 'Программа обновления (winget) не найдена.' -ForegroundColor Red; Read-Host 'Enter — закрыть' | Out-Null; return }
function List { & $wg upgrade --source winget --accept-source-agreements 2>&1 | ForEach-Object { "$_".TrimEnd() } | Where-Object { $_ -and $_ -notmatch '[█▒]|^\s*[-\\|/]\s*$' } }
Write-Host "`nПРОВЕРКА ОБНОВЛЕНИЙ (1–2 минуты)...`n" -ForegroundColor Cyan
$l = List
if ($l -match '0x8a15|source reset|Сбой при') {
  Write-Host 'Каталог программ повреждён — чиню...' -ForegroundColor Yellow
  & $wg source reset --force 2>&1 | Out-Null; & $wg source update --name winget 2>&1 | Out-Null; $l = List }
$l | Write-Host
Write-Host "`nВыше — программы, для которых есть новая версия." -ForegroundColor Yellow
Write-Host 'Перед обновлением закрой браузер и программы из списка.'
Write-Host 'Нажмите 1 и Enter — обновить ВСЕ. Просто Enter — закрыть без изменений.'
if ((Read-Host) -eq '1') {
  & $wg upgrade --all --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity
  Write-Host "`nГотово. Если что-то не скачалось — включи Happ и запусти этот ярлык ещё раз" -ForegroundColor Green
  Write-Host '(некоторые сайты производителей недоступны из России).' -ForegroundColor Green
}
Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null