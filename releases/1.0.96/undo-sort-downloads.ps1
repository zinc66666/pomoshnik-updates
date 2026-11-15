$ErrorActionPreference = 'SilentlyContinue'
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
Step -Plan 'Ищу журнал разбора', 'Возвращаю файлы', 'Убираю пустые папки разбора'
Step 'Ищу журнал разбора'
$dl = [Environment]::ExpandEnvironmentVariables((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders').'{374DE290-123F-4565-9164-39C4925E467B}')
if (-not (Test-Path $dl)) { $dl = Join-Path $env:USERPROFILE 'Downloads' }
$log = Join-Path $dl '_разбор-журнал.csv'
if (-not (Test-Path $log)) { Step -Done 'журнала нет — возвращать нечего'; Write-Host 'Журнала разбора нет — возвращать нечего.'; Start-Sleep 5; return }
Step -Done 'нашёл'; Step -Unsafe; Step 'Возвращаю файлы' -Hint 'Из папок разбора на прежние места'
$n = 0; $left = New-Object Collections.Generic.List[string]
# Не вернулся (место занято, файл открыт) — строка остаётся в журнале для повтора; файла уже нет в папке разбора — строка не нужна
Get-Content -LiteralPath $log -Encoding UTF8 | ForEach-Object { $p = $_.Trim('"') -split '";"'; if ($p.Count -eq 2 -and (Test-Path -LiteralPath $p[1])) {
  if (-not (Test-Path -LiteralPath $p[0])) { Move-Item -LiteralPath $p[1] -Destination $p[0] }
  if ((Test-Path -LiteralPath $p[0]) -and -not (Test-Path -LiteralPath $p[1])) { $n++ } else { $left.Add($_) } } }
# Не вернулось — шаг с замечанием: итог в окне не зелёное «Готово»
if ($left.Count) { Step -Warn "вернул $n, не вернулось $($left.Count)" } else { Step -Done "вернул $n" }
if ($left.Count) { [IO.File]::WriteAllLines($log, $left.ToArray(), (New-Object Text.UTF8Encoding $true)) } else { Remove-Item -LiteralPath $log }
Step 'Убираю пустые папки разбора'
Get-ChildItem $dl -Directory | Where-Object { $_.Name -in 'Картинки','Видео','Музыка','Документы','Архивы','Установщики','Прочее' -and -not (Get-ChildItem -LiteralPath $_.FullName -Force) } | Remove-Item
Step -Done 'готово'
Write-Host "Возвращено файлов: $n" -ForegroundColor Green
if ($left.Count) { Write-Host "Не вернулось файлов: $($left.Count). На их месте уже лежит файл с тем же именем, или файл открыт в программе. Они в папках разбора: закрой программы и запусти возврат ещё раз." -ForegroundColor Yellow }
Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null