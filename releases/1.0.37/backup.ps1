$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
$Host.UI.RawUI.WindowTitle = 'Резервная копия'
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
Step -Safe; Step -Plan 'Считаю размер твоих папок', 'Ищу, куда копировать', 'Спрашиваю, куда копировать'
Write-Host "`nРЕЗЕРВНАЯ КОПИЯ твоих файлов`n" -ForegroundColor Cyan
$src = [ordered]@{ 'Документы' = [Environment]::GetFolderPath('MyDocuments'); 'Изображения' = [Environment]::GetFolderPath('MyPictures')
  'Видео' = [Environment]::GetFolderPath('MyVideos'); 'Рабочий стол' = [Environment]::GetFolderPath('Desktop') }
$need = 0; Step 'Считаю размер твоих папок' -Hint 'Ничего не копирую'
foreach ($k in $src.Keys) { $s = (Get-ChildItem -LiteralPath $src[$k] -Recurse -File -Force | Measure-Object Length -Sum).Sum; $need += $s; Write-Host ("  {0,-14} {1,7:N1} ГБ   {2}" -f $k, ($s / 1GB), $src[$k]) }
Write-Host ("  {0,-14} {1,7:N1} ГБ" -f 'ВСЕГО', ($need / 1GB)) -ForegroundColor White; Step -Done ("всего {0:N1} ГБ" -f ($need / 1GB))
Write-Host '  («Загрузки» не копируются: там в основном установщики.)' -ForegroundColor DarkGray
$tg = @(); Step 'Ищу, куда копировать' -Hint 'Флешки, внешние диски, Яндекс Диск'
# Внешний диск — по шине (USB, карта памяти). Системный и внутренние (NVMe, SATA) — не копия: сломается ноутбук — пропадут вместе. Шину не узнал — не предлагаю
function Ext($dl) { try { "$((Get-Disk -Number (Get-Partition -DriveLetter $dl.TrimEnd(':') -ErrorAction Stop).DiskNumber -ErrorAction Stop).BusType)" -in 'USB', 'SD', 'MMC', '1394' } catch { $false } }
Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DeviceID -ne $env:SystemDrive -and ($_.DriveType -eq 2 -or ($_.DriveType -eq 3 -and (Ext $_.DeviceID))) } | ForEach-Object {
  $tg += [pscustomobject]@{ Name = "флешка/диск $($_.DeviceID) $($_.VolumeName)"; Root = "$($_.DeviceID)\Копия ноутбука"; Free = $_.FreeSpace } }
# Яндекс Диск: в профиле или в корне любого локального диска
$yd = @("$env:USERPROFILE\YandexDisk", "$env:USERPROFILE\Яндекс.Диск") + @(Get-CimInstance Win32_LogicalDisk | Where-Object DriveType -eq 3 | ForEach-Object { "$($_.DeviceID)\YandexDisk", "$($_.DeviceID)\Яндекс.Диск" }) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ($yd) { $tg += [pscustomobject]@{ Name = 'Яндекс Диск (уйдёт в облако; бесплатно там 5–10 ГБ)'; Root = "$yd\Копия ноутбука"; Free = (Get-PSDrive $yd.Substring(0, 1)).Free } }
if ($tg) { Step -Done "мест: $(@($tg).Count)" } else { Step -Fail 'нет флешки или диска' -Do 'Вставь флешку (от 32 ГБ) и запусти копию ещё раз.' }
if (-not $tg) { Write-Host "`nКуда копировать — не найдено. Вставь флешку (от 32 ГБ) и запусти этот ярлык ещё раз." -ForegroundColor Yellow; Read-Host 'Enter — закрыть' | Out-Null; return }
Write-Host "`nКуда копировать:" -ForegroundColor Cyan
for ($i = 0; $i -lt $tg.Count; $i++) { Write-Host ("  {0}. {1} — свободно {2:N1} ГБ" -f ($i + 1), $tg[$i].Name, ($tg[$i].Free / 1GB)) }
Step 'Спрашиваю, куда копировать' -Hint 'Ответь на вопрос ниже'
$a = Read-Host "`nНомер (просто Enter — 1, буква н — отмена)"
if ($a -match '^[нНnN]') { Step -Done 'отмена'; return }
$t = $tg[$(if ($a -match '^\d+$') { [int]$a - 1 } else { 0 })]; if (-not $t) { Step -Done 'нет такого номера'; return }
Step -Done $t.Root
$have = (Get-ChildItem -LiteralPath $t.Root -Recurse -File -Force | Measure-Object Length -Sum).Sum
if ($need - $have -gt $t.Free) { Step 'Проверяю место'; Step -Fail 'не хватит места' -Do 'Возьми флешку побольше.'; Write-Host ("`nНе хватит места: нужно ещё {0:N1} ГБ, свободно {1:N1} ГБ. Возьми флешку побольше." -f (($need - $have) / 1GB), ($t.Free / 1GB)) -ForegroundColor Red; Read-Host 'Enter — закрыть' | Out-Null; return }
Write-Host "`nКопирую в $($t.Root) — первый раз долго, дальше только новое и изменённое..." -ForegroundColor Cyan
$err = 0; Step -Plan @($src.Keys | ForEach-Object { "Копирую: $_" }); Step -Unsafe
foreach ($k in $src.Keys) { Write-Host "  $k..."; Step "Копирую: $k" -Hint 'Только новое и изменённое. Первый раз — долго'
  robocopy $src[$k] (Join-Path $t.Root $k) /E /XO /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /XF desktop.ini Thumbs.db | Out-Null
  if ($LASTEXITCODE -ge 8) { $err++; Write-Host "    часть файлов не скопировалась (заняты или нет доступа)" -ForegroundColor Yellow; Step -Warn 'часть файлов не скопировалась' } else { Step -Done 'скопировано' } }
$stamp = '{0:yyyy-MM-dd HH:mm} -> {1}' -f (Get-Date), $t.Root
Set-Content -LiteralPath (Join-Path $t.Root '_когда сделана копия.txt') $stamp -Encoding UTF8
New-Item -ItemType Directory -Force (PctDir 'reports') | Out-Null; Set-Content "$(PctDir 'reports')\backup-last.txt" $stamp -Encoding UTF8
Write-Host $(if ($err) { "`nГотово, но с замечаниями ($err). Закрой программы и запусти ещё раз." } else { "`nГотово: копия сделана. Удалённые здесь файлы в копии остаются." }) -ForegroundColor $(if ($err) { 'Yellow' } else { 'Green' })
Write-Host 'Делай копию раз в неделю. Флешку храни отдельно от ноутбука.'
Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null