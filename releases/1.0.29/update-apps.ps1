$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = 'Обновить программы'
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
Step -Plan 'Ищу программу обновления', 'Проверяю обновления', 'Спрашиваю, обновлять ли'
Step 'Ищу программу обновления'
$wg = (Get-Command winget.exe).Source
if (-not $wg) { $wg = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe", "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" | Select-Object -Last 1 -ExpandProperty FullName }
if (-not $wg) { Step -Fail 'не нашёл winget' -Do 'Установи «Установщик приложений» из Microsoft Store.'; Write-Host 'Программа обновления (winget) не найдена.' -ForegroundColor Red; Read-Host 'Enter — закрыть' | Out-Null; return }
function List { & $wg upgrade --source winget --accept-source-agreements 2>&1 | ForEach-Object { "$_".TrimEnd() } | Where-Object { $_ -and $_ -notmatch '[█▒]|^\s*[-\\|/]\s*$' } }
Step -Done 'нашёл winget'
Step 'Проверяю обновления' -Hint 'Жду ответ каталога winget, 1–2 минуты'
Write-Host "`nПРОВЕРКА ОБНОВЛЕНИЙ (1–2 минуты)...`n" -ForegroundColor Cyan
$l = List
if ($l -match '0x8a15|source reset|Сбой при') {
  Step -Warn 'каталог программ повреждён'; Step 'Чиню каталог программ' -Hint 'Сбрасываю и скачиваю заново, до 2 минут'
  Write-Host 'Каталог программ повреждён — чиню...' -ForegroundColor Yellow
  & $wg source reset --force 2>&1 | Out-Null; & $wg source update --name winget 2>&1 | Out-Null; $l = List }
Step -Done 'список готов'
# По строке: Write-Host окна (run.ps1) не берёт конвейер
$l | ForEach-Object { Write-Host $_ }
Write-Host "`nВыше — программы, для которых есть новая версия." -ForegroundColor Yellow
Write-Host 'Перед обновлением закрой браузер и программы из списка.'
# «Напиши д» — окно покажет кнопки Да/Нет («Да» отвечает «д»); «Enter — закрыть» окно приняло бы за конец и не спросило
Write-Host 'Обновить все программы из списка? Напиши д и Enter. Просто Enter — не обновлять.'
Step 'Спрашиваю, обновлять ли' -Hint 'Ответь на вопрос ниже'
if ((Read-Host) -match '^\s*[дДyY1]') { Step -Done 'обновить все'; Step -Unsafe; Step 'Обновляю программы' -Hint 'Не выключай компьютер, это до 20 минут'
  & $wg upgrade --all --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity
  if ($LASTEXITCODE) { Step -Warn 'часть программ могла не обновиться' } else { Step -Done 'готово' }
  Write-Host "`nГотово. Если что-то не скачалось — включи Happ и запусти этот ярлык ещё раз" -ForegroundColor Green
  Write-Host '(некоторые сайты производителей недоступны из России).' -ForegroundColor Green
} else { Step -Done 'не обновлять' }
Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null