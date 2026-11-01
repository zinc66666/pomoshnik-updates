$ErrorActionPreference = 'SilentlyContinue'
$Host.UI.RawUI.WindowTitle = 'Что занимает место'
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
Step -Safe; Step -Plan 'Смотрю свободное место', 'Считаю размер папок', 'Считаю мусор и Корзину'
Step 'Смотрю свободное место'
Write-Host "`nСВОБОДНОЕ МЕСТО" -ForegroundColor Cyan
$lowC = $false; $nd = 0
Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -gt 0 } | ForEach-Object { $t = $_.Used + $_.Free; $p = $_.Free / $t * 100; $nd++; if ($_.Name -eq 'C' -and $p -lt 15) { $lowC = $true }
  Write-Host ("  {0}:  свободно {1:N1} ГБ из {2:N1} ГБ ({3:N0}%)" -f $_.Name, ($_.Free/1GB), ($t/1GB), $p) -ForegroundColor $(if ($p -lt 15) { 'Red' } else { 'Gray' }) }
if ($lowC) { Step -Warn "дисков: $nd, на C мало места" } else { Step -Done "дисков: $nd, места хватает" }
Write-Host "`nСАМЫЕ БОЛЬШИЕ ПАПКИ (подождите, считаю...)" -ForegroundColor Cyan
# Корзина ($RECYCLE.BIN) — не папка для разбора: её размер ниже, в рекомендациях
# Корни: профиль, затем на каждом несистемном диске — папка с именем пользователя и сам диск
Step 'Считаю размер папок' -Hint 'Ничего не удаляю. Большие диски — до нескольких минут'
$fx = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object { $_.Name.TrimEnd('\') })
$roots = @(@($env:USERPROFILE) + @($fx | Where-Object { $_ -ne $env:SystemDrive } | ForEach-Object { "$_\$env:USERNAME", "$_\" })) | Where-Object { Test-Path $_ } | Select-Object -Unique
$rows = foreach ($r in $roots) { Get-ChildItem -LiteralPath $r -Directory -Force | Where-Object { $_.Attributes -notmatch 'ReparsePoint' -and $_.Name -ne '$RECYCLE.BIN' } | ForEach-Object { $s = (Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Force | Measure-Object Length -Sum).Sum; [pscustomobject]@{ Path = $_.FullName; GB = [math]::Round($s/1GB, 2) } } }
# Совет по папке: что с ней делать и можно ли трогать вручную.
function Tip($p) {
  if ($p -match 'Download|Загрузк') { return 'Yellow', 'разбери (ярлык 4) и удали старые установщики из папки «Установщики»' }
  if ($p -match 'Steam|steamapps|Games|Игры|ИГРЫ|Epic|Riot|Tanki|Tanks') { return 'Yellow', 'игры: удали те, в которые не играешь, — через Steam/лаунчер, не вручную' }
  if ($p -match 'Video|Видео|ВИДЕО|OBS|Captures') { return 'Yellow', 'видео: старые записи перенеси на флешку/облако или удали ненужные' }
  if ($p -match '^C:.*(Desktop|Рабочий)') { return 'White', 'рабочий стол на диске C: большие файлы лучше хранить на диске D' }
  if ($p -match 'Pictures|Изображ|Documents|Докум|Music|Музык') { return 'White', 'твои файлы: удаляй только то, что точно не нужно' }
  if ($p -match 'AppData|ProgramData|Program Files|Windows|\$') { return 'DarkGray', 'НЕ удалять вручную — служебные файлы программ (мусор чистит ярлык 9)' }
  return 'Gray', '' }
$rows = @($rows); Step -Done "папок: $($rows.Count)"
$rows | Sort-Object GB -Descending | Select-Object -First 15 | ForEach-Object { $t = Tip $_.Path
  Write-Host ("  {0,7:N2} ГБ  {1,-34} {2}" -f $_.GB, $_.Path, $(if ($_.GB -ge 1 -and $t[1]) { '— ' + $t[1] } else { '' })) -ForegroundColor $(if ($_.GB -ge 1) { $t[0] } else { 'Gray' }) }
Step 'Считаю мусор и Корзину' -Hint 'Ничего не удаляю'
Write-Host "`nРЕКОМЕНДАЦИИ" -ForegroundColor Cyan
$junk = (Get-ChildItem "$env:LOCALAPPDATA\Temp", "$env:windir\Temp", "$env:LOCALAPPDATA\CrashDumps", "$env:LOCALAPPDATA\Microsoft\Windows\INetCache" -Recurse -Force -File | Measure-Object Length -Sum).Sum
if ($junk -gt 200MB) { Write-Host ("  - Временного мусора {0:N0} МБ — нажми «9. Очистка мусора»." -f ($junk/1MB)) -ForegroundColor Yellow } else { Write-Host ("  - Мусора мало ({0:N0} МБ) — чистить нечего." -f ($junk/1MB)) -ForegroundColor Green }
$rb = (Get-ChildItem @($fx | ForEach-Object { "$_\`$Recycle.Bin" }) -Recurse -Force -File | Measure-Object Length -Sum).Sum
Step -Done ("мусор {0:N0} МБ, Корзина {1:N1} ГБ" -f ($junk/1MB), ($rb/1GB))
if ($rb -gt 500MB) { Write-Host ("  - В Корзине {0:N1} ГБ. Если ничего оттуда не нужно — очисти (ярлык 9 спросит)." -f ($rb/1GB)) -ForegroundColor Yellow }
if ($lowC) { Write-Host '  - На диске C мало места: перенеси фото, видео и игры на диск D.' -ForegroundColor Red } else { Write-Host '  - Места на диске C достаточно.' -ForegroundColor Green }
Write-Host '  - Не рекомендуется: удалять что-то из Windows, Program Files и AppData вручную и ставить «чистилки» вроде CCleaner.' -ForegroundColor DarkGray
Write-Host "`nНичего не удалено — это только список и советы. Нажмите Enter, чтобы закрыть."; Read-Host | Out-Null