$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
$Host.UI.RawUI.WindowTitle = 'Резервная копия'
Write-Host "`nРЕЗЕРВНАЯ КОПИЯ твоих файлов`n" -ForegroundColor Cyan
$src = [ordered]@{ 'Документы' = [Environment]::GetFolderPath('MyDocuments'); 'Изображения' = [Environment]::GetFolderPath('MyPictures')
  'Видео' = [Environment]::GetFolderPath('MyVideos'); 'Рабочий стол' = [Environment]::GetFolderPath('Desktop') }
$need = 0
foreach ($k in $src.Keys) { $s = (Get-ChildItem -LiteralPath $src[$k] -Recurse -File -Force | Measure-Object Length -Sum).Sum; $need += $s; Write-Host ("  {0,-14} {1,7:N1} ГБ   {2}" -f $k, ($s / 1GB), $src[$k]) }
Write-Host ("  {0,-14} {1,7:N1} ГБ" -f 'ВСЕГО', ($need / 1GB)) -ForegroundColor White
Write-Host '  («Загрузки» не копируются: там в основном установщики.)' -ForegroundColor DarkGray
$tg = @()
Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 -or ($_.DriveType -eq 3 -and $_.DeviceID -notin 'C:', 'D:') } | ForEach-Object {
  $tg += [pscustomobject]@{ Name = "флешка/диск $($_.DeviceID) $($_.VolumeName)"; Root = "$($_.DeviceID)\Копия ноутбука"; Free = $_.FreeSpace } }
$yd = @("$env:USERPROFILE\YandexDisk", 'D:\YandexDisk', "$env:USERPROFILE\Яндекс.Диск") | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($yd) { $tg += [pscustomobject]@{ Name = 'Яндекс Диск (уйдёт в облако; бесплатно там 5–10 ГБ)'; Root = "$yd\Копия ноутбука"; Free = (Get-PSDrive $yd.Substring(0, 1)).Free } }
if (-not $tg) { Write-Host "`nКуда копировать — не найдено. Вставь флешку (от 32 ГБ) и запусти этот ярлык ещё раз." -ForegroundColor Yellow; Read-Host 'Enter — закрыть' | Out-Null; return }
Write-Host "`nКуда копировать:" -ForegroundColor Cyan
for ($i = 0; $i -lt $tg.Count; $i++) { Write-Host ("  {0}. {1} — свободно {2:N1} ГБ" -f ($i + 1), $tg[$i].Name, ($tg[$i].Free / 1GB)) }
$a = Read-Host "`nНомер (просто Enter — 1, буква н — отмена)"
if ($a -match '^[нНnN]') { return }
$t = $tg[$(if ($a -match '^\d+$') { [int]$a - 1 } else { 0 })]; if (-not $t) { return }
$have = (Get-ChildItem -LiteralPath $t.Root -Recurse -File -Force | Measure-Object Length -Sum).Sum
if ($need - $have -gt $t.Free) { Write-Host ("`nНе хватит места: нужно ещё {0:N1} ГБ, свободно {1:N1} ГБ. Возьми флешку побольше." -f (($need - $have) / 1GB), ($t.Free / 1GB)) -ForegroundColor Red; Read-Host 'Enter — закрыть' | Out-Null; return }
Write-Host "`nКопирую в $($t.Root) — первый раз долго, дальше только новое и изменённое..." -ForegroundColor Cyan
$err = 0
foreach ($k in $src.Keys) { Write-Host "  $k..."
  robocopy $src[$k] (Join-Path $t.Root $k) /E /XO /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /XF desktop.ini Thumbs.db | Out-Null
  if ($LASTEXITCODE -ge 8) { $err++; Write-Host "    часть файлов не скопировалась (заняты или нет доступа)" -ForegroundColor Yellow } }
$stamp = '{0:yyyy-MM-dd HH:mm} -> {1}' -f (Get-Date), $t.Root
Set-Content -LiteralPath (Join-Path $t.Root '_когда сделана копия.txt') $stamp -Encoding UTF8
New-Item -ItemType Directory -Force (PctDir 'reports') | Out-Null; Set-Content "$(PctDir 'reports')\backup-last.txt" $stamp -Encoding UTF8
Write-Host $(if ($err) { "`nГотово, но с замечаниями ($err). Закрой программы и запусти ещё раз." } else { "`nГотово: копия сделана. Удалённые здесь файлы в копии остаются." }) -ForegroundColor $(if ($err) { 'Yellow' } else { 'Green' })
Write-Host 'Делай копию раз в неделю. Флешку храни отдельно от ноутбука.'
Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null