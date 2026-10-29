$ErrorActionPreference = 'SilentlyContinue'
$dl = [Environment]::ExpandEnvironmentVariables((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders').'{374DE290-123F-4565-9164-39C4925E467B}')
if (-not (Test-Path $dl)) { $dl = Join-Path $env:USERPROFILE 'Downloads' }
$log = Join-Path $dl '_разбор-журнал.csv'
if (-not (Test-Path $log)) { Write-Host 'Журнала разбора нет — возвращать нечего.'; Start-Sleep 5; return }
$n = 0
Get-Content -LiteralPath $log -Encoding UTF8 | ForEach-Object { $p = $_.Trim('"') -split '";"'; if ($p.Count -eq 2 -and (Test-Path -LiteralPath $p[1]) -and -not (Test-Path -LiteralPath $p[0])) { Move-Item -LiteralPath $p[1] -Destination $p[0]; $n++ } }
Remove-Item -LiteralPath $log
Get-ChildItem $dl -Directory | Where-Object { $_.Name -in 'Картинки','Видео','Музыка','Документы','Архивы','Установщики','Прочее' -and -not (Get-ChildItem -LiteralPath $_.FullName -Force) } | Remove-Item
Write-Host "Возвращено файлов: $n" -ForegroundColor Green; Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null