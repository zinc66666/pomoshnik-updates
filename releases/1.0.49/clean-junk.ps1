$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
. "$PSScriptRoot\pct-wiper.ps1"
$Host.UI.RawUI.WindowTitle = 'Очистка мусора'
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
Write-Host "`nОЧИСТКА МУСОРА (только временные файлы — твои файлы не трогаются)`n" -ForegroundColor Cyan
$cut = (Get-Date).AddDays(-1).ToFileTimeUtc(); $total = [long]0; $Elevated = PctElevated
# Для pct-wiper.ps1: журнала-файла нет, причины — строками в подробностях
function Jr($t) { Write-Host "  $t" -ForegroundColor DarkGray }
# Корни не из окружения (с повышением оно от её процессов): Windows и ProgramData — от системы, профиль — по SID из HKLM; профиль не нашёл — его группы пропускаю
$w = [Environment]::GetFolderPath('Windows'); $pd = [Environment]::GetFolderPath('CommonApplicationData'); $h = PctHome; $la = $(if ($h) { "$h\AppData\Local" })
$dirs = [ordered]@{
  'Временные файлы программ'   = $(if ($la) { "$la\Temp" })
  'Временные файлы Windows'    = "$w\Temp"
  'Отчёты о сбоях программ'    = $(if ($la) { "$la\CrashDumps" })
  'Отчёты об ошибках Windows'  = "$pd\Microsoft\Windows\WER\ReportArchive"
  'Очередь отчётов об ошибках' = "$pd\Microsoft\Windows\WER\ReportQueue"
  'Старый кэш Интернета'       = $(if ($la) { "$la\Microsoft\Windows\INetCache" })
  'Кэш загрузок обновлений'    = "$w\SoftwareDistribution\Download"
  'Кэш оптимизации доставки'   = "$w\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"
}
# PCT_CLEAN_FAKE=<папка> — корни внутри неё (C:\x → <папка>\C\x): проверка без настоящих папок (с повышением при UAC подмену снимает pct-core). PCT_CLEAN_RACE=<папка>|<приманка> — стенд: подмена папки посреди обхода
$Fake = "$env:PCT_CLEAN_FAKE".TrimEnd('\'); if ($Fake) { foreach ($k in @($dirs.Keys)) { $d = $dirs[$k]; if ($d) { $dirs[$k] = "$Fake\$($d.Substring(0, 1))$($d.Substring(2))" } } }
# Корень не годится: пути нет или он сам либо его родитель — точка соединения или ссылка (удаление ушло бы в чужую папку). Пусто — годится
function Bad($d) { if (-not $d) { return 'не нашёл папку профиля' }
  for ($x = Get-Item -LiteralPath $d -Force; $x; $x = $x.Parent) { if ($x.Attributes -band [IO.FileAttributes]::ReparsePoint) { return "ссылка на другую папку: $($x.FullName)" } } }
# Одна уборка за раз, замок общий с big-clean: две рядом удаляют один файл и обе считают его в «освобождено». На Корзину замок не держу: там вопрос без срока. На стенде у каждого дерева свой замок, настоящие уборки и тесты рядом не мешают
$lk = PctLock $(if ($Fake) { "clean-$($Fake -replace '\W', '-')" } else { 'clean' })
if (-not $lk) { Step -Safe; Step 'Проверяю, не идёт ли уборка'; Step -Fail 'уборка уже идёт' -Do 'Дождись, пока она закончится.'; Write-Host 'Уборка уже идёт. Дождись, пока она закончится.' -ForegroundColor Yellow; Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null; return }
Step -Plan (@($dirs.Keys) + 'Смотрю Корзину'); Step -Unsafe
try { foreach ($k in $dirs.Keys) {
  $d = $dirs[$k]; $freed = 0; Step $k -Hint $(if ($total) { "Освобождено пока {0:N0} МБ" -f ($total/1MB) } else { 'Только файлы старше суток' })
  $why = Bad $d; if ($why) { Write-Host ("  {0,-28} пропускаю: {1}" -f $k, $why) -ForegroundColor Yellow; Step -Warn "пропустил: $why"; continue }
  # По дескрипторам (pct-wiper.ps1): подмена папки ссылкой посреди обхода не уводит. Файлы и пустые папки старше суток; запретные имена — те же, что у «Большой уборки»
  try { WipeInit; [PctWipe]::Run($d, $keepName, $cut, $null, (RaceHook)) } catch { Jr "не убрал ${d}: $($_.Exception.Message)"; Write-Host ("  {0,-28} не получилось убрать" -f $k) -ForegroundColor Yellow; Step -Warn 'не получилось убрать: причина в подробностях'; continue }
  foreach ($l in [PctWipe]::Log) { Jr $l }; $freed = [PctWipe]::Freed; $total += $freed; $t = "освобождено {0:N0} МБ" -f ($freed/1MB)
  # Занятое и несбывшееся — в шаге, не только в подробностях: иначе «освобождено 0 МБ» выглядит как «всё чисто»
  $n = @(if ([PctWipe]::Busy) { "занято файлов: $([PctWipe]::Busy), их не тронул" }) + @(if (@([PctWipe]::Log | Where-Object { $_ -notlike 'не тронул:*' }).Count) { 'часть не убрал: причина в подробностях' })
  Write-Host ("  {0,-28} освобождено {1,7:N0} МБ{2}" -f $k, ($freed/1MB), $(if ($n) { ", $($n -join ', ')" })); if ($n) { Step -Warn "$t, $($n -join ', ')" } else { Step -Done $t } } } finally { PctUnlock $lk }
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