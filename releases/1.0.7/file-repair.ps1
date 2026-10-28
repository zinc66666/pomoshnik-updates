# «Не открываются файлы или меню»: запускает проверенный модуль Repair-FileOpening (из Igromanoff OS 1.4) в режиме исправления известных причин.
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""; return }
$Host.UI.RawUI.WindowTitle = 'Не открываются файлы или меню'
Write-Host "`nНЕ ОТКРЫВАЮТСЯ ФАЙЛЫ ИЛИ МЕНЮ`n" -ForegroundColor Cyan
Write-Host 'Ищу причину (до 1 минуты). Программы и файлы не удаляются.' -ForegroundColor DarkGray
$out = "$(PctDir 'reports')\file-repair-" + (Get-Date -Format 'yyyyMMdd-HHmm')
& "$(PctDir 'helpers')\repair-file-opening.ps1" -RepairKnownSettings -OutputDirectory $out *>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
Write-Host "`nГотово. Отчёт: $out" -ForegroundColor Green
Write-Host 'Если файлы всё ещё не открываются — перезагрузи ноутбук. Не помогло — Помощник → «Позвать помощь».'
Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null
