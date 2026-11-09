# «Большая уборка», часть A: смотрю мусор по группам, спрашиваю про каждую, убираю выбранное, показываю место до и после.
# -Scan — только смотрю, ничего не удаляю. PCT_CLEAN_FAKE=<папка> — все корни групп внутри неё (C:\x → <папка>\C\x): проверка удаления без настоящих дисков.
# CLEAN-UI, для окна: -Scan -Json <файл> — подсчёт по карточкам (файл обновляется после каждой, без прав и без окна Windows). -Only <ключи> (или -Arg от run.ps1) — убрать только эти карточки, без вопросов; web, chat, gpu — все их карточки.
# Её папки — от её учётной записи, системные группы — вторым процессом с повышением (-Elevated -Result <имя>): одно окно Windows на нажатие. Удаление здесь — по дескрипторам (PctWipe, pct-wiper.ps1): подмена папки ссылкой посреди уборки не уводит.
# Без ключей — меню запасного окна: подсчёт и вопросы без прав, выбранное убирает Sweep, тот же код, что у -Only. -AnyAge — второму процессу меню: временные файлы любого возраста, как и в подсчёте меню.
# PCT_CLEAN_APPX=<файл> — стенд: список установленных пакетов; PCT_CLEAN_PROCS=<имена через запятую> — стенд: какие программы открыты; PCT_CLEAN_UAC=deny — стенд: в окне Windows выбрано «Нет», child — второй процесс без окна Windows; PCT_CLEAN_RACE=<папка>|<приманка> — стенд: подмена папки посреди обхода; PCT_CLEAN_DENY=<пути через |> — стенд: к этим путям нет доступа.
param([switch]$Scan, [string]$Json, [string]$Only, [string]$Arg, [switch]$Elevated, [string]$Result, [switch]$AnyAge)
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
. "$PSScriptRoot\pct-wiper.ps1"
$Host.UI.RawUI.WindowTitle = 'Большая уборка'
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
$ru = [Globalization.CultureInfo]'ru-RU'
function Sz([double]$b) { if ($b -ge 1GB) { ($b / 1GB).ToString('0.0', $ru) + ' ГБ' } elseif ($b -ge 1MB) { [math]::Round($b / 1MB).ToString($ru) + ' МБ' } elseif ($b -gt 0) { 'меньше 1 МБ' } else { '0 МБ' } }
function Jr($t) { try { $d = PctDir 'reports'; [void][IO.Directory]::CreateDirectory($d); [IO.File]::AppendAllText("$d\big-clean.log", "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $t`n", (New-Object Text.UTF8Encoding $false)) } catch {} }
function Enter { Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null }
$Fake = "$env:PCT_CLEAN_FAKE".TrimEnd('\')
# Короткое имя (YURII~1) → длинное: иначе сверка с запретными папками не сработает
function Long($p) { $p = "$p".TrimEnd('\'); if ($p -notmatch '~') { return $p }
  try { $s = $p.Split('\'); $c = $s[0] + '\'; for ($i = 1; $i -lt $s.Count; $i++) { $m = @(([IO.DirectoryInfo]$c).GetFileSystemInfos($s[$i])); $c = Join-Path $c $(if ($m.Count -eq 1) { $m[0].Name } else { $s[$i] }) }; $c } catch { $p } }
function Map($p) { $p = Long $p; if ($Fake) { "$Fake\$($p.Substring(0, 1))$($p.Substring(2))" } else { $p } }
function Drv($p) { $(if ($Fake) { $p.Substring($Fake.Length + 1, 1) } else { $p.Substring(0, 1) }).ToUpper() }

# Никогда не трогать: Документы, Рабочий стол, Загрузки, Happ, Помощник; в поддельном режиме — и их копии в поддельном дереве
$dl = "$((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders').'{374DE290-123F-4565-9164-39C4925E467B}')"
$dl = $(if ($dl) { [Environment]::ExpandEnvironmentVariables($dl) } else { "$env:USERPROFILE\Downloads" })
$keep = @(); foreach ($k in @([Environment]::GetFolderPath('MyDocuments'), [Environment]::GetFolderPath('Desktop'), $dl, 'D:\Happ', (PctRoot), "$env:LOCALAPPDATA\Pomoshnik")) { if ($k -match '^[A-Za-z]:\\') { $keep += (Long $k); if ($Fake) { $keep += (Map $k) } } }
function Under($a, $b) { $a -eq $b -or $a.StartsWith("$b\", 'OrdinalIgnoreCase') }
# Корень группы годится: глубже диска, вне запретных папок и не их родитель, не ссылка, в поддельном режиме — внутри поддельного дерева
function Allowed($p) { if ($p -notmatch '^[A-Za-z]:\\[^\\]+\\') { return $false }; if ($Fake -and -not (Under $p $Fake)) { return $false }
  foreach ($k in $keep) { if ((Under $p $k) -or (Under $k $p)) { return $false } }; if ((Split-Path $p -Leaf) -match $keepName) { return $false }
  $i = [IO.DirectoryInfo]$p; if ($i.Exists -and ($i.Attributes -band 1024)) { return $false }; $true }

# ---------- Группы и их корни (только эти пути) ----------
$Grp = [ordered]@{
  temp = @{ N = 'Временные файлы'; U = 'Убираю временные файлы'; What = 'Это остатки, которые программы бросили после работы.'; After = 'После удаления ничего не изменится: программам они больше не нужны.'; Rec = 'Рекомендую.'; Q = 'Удалить временные файлы?' }
  bin  = @{ N = 'Корзина'; U = 'Очищаю Корзину'; What = 'Это файлы, которые уже удалены, но пока лежат в Корзине.'; After = 'После очистки вернуть их будет нельзя.'; Rec = 'По ситуации: сначала загляни в Корзину, нет ли там нужного.'; Q = 'Очистить Корзину?' }
  web  = @{ N = 'Кэш браузеров'; U = 'Убираю кэш браузеров'; What = 'Это копии картинок и страниц, чтобы сайты открывались быстрее. Пароли, вход на сайты, история и вкладки останутся.'; After = 'После удаления сайты один раз откроются чуть дольше.'; Rec = 'Рекомендую, если мало места.'; Q = 'Удалить кэш браузеров?'; Small = 1 }
  chat = @{ N = 'Кэш Discord и Telegram'; U = 'Убираю кэш Discord и Telegram'; What = 'Это картинки и видео из чатов, сохранённые на ноутбуке. Вход и переписка останутся.'; After = 'После удаления старые картинки в чатах загрузятся заново.'; Rec = 'Рекомендую, если мало места.'; Q = 'Удалить кэш Discord и Telegram?'; Small = 1 }
  gpu  = @{ N = 'Кэш видеокарты'; U = 'Убираю кэш видеокарты'; What = 'Это заготовки, чтобы игры и видео запускались быстрее.'; After = 'После удаления игры первый раз запустятся дольше и пару минут могут подтормаживать.'; Rec = 'По ситуации: удаляй, если игры начали глючить.'; Q = 'Удалить кэш видеокарты?'; Small = 1 }
  upd  = @{ N = 'Загрузки обновлений Windows'; U = 'Убираю загрузки обновлений'; What = 'Это уже скачанные обновления и копии, которыми Windows делится с другими компьютерами.'; After = 'После удаления Windows сама скачает заново то, что понадобится.'; Rec = 'Рекомендую.'; Q = 'Удалить загрузки обновлений?' }
  dump = @{ N = 'Отчёты о сбоях'; U = 'Убираю отчёты о сбоях'; What = 'Это записи о том, как падали программы и Windows.'; After = 'После удаления по ним уже не разобрать старые сбои.'; Rec = 'По ситуации: если ноутбук недавно сам перезагружался, оставь их и позови помощь.'; Q = 'Удалить отчёты о сбоях?'; Small = 1 } }
# Строка чека «что сделал» по группе
$Did = @{ temp = 'Убрал временные файлы'; bin = 'Очистил Корзину'; web = 'Убрал кэш браузеров — вход и пароли на месте'; chat = 'Убрал кэш Discord и Telegram — вход и переписка на месте'; gpu = 'Убрал кэш видеокарты — игры первый раз запустятся дольше'; upd = 'Убрал загрузки обновлений Windows'; dump = 'Убрал отчёты о сбоях' }
# Карточки окна (CLEAN-UI): раздел, риск, короткая строка, что это, что изменится, совет, шаг, строка чека. Порядок — порядок на экране
function Web($n) { @{ N = "Кэш $n"; S = 'web'; R = 'low'; D = 'Пароли, вход на сайты и вкладки останутся'; What = 'Это копии картинок и страниц, чтобы сайты открывались быстрее.'; After = 'Сайты один раз откроются чуть дольше. Пароли, вход на сайты, история и вкладки останутся.'; Rec = 'Убрать, если мало места.'; U = "Убираю кэш $n"; Did = "Убрал кэш $n — вход и пароли на месте" } }
function Gpu($n) { @{ N = "Кэш $n"; S = 'gpu'; R = 'mid'; D = 'Игры первый раз запустятся дольше'; What = 'Это заготовки, чтобы игры и видео запускались быстрее.'; After = 'Игры первый раз запустятся дольше и пару минут могут подтормаживать.'; Rec = 'По ситуации: убирай, если игры начали глючить.'; U = "Убираю кэш $n"; Did = "Убрал кэш $n — игры первый раз запустятся дольше" } }
function Chat($n) { @{ N = "Кэш $n"; S = 'web'; R = 'low'; D = 'Вход и переписка останутся'; What = 'Это картинки и видео из чатов, сохранённые на компьютере.'; After = 'Старые картинки в чатах загрузятся заново. Вход и переписка останутся.'; Rec = 'Убрать, если мало места.'; U = "Убираю кэш $n"; Did = "Убрал кэш $n — вход и переписка на месте" } }
$Card = [ordered]@{
  temp = @{ N = 'Временные файлы'; S = 'win'; R = 'low'; D = 'Остатки, которые программы бросили после работы'; What = 'Это остатки, которые программы бросили после работы.'; After = 'Ничего: программам эти файлы больше не нужны. Беру только файлы старше 7 дней.'; Rec = 'Убрать. Это самая безопасная часть уборки.'; U = 'Убираю временные файлы'; Did = 'Убрал временные файлы' }
  thumb = @{ N = 'Кэш эскизов'; S = 'win'; R = 'low'; D = 'Маленькие картинки файлов в Проводнике'; What = 'Это маленькие картинки файлов, чтобы папки открывались быстрее.'; After = 'Папки с картинками первый раз откроются чуть дольше: Windows соберёт эскизы заново.'; Rec = 'Убрать, если мало места.'; U = 'Убираю кэш эскизов'; Did = 'Убрал кэш эскизов' }
  upd = @{ N = 'Загрузки обновлений Windows'; S = 'win'; R = 'low'; D = 'Скачанные обновления и копии для других компьютеров'; What = $Grp.upd.What; After = 'Windows сама скачает заново то, что понадобится.'; Rec = 'Убрать.'; U = 'Убираю загрузки обновлений'; Did = 'Убрал загрузки обновлений Windows' }
  dump = @{ N = 'Отчёты о сбоях'; S = 'win'; R = 'low'; D = 'Записи о том, как падали программы'; What = $Grp.dump.What; After = 'По ним уже не разобрать старые сбои.'; Rec = 'Убрать. Если компьютер недавно сам перезагружался, сначала позови помощь.'; U = 'Убираю отчёты о сбоях'; Did = 'Убрал отчёты о сбоях' }
  logs = @{ N = 'Журналы Windows'; S = 'win'; R = 'low'; D = 'Журналы установок старше 7 дней'; What = 'Это записи о том, как ставились обновления и сама Windows.'; After = 'Работа Windows не изменится. Места обычно немного.'; Rec = 'По желанию: места освободится немного.'; U = 'Убираю журналы Windows'; Did = 'Убрал журналы установок старше 7 дней' }
  bin = @{ N = 'Корзина'; S = 'win'; R = 'mid'; D = 'Удалённые файлы, которые ещё можно вернуть'; What = 'Это файлы, которые уже удалены, но пока лежат в Корзине.'; After = 'Вернуть их будет нельзя.'; Rec = 'По ситуации: сначала загляни в Корзину, нет ли там нужного.'; U = 'Очищаю Корзину'; Did = 'Очистил Корзину' }
  left = @{ N = 'Остатки удалённых приложений'; S = 'win'; R = 'mid'; D = 'Папки приложений, которых больше нет'; What = 'Это настройки и файлы приложений из Microsoft Store, которые уже удалены.'; After = 'Если поставишь такое приложение снова, оно начнёт с чистого листа.'; Rec = 'По ситуации: открой список и сними то, что хочешь оставить.'; U = 'Убираю остатки приложений'; Did = 'Убрал остатки удалённых приложений' }
  'web-chrome' = (Web 'Chrome'); 'web-edge' = (Web 'Edge'); 'web-yandex' = (Web 'Яндекс Браузера'); 'web-opera' = (Web 'Opera'); 'web-brave' = (Web 'Brave'); 'web-vivaldi' = (Web 'Vivaldi'); 'web-firefox' = (Web 'Firefox')
  'chat-discord' = (Chat 'Discord'); 'chat-telegram' = (Chat 'Telegram'); 'gpu-dx' = (Gpu 'DirectX'); 'gpu-nv' = (Gpu 'NVIDIA'); 'gpu-amd' = (Gpu 'AMD'); 'gpu-intel' = (Gpu 'Intel') }
$items = New-Object Collections.ArrayList; $seen = @{}
# Корень: группа, подпись источника, путь, процесс (открыт — пропускаю), имя программы для подсказки, карточка окна (нет — как группа). Sys — папка системы, её убирает только процесс с повышением
# Отказ в доступе — не «папки нет»: Test-Path в обоих случаях даёт false. Родитель закрыт — есть ли там папка, не узнать без прав
function Denied($m) { if ($Fake -and -not $Elevated -and "$env:PCT_CLEAN_DENY") { foreach ($x in "$env:PCT_CLEAN_DENY" -split '\|') { if ($x -and (Under $m $x.TrimEnd('\'))) { return $true } } }
  try { [void][IO.File]::GetAttributes($m); $false } catch [UnauthorizedAccessException] { $true } catch { $false } }
function Add($g, $l, $p, $proc = '', $app = '', $c = '') { if ("$p" -notmatch '^[A-Za-z]:\\') { return }; $m = Map $p; if ($seen.ContainsKey($m)) { return }; $seen[$m] = 1
  $no = Denied $m; if (-not $no -and -not (Test-Path -LiteralPath $m)) { return }; if (-not (Allowed $m)) { Jr "отказ: путь вне разрешённых корней или рядом с запретной папкой: $m"; return }
  [void]$items.Add([pscustomobject]@{ G = $g; C = $(if ($c) { $c } else { $g }); L = $l; P = $m; O = $p; Proc = $proc; App = $app; B = [long]0; F = 0; Skip = $false; Sys = ((Under $m (Map $wd)) -or (Under $m (Map $pd))); Age = 0; Pat = ''; Known = (-not $no) }) }
# Профили браузера на основе Chromium: папка с Preferences; чищу только Cache, Code Cache, GPUCache и кэш шейдеров браузера
function Chromium($l, $base, $proc, $app, $local = '', $k = '') { $b = Map $base; if (-not (Test-Path -LiteralPath $b)) { return }
  foreach ($c in @('ShaderCache', 'GrShaderCache', 'GraphiteDawnCache')) { Add 'web' $l "$base\$c" $proc $app $k }
  $pr = @($base) + @(Get-ChildItem -LiteralPath $b -Directory -Force | Where-Object { Test-Path -LiteralPath "$($_.FullName)\Preferences" } | ForEach-Object { "$base\$($_.Name)" })
  foreach ($p in $pr) { foreach ($c in @('Cache', 'Code Cache', 'GPUCache')) { Add 'web' $l "$p\$c" $proc $app $k } }
  if ($local) { Add 'web' $l "$local\Cache" $proc $app $k } }
# Корни не из окружения (с повышением оно от её процессов): Windows и ProgramData — от системы, профиль — по SID из HKLM; профиль не нашёл — корни профиля пусты, Add их не берёт
$h = PctHome; $la = $(if ($h) { "$h\AppData\Local" }); $ra = $(if ($h) { "$h\AppData\Roaming" }); $low = $(if ($h) { "$h\AppData\LocalLow" }); $tp = $(if ($h) { "$h\AppData\Local\Temp" })
$wd = [Environment]::GetFolderPath('Windows'); $pd = [Environment]::GetFolderPath('CommonApplicationData'); if (-not $h) { Jr 'не нашёл папку профиля: её группы пропускаю' }
Add 'temp' 'временные файлы' $tp; Add 'temp' 'временные файлы' "$wd\Temp"
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$drives = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object { $_.Name.Substring(0, 1) })
foreach ($d in $drives) { Add 'bin' 'Корзина' "${d}:\`$Recycle.Bin\$sid" }
Chromium 'кэш Chrome' "$la\Google\Chrome\User Data" 'chrome' 'Chrome' '' 'web-chrome'
Chromium 'кэш Edge' "$la\Microsoft\Edge\User Data" 'msedge' 'Edge' '' 'web-edge'
Chromium 'кэш Яндекс Браузера' "$la\Yandex\YandexBrowser\User Data" 'browser' 'Яндекс Браузер' '' 'web-yandex'
foreach ($o in @('Opera Stable', 'Opera GX Stable')) { Chromium 'кэш Opera' "$ra\Opera Software\$o" 'opera' 'Opera' "$la\Opera Software\$o" 'web-opera' }
Chromium 'кэш Brave' "$la\BraveSoftware\Brave-Browser\User Data" 'brave' 'Brave' '' 'web-brave'
Chromium 'кэш Vivaldi' "$la\Vivaldi\User Data" 'vivaldi' 'Vivaldi' '' 'web-vivaldi'
foreach ($f in @(Get-ChildItem -LiteralPath (Map "$la\Mozilla\Firefox\Profiles") -Directory -Force)) { Add 'web' 'кэш Firefox' "$la\Mozilla\Firefox\Profiles\$($f.Name)\cache2" 'firefox' 'Firefox' 'web-firefox' }
foreach ($c in @('Cache', 'Code Cache', 'GPUCache')) { Add 'chat' 'кэш Discord' "$ra\discord\$c" 'Discord' 'Discord' 'chat-discord' }
foreach ($u in @(Get-ChildItem -LiteralPath (Map "$ra\Telegram Desktop\tdata") -Directory -Force -Filter 'user_data*')) { foreach ($c in @('cache', 'media_cache')) { Add 'chat' 'кэш Telegram' "$ra\Telegram Desktop\tdata\$($u.Name)\$c" 'Telegram' 'Telegram' 'chat-telegram' } }
foreach ($x in @(@('gpu-dx', "$la\D3DSCache"), @('gpu-nv', "$la\NVIDIA\DXCache"), @('gpu-nv', "$la\NVIDIA\GLCache"), @('gpu-nv', "$low\NVIDIA\PerDriverVersion\DXCache"), @('gpu-nv', "$low\NVIDIA\PerDriverVersion\GLCache"), @('gpu-nv', "$pd\NVIDIA Corporation\NV_Cache"), @('gpu-amd', "$la\AMD\DxCache"), @('gpu-amd', "$la\AMD\DxcCache"), @('gpu-amd', "$la\AMD\GLCache"), @('gpu-amd', "$la\AMD\VkCache"), @('gpu-intel', "$la\Intel\ShaderCache"), @('gpu-intel', "$low\Intel\ShaderCache"))) { Add 'gpu' 'кэш видеокарты' $x[1] '' '' $x[0] }
Add 'upd' 'загрузки обновлений Windows' "$wd\SoftwareDistribution\Download"
Add 'upd' 'копии обновлений для других компьютеров' "$wd\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"
foreach ($p in @("$wd\Minidump", "$wd\MEMORY.DMP", "$wd\LiveKernelReports", "$la\CrashDumps", "$pd\Microsoft\Windows\WER\ReportArchive", "$pd\Microsoft\Windows\WER\ReportQueue", "$la\Microsoft\Windows\WER\ReportArchive", "$la\Microsoft\Windows\WER\ReportQueue")) { Add 'dump' 'отчёты о сбоях' $p }
# Только карточки окна (в вопросах меню их нет). Журналы Защитника и found.* не трогаю: в found.* могут лежать спасённые файлы
Add 'thumb' 'кэш эскизов' "$la\Microsoft\Windows\Explorer"
foreach ($p in @("$wd\Panther", "$wd\Logs\CBS")) { Add 'logs' 'журналы установок' $p }
foreach ($i in $items) { if ($i.G -eq 'thumb') { $i.Pat = '^thumbcache_.*\.db$' }; if ($i.G -eq 'logs' -or ($i.G -eq 'temp' -and ($Json -or $Only -or $Arg) -and -not $AnyAge)) { $i.Age = 7 } }

# Размер дерева: внутрь ссылок (junction, symlink) не захожу
function Size($p) { $b = [long]0; $n = 0; if ([IO.File]::Exists($p)) { return @(([IO.FileInfo]$p).Length, 1) }
  $st = New-Object Collections.Stack; $st.Push([IO.DirectoryInfo]$p)
  while ($st.Count) { $d = $st.Pop(); try { foreach ($e in $d.EnumerateFileSystemInfos()) { if ($e.Attributes -band 1024) { continue }; if ($e -is [IO.DirectoryInfo]) { $st.Push($e) } else { $b += $e.Length; $n++ } } } catch {} }
  @($b, $n) }
# Папку можно посмотреть: у папки, куда можно только класть файлы (Windows\Temp без прав), Size дал бы ложный ноль
function CanList($p) { if ([IO.File]::Exists($p)) { return $true }; try { foreach ($e in ([IO.DirectoryInfo]$p).EnumerateFileSystemInfos()) { break }; $true } catch { $false } }
function Unk($l) { @($l | Where-Object { $_ -and -not $_.Known }).Count }
function Open($proc) { if ($Fake -and $null -ne $env:PCT_CLEAN_PROCS) { return ($proc -and ",$env:PCT_CLEAN_PROCS," -like "*,$proc,*") }; $proc -and (Get-Process -Name $proc) }
function Free { $o = [ordered]@{}; foreach ($d in $drives) { $o[$d] = ([IO.DriveInfo]"${d}:\").AvailableFreeSpace }; $o }
function Sum($list) { $s = [long]0; foreach ($i in $list) { $s += $i.B }; $s }
function ByDrv($list) { $h = [ordered]@{}; foreach ($i in $list) { $k = Drv $i.P; $h[$k] = [long]$h[$k] + $i.B }; $s = @($h.Keys | Where-Object { $h[$_] -ge 1MB } | ForEach-Object { "${_}: $(Sz $h[$_])" })
  if ($s.Count -gt 1) { "$(Sz (Sum $list)) ($($s -join ', '))" } elseif ($s.Count -eq 1) { "$(Sz (Sum $list)) на диске $(@($h.Keys | Where-Object { $h[$_] -ge 1MB })[0])" } else { Sz (Sum $list) } }
# Совет по открытой программе: Discord и Telegram живут у часов после закрытия окна; есть окно — закрыть; нет окна (Edge в фоне) — почищу в другой раз
$script:winC = @{}
function HasWin($proc) { if ($Fake -and $null -ne $env:PCT_CLEAN_PROCS) { return $true }; if (-not $script:winC.ContainsKey($proc)) { $script:winC[$proc] = [bool](Get-Process -Name $proc | Where-Object { $_.MainWindowHandle -ne 0 }) }; $script:winC[$proc] }
function Note($i) { $a = $i.App
  if ($i.G -eq 'chat') { "$a работает у часов. Чтобы почистить его кэш: правой кнопкой по значку у часов → «Выйти», потом запусти уборку ещё раз." }
  elseif (HasWin $i.Proc) { "$a открыт — закрой $a, чтобы почистить его кэш." }
  else { "$a работает в фоне. Его кэш почищу в следующий раз, когда $a будет закрыт." } }
# Коротко — для строки шага (полный совет — в вопросе и журнале)
function Short($i) { $a = $i.App; if ($i.G -eq 'chat') { "$a у часов" } elseif (HasWin $i.Proc) { "$a открыт" } else { "$a в фоне" } }
function StepNote($l) { $u = @($l | Select-Object -ExpandProperty App -Unique); if ($u.Count -eq 1) { Short $l[0] } else { "открыто программ: $($u.Count)" } }
function Notes($l) { $seenA = @{}; (@($l | Where-Object { -not $seenA[$_.App] -and ($seenA[$_.App] = 1) } | ForEach-Object { Note $_ }) -join ' ') }

# ---------- Карточки окна (CLEAN-UI) ----------
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($Arg) { $Only = $Arg }
# web, chat, gpu — все их карточки; неизвестный ключ — в журнал
function Keys($s) { $o = @(); foreach ($x in "$s" -split '[,.\s]+') { if (-not $x) { continue }; if ($x -in 'web', 'chat', 'gpu') { $o += @($Card.Keys | Where-Object { $_ -like "$x-*" }) } elseif ($Card.Contains($x)) { $o += $x } else { Jr "неизвестная карточка: $x" } }; @($o | Select-Object -Unique) }
# Остатки приложений: папки Packages вида имя_издатель без установленного пакета. Списка нет или он подозрительно мал — группы нет; системные папки — никогда
function Left { if (-not $la) { return }; $fam = @{}; try { if ($Fake) { if (-not $env:PCT_CLEAN_APPX) { return }; foreach ($n in [IO.File]::ReadAllLines($env:PCT_CLEAN_APPX)) { $fam[$n.Trim()] = 1 } }
    else { foreach ($x in @(Get-AppxPackage -PackageTypeFilter Main, Framework, Resource, Bundle, Optional, Xap -ErrorAction Stop)) { $fam[$x.PackageFamilyName] = 1 }; if ($fam.Count -lt 5) { Jr "список приложений мал ($($fam.Count)): остатки не ищу"; return } } } catch { Jr "список приложений: $($_.Exception.Message)"; return }
  foreach ($f in @(Get-ChildItem -LiteralPath (Map "$la\Packages") -Directory -Force)) { $n = $f.Name; if ($n -notmatch '^[A-Za-z0-9.\-]+_[a-z0-9]{13}$' -or $n -match '^(?i)(Microsoft\.Windows\.|MicrosoftWindows\.|Windows\.|[0-9a-f]{8}-)' -or $fam.ContainsKey($n)) { continue }; Add 'left' $n "$la\Packages\$n" } }
# Подсчёт одного корня теми же правилами, что и удаление: запретные имена, возраст, маска. Нет прав на сам корень — Known = false («не знаю», не ноль)
function Count($it) { if (-not $it.Known) { return }; $it.B = [long]0; if ([IO.File]::Exists($it.P)) { $it.B = ([IO.FileInfo]$it.P).Length; return }
  $cut = $(if ($it.Age) { (Get-Date).AddDays(-$it.Age) }); $st = New-Object Collections.Stack; $st.Push([IO.DirectoryInfo]$it.P); $top = $true
  while ($st.Count) { $d = $st.Pop(); try { foreach ($e in $d.EnumerateFileSystemInfos()) { if ($e.Name -match $keepName -or ($e.Name -eq 'desktop.ini' -and $d.Name -like 'S-1-5-*') -or ($e.Attributes -band 1024)) { continue }
        if ($e -is [IO.DirectoryInfo]) { if (-not $it.Pat) { $st.Push($e) } } elseif ((-not $it.Pat -or $e.Name -match $it.Pat) -and (-not $cut -or $e.LastWriteTime -lt $cut)) { $it.B += $e.Length } } } catch { if ($top) { $it.Known = $false } }; $top = $false } }
# Файл занят так, что его не удалить: проба правом «удаление», ничего не меняет
function Held($p) { try { $s = New-Object IO.FileStream($p, [IO.FileMode]::Open, [Security.AccessControl.FileSystemRights]::Delete, [IO.FileShare]'ReadWrite, Delete', 4096, [IO.FileOptions]::None); $s.Dispose(); $false } catch [UnauthorizedAccessException] { $false } catch { $true } }
function Hold($k) { @($items | Where-Object { $_.C -eq $k -and $_.Pat } | ForEach-Object { $it = $_; @(Get-ChildItem -LiteralPath $it.P -Force -File | Where-Object { $_.Name -match $it.Pat -and (Held $_.FullName) }) }) }
# Что мешает карточке: программа открыта или живёт в фоне
function Block($k) { $u = @{}; foreach ($i in @($items | Where-Object { $_.C -eq $k -and $_.Proc })) { if ($u.ContainsKey($i.App) -or -not (Open $i.Proc)) { continue }; $u[$i.App] = $(if (HasWin $i.Proc) { "$($i.App) открыт — закрой его, тогда уберу" } elseif ($i.G -eq 'chat') { "$($i.App) работает у часов — выйди из него, тогда уберу" } else { "$($i.App) работает в фоне — уберу, когда он закроется" }) }
  @($u.Keys | ForEach-Object { [ordered]@{ app = $_; text = $u[$_] } }) }
function Label($o) { foreach ($x in @(@($tp, '%TEMP%'), @($low, '%LOCALAPPDATA%Low'), @($la, '%LOCALAPPDATA%'), @($ra, '%APPDATA%'))) { if ($x[0] -and (Under $o $x[0])) { return $x[1] + $o.Substring($x[0].Length) } }; $o }
function CardJ($k, $scan) { $c = $Card[$k]; $li = @($items | Where-Object { $_.C -eq $k }); $kn = @($li | Where-Object { $_.Known }); $b = [long]0; foreach ($i in $kn) { $b += $i.B }
  [ordered]@{ key = $k; name = $c.N; sec = $c.S; risk = $c.R; sub = $c.D; What = $c.What; After = $c.After; Rec = $c.Rec; scanning = [bool]$scan; size = $(if ($li.Count -and -not $kn.Count) { $null } else { $b }); unknown = [bool]@($li | Where-Object { -not $_.Known }).Count; uac = [bool]@($li | Where-Object { $_.Sys }).Count
    block = @(if (-not $scan) { Block $k }); held = @(if (-not $scan) { Hold $k }).Count; dirs =@($li | ForEach-Object { [ordered]@{ path = $_.P; label = (Label $_.O); name = $_.L; size = $(if ($_.Known) { $_.B } else { $null }); uac = [bool]$_.Sys } }) } }
function JsonOut($o, [switch]$Last) { $t = "$Json.$PID.tmp"; $x = New-Object Text.UTF8Encoding $false; $body = $o | ConvertTo-Json -Depth 6 -Compress
  for ($n = 0; $n -lt $(if ($Last) { 20 } else { 1 }); $n++) { try { [IO.File]::WriteAllText($t, $body, $x); if ([IO.File]::Exists($Json)) { [IO.File]::Replace($t, $Json, [NullString]::Value) } else { [IO.File]::Move($t, $Json) }; return } catch { Start-Sleep -Milliseconds 100 } }; Jr "подсчёт: файл не записан: $Json" }
# Подсчёт для окна: карточки сразу (размер — ⟳), затем файл обновляется после каждой. Постоянные карточки Windows есть всегда, остальные — только если есть их корни
function ScanJson { $sw = [Diagnostics.Stopwatch]::StartNew(); $always = 'temp', 'thumb', 'upd', 'dump', 'logs', 'bin'; $done = @{} # готовая карточка не считается заново
  $list = { @($Card.Keys | Where-Object { $k = $_; $k -in $always -or @($items | Where-Object { $_.C -eq $k }).Count }) }
  $state = { param($cur, $end) [ordered]@{ schema = 1; done = [bool]$end; sec = [int]$sw.Elapsed.TotalSeconds; cur = "$cur"; groups = @(& $list | ForEach-Object { if ($done[$_]) { $done[$_] } else { CardJ $_ $true } }) } }
  JsonOut (& $state 'Смотрю, что есть' $false)
  foreach ($k in @(& $list)) { foreach ($i in @($items | Where-Object { $_.C -eq $k })) { Count $i }; $done[$k] = CardJ $k $false; JsonOut (& $state $Card[$k].N $false) }
  Left; foreach ($i in @($items | Where-Object { $_.C -eq 'left' })) { Count $i }; if (@($items | Where-Object { $_.C -eq 'left' }).Count) { $done['left'] = CardJ 'left' $false }
  Jr "посчитал для окна за $($sw.ElapsedMilliseconds) мс"; JsonOut (& $state '' $true) -Last }

# Один корень; итог — в $cf, $cb, $df
function WipeH($it) { if (-not $seen.ContainsKey($it.P) -or -not (Allowed $it.P)) { Jr "отказ: $($it.P)"; return }; $k = $it.C; Write-Host "  убираю: $($it.P)" -ForegroundColor DarkGray
  if (-not $Fake -and $it.L -like 'копии обновлений*' -and (Get-Command Delete-DeliveryOptimizationCache)) { $b0 = (Size $it.P)[0]; Delete-DeliveryOptimizationCache -Force; $b1 = (Size $it.P)[0]; if ($b1) { $cb[$k] = [int]$cb[$k] + 1 }; $x = [math]::Max(0, $b0 - $b1); $cf[$k] = [long]$cf[$k] + $x; $dv = Drv $it.P; $df[$dv] = [long]$df[$dv] + $x; return }
  $cut = [long]0; if ($it.Age) { $cut = (Get-Date).AddDays(-$it.Age).ToFileTimeUtc() }
  try { WipeInit; [PctWipe]::Run($it.P, $keepName, $cut, $it.Pat, (RaceHook)); foreach ($l in [PctWipe]::Log) { Jr $l }; $x = [PctWipe]::Freed; $cf[$k] = [long]$cf[$k] + $x; $cb[$k] = [int]$cb[$k] + [PctWipe]::Busy; $dv = Drv $it.P; $df[$dv] = [long]$df[$dv] + $x }
  catch { Jr "не убрал $($it.P): $($_.Exception.Message)"; $script:wipeBad = $true; $cb[$k] = [int]$cb[$k] + 1 } }
# Карточки ks, часть sys: занятое программой — пропуск с подсказкой; идёт обновление — загрузки обновлений не трогаю
function Part($ks, [bool]$sys) { $upBusy = $(if ($Fake) { [bool]$env:PCT_CLEAN_UPBUSY } else { (Get-Process -Name TiWorker) -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') })
  foreach ($i in @($items | Where-Object { $_.C -in $ks -and $_.Sys -eq $sys })) { if (Open $i.Proc) { [void]$skip.Add($i); continue }; if ($upBusy -and $i.L -eq 'загрузки обновлений Windows') { $script:upSkip = $true; continue }; WipeH $i } }
function Parts($ks, [bool]$sys) { @($ks | Where-Object { $k = $_; @($items | Where-Object { $_.C -eq $k -and $_.Sys -eq $sys }).Count }) }
function Asks($sysK) { [bool]($sysK -and ((-not $admin -and -not $Fake) -or ($Fake -and $env:PCT_CLEAN_UAC -eq 'child'))) }
# Уборка окна и меню: системная часть (ключи sysK) — вторым процессом, одно окно Windows на запуск; своя — здесь, шагами ph (T — подпись, K — карточки). Итог — $cf, $cb, $df, $skip, $notes, $unv вызывающего; чек — $script:rc. xa — добавка к запуску второго процесса
function Sweep($sysK, $tSys, $ph, [bool]$ask, [string[]]$xa = @()) { $script:rc = $null
  if ($sysK) { $ok = $true; $pr = $null
    if ($ask) { Step 'Жду, пока Windows спросит разрешение' -Hint 'Нажми «Да» в окне Windows'; $script:rc = PctReceipt 'big-clean' 'Уборка' @('disk', 'mem'); $id = [guid]::NewGuid().ToString('N'); $res = "$(PctDir 'run')\clean-$id.res"
      $sp = @{ FilePath = "$([Environment]::GetFolderPath('System'))\WindowsPowerShell\v1.0\powershell.exe"; WindowStyle = 'Hidden'; PassThru = $true; ErrorAction = 'Stop'; ArgumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Only', ($sysK -join ','), '-Elevated', '-Result', $id) + $xa }; if (-not $Fake) { $sp.Verb = 'RunAs' }
      try { $pr = Start-Process @sp } catch { $ok = $false; Jr "разрешение Windows: $($_.Exception.Message)" }
      if ($ok) { Step -Done 'разрешение есть' } else { Step -Warn 'разрешения нет' } }
    elseif ($Fake -and $env:PCT_CLEAN_UAC -eq 'deny') { $ok = $false; Jr 'стенд: в окне Windows выбрано «Нет»' }
    if (-not $ok) { [void]$notes.Add('Windows не дал разрешение — системные файлы не тронул.'); foreach ($k in $sysK) { $unv[$k] = 1 } }
    if (-not $script:rc) { $script:rc = PctReceipt 'big-clean' 'Уборка' @('disk', 'mem') }
    Step $tSys -Hint 'Документы, фото и пароли не трогаю'
    if ($ok -and $pr) { $sw = [Diagnostics.Stopwatch]::StartNew(); while (-not $pr.HasExited -and $sw.Elapsed.TotalMinutes -lt 30) { Start-Sleep -Milliseconds 200 }
      $j = $null; try { $j = [IO.File]::ReadAllText($res) | ConvertFrom-Json; [IO.File]::Delete($res) } catch { Jr "итог с повышением не прочитан: $($_.Exception.Message)" }
      if ($j) { foreach ($k in $sysK) { $cf[$k] = [long]$cf[$k] + [long]$j.freed.$k; $cb[$k] = [int]$cb[$k] + [int]$j.busy.$k }; foreach ($p in $j.drv.PSObject.Properties) { $df[$p.Name] = [long]$df[$p.Name] + [long]$p.Value }; if ($j.upSkip) { $script:upSkip = $true }; if ($j.bad) { $script:wipeBad = $true }; foreach ($k in @($j.skip)) { $unv["$k"] = 1 } } else { [void]$notes.Add('Системная часть не ответила: что с ней стало, смотри в журнале.'); foreach ($k in $sysK) { $unv[$k] = 1 } } }
    elseif ($ok) { Jr "системные части здесь же: $($sysK -join ', ')"; Part $sysK $true }
    $t = [long]0; foreach ($k in $sysK) { $t += [long]$cf[$k] }; if ($ok) { Step -Done (Sz $t) } else { Step -Warn 'пропустил' } }
  if (-not $script:rc) { $script:rc = PctReceipt 'big-clean' 'Уборка' @('disk', 'mem') }
  foreach ($c in $ph) { Step $c.T -Hint 'Документы, фото и пароли не трогаю'; $f0 = [long]0; foreach ($k in $c.K) { $f0 += [long]$cf[$k] }; Part $c.K $false; $t = [long]0; $bs = 0; foreach ($k in $c.K) { $t += [long]$cf[$k]; $bs += [int]$cb[$k] }; $t -= $f0
    $sk = @($skip | Where-Object { $_.C -in $c.K }); if ($sk) { Step -Warn "$(Sz $t), $(StepNote $sk)" } elseif ($bs) { Step -Warn "$(Sz $t), занято файлов: $bs" } else { Step -Done (Sz $t) } }
  if ($script:upSkip) { [void]$notes.Add('Windows ставит обновления — загрузки обновлений не тронул.') }; if ($skip.Count) { [void]$notes.Add((Notes @($skip))) }
  if ([int]$cb['thumb']) { [void]$notes.Add('Проводник держит часть кэша эскизов — эти файлы пропустил.') }; if ($script:wipeBad) { [void]$notes.Add('Часть не получилось убрать — подробности в журнале.') } }

# Второй процесс с повышением: только системные части выбранных карточек, итог — новым файлом в run\ (своё имя, поверх ссылки не пишу). Шагов и чека нет — их ведёт первый процесс
if ($Elevated) { if (-not $Only -or $Result -notmatch '^[0-9a-f]{32}$' -or (-not $admin -and -not $Fake)) { return }
  $cf = @{}; $cb = @{}; $df = @{}; $skip = New-Object Collections.ArrayList; $script:upSkip = $false; $script:wipeBad = $false; $ks = @(Keys $Only); Jr "с повышением, системные части: $($ks -join ', ')"; Part $ks $true
  $o = [ordered]@{ freed = $cf; busy = $cb; drv = $df; upSkip = [bool]$script:upSkip; skip = @($skip | ForEach-Object { $_.C }); bad = [bool]$script:wipeBad }
  $fs = [IO.File]::Open("$(PctDir 'run')\clean-$Result.res", [IO.FileMode]::CreateNew, [IO.FileAccess]::Write); try { $b = (New-Object Text.UTF8Encoding $false).GetBytes(($o | ConvertTo-Json -Depth 3 -Compress)); $fs.Write($b, 0, $b.Length) } finally { $fs.Dispose() }; return }
if ($Json) { ScanJson; return }
if ($Only) { $lk = PctLock 'clean'; if (-not $lk) { Step -Safe; Step 'Проверяю, не идёт ли уборка'; Step -Fail 'уборка уже идёт' -Do 'Дождись, пока она закончится.'; return }
  try { Step -Safe; $ks = @(Keys $Only); Jr "убрать: $($ks -join ', ')$(if ($Fake) { ", поддельное дерево $Fake" })"
    if (-not $ks) { Step 'Смотрю, что убрать'; Step -Fail 'нечего убирать' -Do 'Нажми «Пересчитать» и выбери карточку.'; return }
    # Остатки приложений: то, что человек снял в окне, не трогаю (run\clean-skip.txt — имена папок)
    if ($ks -contains 'left') { Left; $sf = "$(PctDir 'run')\clean-skip.txt"; if ([IO.File]::Exists($sf)) { $off = @([IO.File]::ReadAllLines($sf) | ForEach-Object { $_.Trim() }); [IO.File]::Delete($sf); foreach ($i in @($items | Where-Object { $_.C -eq 'left' -and $off -contains $_.L })) { $items.Remove($i); Jr "оставил по выбору: $($i.L)" } } }
    $cf = @{}; $cb = @{}; $df = @{}; $skip = New-Object Collections.ArrayList; $script:upSkip = $false; $script:wipeBad = $false; $notes = New-Object Collections.ArrayList; $unv = @{}
    $sysK = @(Parts $ks $true); $usrK = @(Parts $ks $false); $ask = Asks $sysK
    # Шаги: разрешение Windows, системная часть, её часть по разделам; одна карточка — её подпись
    $name = { param($t) if (@($ks).Count -eq 1) { $Card[$ks[0]].U } else { $t } }
    $ph = @(@(@('win', 'Убираю файлы Windows'), @('web', 'Убираю кэш браузеров и чатов'), @('gpu', 'Убираю кэш видеокарты')) | ForEach-Object { $s = $_; $pk = @($usrK | Where-Object { $Card[$_].S -eq $s[0] }); if ($pk) { [pscustomobject]@{ T = (& $name $s[1]); K = $pk } } })
    $tSys = & $name 'Убираю системные файлы'; if ($sysK -and $usrK -and @($ks).Count -eq 1) { $tSys = "${tSys}: системная часть" }
    Step -Plan (@(if ($ask) { 'Жду, пока Windows спросит разрешение' }) + @(if ($sysK) { $tSys }) + @($ph | ForEach-Object { $_.T }) + @('Сравниваю место до и после'))
    Step -Unsafe; Sweep $sysK $tSys $ph $ask
    # Чек: только через PctReceipt; окну — сколько освободила каждая карточка
    Step 'Сравниваю место до и после'; Start-Sleep -Milliseconds 300; $all = [long]0; foreach ($k in $ks) { $all += [long]$cf[$k]; if ([long]$cf[$k] -gt 0) { PctRcDo $rc $Card[$k].Did (Sz $cf[$k]) } }
    $dk = @($df.Keys | Where-Object { $df[$_] -ge 1MB }); $hd = "Освободил $(Sz $all)$(if ($dk.Count -eq 1) { " на диске $($dk[0]):" })"; if (-not $all) { $hd = 'Убирать почти нечего' }
    $why = 'Вернуть файлы нельзя — они удалены.' + $(if (@($ks | Where-Object { $Card[$_].S -in 'web', 'gpu' }).Count) { ' Кэш программы соберут сами.' } else { '' })
    [void](PctReceiptEnd $rc $hd $null $why ((@($notes | Select-Object -Unique)) -join ' '))
    # Занято 0 — окно считает карточку проверенной. Часть не тронута (нет разрешения, программа открыта, идёт обновление) — проверенной её считать нельзя
    if ($script:upSkip) { $unv['upd'] = 1 }; foreach ($i in $skip) { $unv[$i.C] = 1 }
    if (Test-Path function:Emit) { foreach ($k in $ks) { Emit 'S' 'cleaned' "$k|$([long]$cf[$k])|$([int]$cb[$k] + [int]$unv[$k])" } }
    Step -Done "освобождено $(Sz $all)"; Jr "готово: освобождено $(Sz $all), занято файлов $(($cb.Values | Measure-Object -Sum).Sum)$(if ($notes.Count) { "; $($notes -join ' ')" })"; Write-Host "Освободил $(Sz $all)." -ForegroundColor Green
  } finally { PctUnlock $lk }; return }

Write-Host "`nБОЛЬШАЯ УБОРКА`n" -ForegroundColor Cyan
Step -Safe
$lk = $null; if (-not $Scan) { $lk = PctLock 'clean'; if (-not $lk) { Step 'Проверяю, не идёт ли уборка'; Step -Fail 'уборка уже идёт' -Do 'Дождись, пока она закончится.'; Write-Host 'Уборка уже идёт. Дождись, пока она закончится.' -ForegroundColor Yellow; Enter; return } }
try {
  Jr "начал: $(if ($Scan) { 'только смотрю' } else { 'уборка' })$(if ($Fake) { ", поддельное дерево $Fake" })"
  # Экран хода не прокручивается: шагов не больше 9. Подсчёт — 3 шага; уборка — разрешение, системная часть, своя часть, сравнение; без системной — до 3 частей и сравнение. По каждой группе — строка в подробностях и размер в вопросе
  # Размер группы для вопроса: то, что видно без прав, и честно — что не видно
  function GSz($g) { $u = Unk $g.Go; if ($g.B -lt 1MB -and $u) { 'размер не узнать без разрешения Windows' } else { "$(ByDrv $g.Go)$(if ($u) { ' и ещё папки, размер которых не узнать без разрешения Windows' })" } }
  $ph = @(@('Считаю временные файлы и Корзину', 'Убираю временные файлы и Корзину', 'temp', 'bin'), @('Считаю кэш программ', 'Убираю кэш программ', 'web', 'chat', 'gpu'), @('Считаю обновления и отчёты о сбоях', 'Убираю обновления и отчёты о сбоях', 'upd', 'dump'))
  $wo = Map "$env:SystemDrive\Windows.old"; $wob = 0; $hasWo = Test-Path -LiteralPath $wo
  Step -Plan (@($ph | ForEach-Object { $_[0] }) + @(if ($hasWo) { 'Смотрю старую Windows' }) + @(if (-not $Scan) { 'Спрашиваю, что убрать' }))
  $free0 = Free; $sw = [Diagnostics.Stopwatch]::StartNew()
  # ---------- Смотрю ----------
  foreach ($p in $ph) { Step $p[0] -Hint 'Ничего не удаляю'; $go = @(); $off = @()
    foreach ($k in $p[2..($p.Count - 1)]) { $g = $Grp[$k]; $li = @($items | Where-Object { $_.G -eq $k })
      foreach ($i in $li) { if ($i.Known -and -not (CanList $i.P)) { $i.Known = $false }; if ($i.Known) { $r = Size $i.P; $i.B = $r[0]; $i.F = $r[1] }; $i.Skip = [bool](Open $i.Proc) }
      $g.Go = @($li | Where-Object { -not $_.Skip }); $g.Off = @($li | Where-Object { $_.Skip -and $_.B -gt 0 }); $g.B = Sum $g.Go; $go += $g.Go; $off += $g.Off
      foreach ($i in $li) { Write-Host "  $($i.P) — $(if ($i.Known) { "$(Sz $i.B), файлов: $($i.F)" } else { 'не посмотреть без разрешения Windows' })$(if ($i.Skip) { " ($(Short $i) — пропущу)" })" -ForegroundColor DarkGray } }
    $t = $(if ((Sum $go) -ge 1MB) { ByDrv $go } elseif (-not (Unk $go)) { 'пусто' }); if (Unk $go) { $t = (@($t) + 'часть папок закрыта' | Where-Object { $_ }) -join ', ' }; if ($off) { Step -Warn "$t, $(StepNote $off)"; Jr "совет: $(Notes $off)" } else { Step -Done $t } }
  if ($hasWo) { Step 'Смотрю старую Windows' -Hint 'Ничего не удаляю, до минуты'; $wob = (Size $wo)[0]; Step -Done "$(Sz $wob), разберём во второй части" }
  $scanMs = $sw.ElapsedMilliseconds; Jr "посмотрел за $scanMs мс"
  $all = [long]0; foreach ($k in $Grp.Keys) { $all += $Grp[$k].B }
  $hid = @($Grp.Keys | Where-Object { Unk $Grp[$_].Go }).Count
  Write-Host ''; Write-Host "Можно убрать: $(Sz $all)$(if ($hid) { ' и ещё папки, размер которых не узнать без разрешения Windows' })" -ForegroundColor White
  foreach ($k in $Grp.Keys) { $g = $Grp[$k]; if ($g.B -ge 1MB -or (Unk $g.Go)) { Write-Host "  $($g.N) — $(GSz $g)" } }
  foreach ($k in $Grp.Keys) { $g = $Grp[$k]; if ($g.Off) { Write-Host "  $(Notes $g.Off)" -ForegroundColor Yellow } }
  if ($wob) { Write-Host "Старая Windows (Windows.old) — $(Sz $wob)." }
  Write-Host 'Старую Windows, большие файлы, программы и одинаковые файлы — это разберём во второй части.' -ForegroundColor DarkGray
  if ($Scan) { Write-Host "`nЯ только посмотрел, ничего не удалял. Смотрел $([math]::Round($scanMs / 1000.0, 1).ToString($ru)) с." -ForegroundColor Green; return }
  # ---------- Спрашиваю ----------
  Step 'Спрашиваю, что убрать' -Hint 'Ответь на вопросы ниже'; $pick = @()
  $ask = @($Grp.Keys | Where-Object { $Grp[$_].B -ge 1MB -or (Unk $Grp[$_].Go) })
  foreach ($k in $ask) { $g = $Grp[$k]; $rec = $(if ($g.Small -and $g.B -lt 50MB -and -not (Unk $g.Go)) { 'Не нужно: места освободится совсем мало.' } else { $g.Rec })
    $off = ''; if ($g.Off) { $off = " $(Notes $g.Off)" }
    Write-Host "$($g.N) — $(GSz $g). $($g.What)$off" -ForegroundColor White; Write-Host "$($g.After) $rec"
    $ans = Read-Host "$($g.Q) (д/н)"; if ("$ans".Trim() -match '^(?i)(д|да|y|yes|l)') { $pick += $k; Jr "выбрано: $($g.N), $(Sz $g.B)" } }
  if (-not $pick) { Step -Done $(if ($ask) { 'ничего не убираю' } else { 'мусора почти нет' }); Write-Host "`n$(if ($ask) { 'Ничего не удалил: ни одна группа не выбрана.' } else { 'Мусора почти нет — убирать нечего.' })" -ForegroundColor Green; return }
  Step -Done "убрать: $($pick.Count) из $($ask.Count)"
  # ---------- Убираю: тем же кодом, что окно (Sweep). Меню выбирает группы, окно — карточки: у web, chat, gpu их несколько, Keys берёт все ----------
  $ks = @(Keys ($pick -join ',')); $cf = @{}; $cb = @{}; $df = @{}; $script:upSkip = $false; $script:wipeBad = $false; $notes = New-Object Collections.ArrayList; $unv = @{}; $script:winC = @{}
  # Занятое программой при подсчёте не трогаю, даже если её уже закрыли: так сказано в вопросе
  $skip = New-Object Collections.ArrayList; foreach ($i in @($items | Where-Object { $_.Skip })) { $items.Remove($i); if ($i.G -in $pick -and $i.B -gt 0) { [void]$skip.Add($i) } }
  $one = @($pick).Count -eq 1; $sysK = @(Parts $ks $true); $usrK = @(Parts $ks $false); $uac = Asks $sysK; $tSys = $(if ($one) { $Grp[$pick[0]].U } else { 'Убираю системные файлы' }); if ($sysK -and $usrK -and $one) { $tSys = "${tSys}: системная часть" }
  # До уборки шагов уже 5: есть системная часть — своя одним шагом, иначе шаг на часть (одна выбранная группа — её подпись)
  $cl = @(if ($sysK) { if ($usrK) { [pscustomobject]@{ T = $(if ($one) { $Grp[$pick[0]].U } else { 'Убираю остальные файлы' }); K = $usrK } } }
    else { foreach ($p in $ph) { $pk = @($p[2..($p.Count - 1)] | Where-Object { $pick -contains $_ }); $kk = @(Keys ($pk -join ',') | Where-Object { $usrK -contains $_ }); if ($kk) { [pscustomobject]@{ T = $(if ($pk.Count -eq 1) { $Grp[$pk[0]].U } else { $p[1] }); K = $kk } } } })
  Step -Plan (@(if ($uac) { 'Жду, пока Windows спросит разрешение' }) + @(if ($sysK) { $tSys }) + @($cl | ForEach-Object { $_.T }) + @('Сравниваю место до и после'))
  Step -Unsafe; Sweep $sysK $tSys $cl $uac @('-AnyAge')
  # ---------- Было → стало ----------
  Step 'Сравниваю место до и после'; Start-Sleep -Milliseconds 300; $free1 = Free
  $ba = @($drives | ForEach-Object { "${_}: $(($free0[$_] / 1GB).ToString('0.0', $ru)) → $(($free1[$_] / 1GB).ToString('0.0', $ru)) ГБ" })
  # Итог — из обоих процессов: $cf и $df уже сложены в Sweep
  $gf = @{}; $got = [long]0; foreach ($k in $pick) { $gf[$k] = [long]0; foreach ($x in @(Keys $k)) { $gf[$k] += [long]$cf[$x] }; $got += $gf[$k] }
  $n = 0; foreach ($k in $ks) { $n += [int]$cb[$k] }
  $dk = @($df.Keys | Where-Object { $df[$_] -ge 1MB }); $hd = "Освободил $(Sz $got)$(if ($dk.Count -eq 1) { " на диске $($dk[0]):" })"; if (-not $got) { $hd = $(if ($n -or $notes.Count) { 'Ничего не убрал' } else { 'Убирать почти нечего' }) }
  Write-Host ''; Write-Host "$(if ($got) { "Освободил $(Sz $got)." } else { "$hd." })" -ForegroundColor Green
  foreach ($d in $drives) { Write-Host "Свободно на ${d}: было $(Sz $free0[$d]) → стало $(Sz $free1[$d])" -ForegroundColor White }
  foreach ($x in @($notes | Select-Object -Unique)) { Write-Host $x -ForegroundColor Yellow }
  $m = $n % 100; $k = $n % 10; $nf = $(if ($m -ge 11 -and $m -le 14) { 'файлов заняты' } elseif ($k -eq 1) { 'файл занят' } elseif ($k -ge 2 -and $k -le 4) { 'файла заняты' } else { 'файлов заняты' })
  if ($n) { $x = "$n $nf — это нормально: так бывает, когда программа открыта."; Write-Host $x -ForegroundColor DarkGray; [void]$notes.Add($x) }
  # Чек: что убрал по группам, место и память до и после; вернуть нельзя — файлы удалены
  foreach ($k in $pick) { if ($gf[$k] -gt 0) { PctRcDo $rc $Did[$k] (Sz $gf[$k]) } }
  $why = 'Вернуть файлы нельзя — они удалены.' + $(if (@($pick | Where-Object { $_ -in 'web', 'chat', 'gpu' }).Count) { ' Кэш программы соберут сами.' } else { '' })
  [void](PctReceiptEnd $rc $hd $null $why ((@($notes | Select-Object -Unique)) -join ' '))
  Step -Done "освобождено $(Sz $got) · свободно $($ba -join ' · ')"; Jr "готово: освобождено $(Sz $got), занято файлов $n, $($ba -join ', ')$(if ($notes.Count) { "; $($notes -join ' ')" })"
} finally { PctUnlock $lk; if (-not $Scan) { Enter } }
