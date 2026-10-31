$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
$Host.UI.RawUI.WindowTitle = 'Очистка мусора'
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
Write-Host "`nОЧИСТКА МУСОРА (только временные файлы — твои файлы не трогаются)`n" -ForegroundColor Cyan
$cut = (Get-Date).AddDays(-1); $total = 0
$dirs = [ordered]@{
  'Временные файлы программ'   = "$env:LOCALAPPDATA\Temp"
  'Временные файлы Windows'    = "$env:windir\Temp"
  'Отчёты о сбоях программ'    = "$env:LOCALAPPDATA\CrashDumps"
  'Отчёты об ошибках Windows'  = "$env:ProgramData\Microsoft\Windows\WER\ReportArchive"
  'Очередь отчётов об ошибках' = "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"
  'Старый кэш Интернета'       = "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"
  'Кэш загрузок обновлений'    = "$env:windir\SoftwareDistribution\Download"
  'Кэш оптимизации доставки'   = "$env:windir\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"
}
Step -Plan (@($dirs.Keys) + 'Смотрю Корзину'); Step -Unsafe
foreach ($k in $dirs.Keys) {
  $d = $dirs[$k]; $freed = 0; Step $k -Hint $(if ($total) { "Освобождено пока {0:N0} МБ" -f ($total/1MB) } else { 'Только файлы старше суток' })
  Get-ChildItem $d -Recurse -Force -File | Where-Object { $_.LastWriteTime -lt $cut } | ForEach-Object { $s = $_.Length; Remove-Item -LiteralPath $_.FullName -Force; if (-not (Test-Path -LiteralPath $_.FullName)) { $freed += $s } }
  Get-ChildItem $d -Recurse -Force -Directory | Sort-Object { $_.FullName.Length } -Descending | Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force) } | Remove-Item -Force
  $total += $freed; Write-Host ("  {0,-28} освобождено {1,7:N0} МБ" -f $k, ($freed/1MB)); Step -Done ("освобождено {0:N0} МБ" -f ($freed/1MB)) }
Write-Host ("`nИТОГО освобождено: {0:N0} МБ" -f ($total/1MB)) -ForegroundColor Green
Step 'Смотрю Корзину' -Hint 'Без твоего слова не очищаю'
$rb = (Get-ChildItem @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object { "$($_.Name)`$Recycle.Bin" }) -Recurse -Force -File | Measure-Object Length -Sum).Sum
if ($rb -gt 50MB) {
  Write-Host ("`nВ Корзине лежит {0:N0} МБ. Это удалённые тобой файлы — их ещё можно вернуть." -f ($rb/1MB)) -ForegroundColor Yellow
  Write-Host 'Очистить Корзину НАВСЕГДА? Напиши слово ОЧИСТИТЬ и нажми Enter. Просто Enter — оставить как есть.'
  if ((Read-Host).Trim() -eq 'ОЧИСТИТЬ') { Clear-RecycleBin -Force; Write-Host 'Корзина очищена.' -ForegroundColor Green; Step -Done 'очищена' } else { Step -Done 'оставил как есть' } }
else { Step -Done ("{0:N0} МБ — очищать не нужно" -f ($rb/1MB)) }
$c = Get-PSDrive C; Write-Host ("`nСвободно на диске C: {0:N1} ГБ" -f ($c.Free/1GB))
Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null