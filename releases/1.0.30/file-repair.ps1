# «Не открываются файлы или меню»: запускает проверенный модуль Repair-FileOpening (из Igromanoff OS 1.4) в режиме исправления известных причин.
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""; return }
$Host.UI.RawUI.WindowTitle = 'Не открываются файлы или меню'
Write-Host "`nНЕ ОТКРЫВАЮТСЯ ФАЙЛЫ ИЛИ МЕНЮ`n" -ForegroundColor Cyan
Step -Safe
Step -Plan 'Проверяю права и модуль проверки', 'Ищу причину и исправляю известные настройки', 'Показываю итог'
Step 'Проверяю права и модуль проверки'
Write-Host 'Ищу причину (до 1 минуты). Программы и файлы не удаляются.' -ForegroundColor DarkGray
$out = "$(PctDir 'reports')\file-repair-" + (Get-Date -Format 'yyyyMMdd-HHmm')
if (-not (Test-Path -LiteralPath "$(PctDir 'helpers')\repair-file-opening.ps1")) { Step -Fail 'нет модуля проверки' -Do 'Нажми «Позвать помощь».'; Write-Host 'Не нашёл модуль проверки. Нажми «Позвать помощь».' -ForegroundColor Yellow; Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null; return }
Step -Done 'есть права'; Step -Unsafe; Step 'Ищу причину и исправляю известные настройки' -Hint 'До 1 минуты'
& "$(PctDir 'helpers')\repair-file-opening.ps1" -RepairKnownSettings -OutputDirectory $out *>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
Step -Done 'готово'; Step 'Показываю итог'; Step -Done 'отчёт — в папке отчётов'
Write-Host "`nГотово. Отчёт: $out" -ForegroundColor Green
Write-Host 'Если файлы всё ещё не открываются — перезагрузи ноутбук. Не помогло — Помощник → «Позвать помощь».'
Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null
