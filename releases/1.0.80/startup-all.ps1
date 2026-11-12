# Автозагрузка: без параметров — список в консоли; -Json <файл> — тот же список для окна (AUTOSTART-UI: без прав и без консоли); -Arg <часть>.<что>.<ключи> — запись из окна через run.ps1.
# -Arg: часть u — значения HKCU (без прав), a — HKLM, задачи и службы (с правами, одно окно Windows); что: off — отключить, best — отключить только совет 2, on — вернуть отключённое Помощником; ключи — H строк через «-».
# Запись — PctUndoItem (pct-core.ps1): журнал до изменения, запись, чтение обратно, чек. $Keep не трогаю и здесь: окну не верю.
# Стенд (только -Json и -Arg): PCT_PRIV_ROOT=Software\PomoshnikTest\<имя> — реестр HKCU\<стенд>\HKCU\… и \HKLM\…, папки <PCT_ROOT>\stand-startup\user и \common;
# PCT_UNDO_FAKE=<json> — задачи tasks {путь: {enabled, exe, args, stuck}}, службы services {имя: {start, delayed, display, path, pid, stuck}}, процессы procs {путь: байт}
param([string]$Json, [string]$Arg)
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
if (-not $Json -and -not $Arg) { $Host.UI.RawUI.WindowTitle = 'Автозагрузка — всё'
  try { $Host.UI.RawUI.BufferSize = New-Object Management.Automation.Host.Size(150, 3000); $Host.UI.RawUI.WindowSize = New-Object Management.Automation.Host.Size(150, 45) } catch {} }
$St = "$env:PCT_PRIV_ROOT".Trim().TrimEnd('\'); $Stand = [bool]$St -and [bool]($Json -or $Arg); $StandOk = $St -match '^Software\\PomoshnikTest\\[A-Za-z0-9_-]+$'
$Fake = $(if ($Stand) { PctUndoFake })
# Путь реестра для командлетов (HKCU:\…) и для pct-core (HKCU\…); стенд — ключ HKCU\<стенд>\<HKCU|HKLM>\…
function RegP([string]$p) { if ($Stand) { $p -replace '^(HKCU|HKLM):\\', "HKCU:\$St\`$1\" } else { $p } }
function Jk([string]$p) { $h, $s = $p -split ':\\', 2; if ($Stand) { "HKCU\$St\$h\$s" } else { "$h\$s" } }
$J ="$(PctDir 'helpers')\startup-journal.csv"   # что отключали и как было — для возврата
# Нельзя отключать: планшет, тачпад, звук, видео, Wi-Fi, удалённая помощь, сторожа.
$Keep = 'XP-?Pen|PenTablet|TabletDriver|Wacom|Realtek|Rtk|Synaptics|ELAN|Precision|Intel|igfx|AMD|Radeon|NVIDIA|Honor|Huawei|AnyDesk|PCT-|Everything|winws|zapret|Happ'
# Файл команды; $Arg — аргументы задачи. Запускатель (conhost, powershell, cmd, wscript, mshta, rundll32) — файл скрипта из аргументов: совет по нему, не по запускателю Windows
function ExeOf($cmd, $Arg, $Wd = '') { if ($cmd -match '^\s*"([^"]+)"(.*)$') { $m = $Matches[1]; $r = $Matches[2] } elseif ($cmd -match '^\s*(.+?\.(exe|cmd|bat|vbs|ps1))(\s.*|$)') { $m = $Matches[1]; $r = $Matches[3] } else { $m, $r = "$cmd".Trim() -split ' ', 2 }
  $f = FindExe ([Environment]::ExpandEnvironmentVariables($m)); $s = ScriptOf $f "$r $Arg" $Wd; if ($s) { $s } else { $f } }
$Launch = '^(conhost|powershell|pwsh|cmd|wscript|cscript|mshta|rundll32)(\.exe)?$'
# Первый файл в аргументах (в кавычках или без пробелов), кроме вложенного запускателя: conhost --headless powershell.exe -f "x.ps1" → x.ps1. Нет файла (-enc, -c) — пусто
# Имя файла без Split-Path: от пустой строки он бросает (задача с действием COM, ярлык без цели)
function LeafOf($p) { try { [IO.Path]::GetFileName("$p") } catch { "$p" } }
# Относительный путь скрипта в действии задачи Windows ищет от «Рабочей папки» задачи ($wd)
function ScriptOf($f, $a, $wd = '') { if ((LeafOf $f) -notmatch $Launch) { return }
  foreach ($x in [regex]::Matches("$a", '"([^"]+?\.(?:ps1|psm1|vbs|vbe|js|jse|wsf|bat|cmd|hta|dll|cpl|exe))"|([^\s",]+\.(?:ps1|psm1|vbs|vbe|js|jse|wsf|bat|cmd|hta|dll|cpl|exe))(?=[\s,"]|$)', 'IgnoreCase')) {
    $p = [Environment]::ExpandEnvironmentVariables($(if ($x.Groups[1].Success) { $x.Groups[1].Value } else { $x.Groups[2].Value }))
    if ((LeafOf $p) -notmatch $Launch) { $w = [Environment]::ExpandEnvironmentVariables("$wd".Trim('"')); if ($w -and $p -notmatch '^([A-Za-z]:|\\|/)') { $c = "$($w.TrimEnd('\'))\$p"; if ([IO.File]::Exists($c)) { return $c } }; return (FindExe $p) } } }
# Команда без папки (conhost.exe, rundll32) — ищу, как Windows: System32, Windows, затем PATH; последним — SysWOW64. Не нашёл — имя как есть
# Папки — от системы, PATH — только системный из HKLM (%SystemRoot%/%windir% → папка Windows, другие %…% и не полные пути — пропуск): windir и PATH с повышением — от её процессов
function FindExe($m) { if (-not $m -or $m -match '[\\/]') { return $m }; $ns = @($m); if ($m -notmatch '\.\w{2,4}$') { $ns = "$m.exe", $m }; $w = [Environment]::GetFolderPath('Windows')
  if ($null -eq $script:SysPath) { $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment')
    $script:SysPath = @("$(if ($k) { $k.GetValue('Path', '', 'DoNotExpandEnvironmentNames'); $k.Close() })" -split ';' | ForEach-Object { $_ -replace '(?i)%(SystemRoot|windir)%', $w.Replace('$', '$$') } | Where-Object { $_ -match '^[A-Za-z]:\\' -and $_ -notmatch '%' }) }
  foreach ($d in @([Environment]::GetFolderPath('System'), $w) + $script:SysPath + [Environment]::GetFolderPath('SystemX86')) { foreach ($n in $ns) { $p = "$("$d".Trim().TrimEnd('\'))\$n"; if ($d -and [IO.File]::Exists($p)) { return $p } } }; $m }
$PubCache = @{}
function Pub($f) { if ($PubCache.ContainsKey("$f")) { return $PubCache["$f"] }; $r = PubRaw $f; $PubCache["$f"] = $r; $r }
function PubRaw($f) { if ((LeafOf $f) -match $Launch) { 'команда без файла' } elseif ($f -and $f -notmatch '[\\/]') { 'не нашёл по имени' } elseif ($f -and (Test-Path -LiteralPath $f)) { $s = Get-AuthenticodeSignature -LiteralPath $f; if ($s.Status -eq 'Valid') { $(if ("$($s.SignerCertificate.Subject)" -match '(?:^|,\s*)CN="?([^",]+)') { $Matches[1] } else { $s.SignerCertificate.Subject }) } else { 'БЕЗ ПОДПИСИ' } } elseif ($f) { 'файл не найден' } else { '' } }
$approved = @{ 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32' }
# Папки автозагрузки не из окружения (с повышением оно от её процессов): общая — от системы, своя — в профиле по SID (не нашёл профиль — её пропускаю)
$folders = @{ "$([Environment]::GetFolderPath('CommonApplicationData'))\Microsoft\Windows\Start Menu\Programs\StartUp" = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' }
$ph = PctHome; if ($ph) { $folders["$ph\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"] = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' }
if ($Stand) { $folders = @{ "$(PctRoot)\stand-startup\common" = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'; "$(PctRoot)\stand-startup\user" = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' } }
# Стенд: задачи и службы из подмены — того же вида, что Get-ScheduledTask и Win32_Service
function FakeTasks { foreach ($p in @($Fake.tasks.PSObject.Properties)) { $v = $p.Value; $i = $p.Name.LastIndexOf('\')
    [pscustomobject]@{ TaskPath = $p.Name.Substring(0, $i + 1); TaskName = $p.Name.Substring($i + 1); State = $(if ($v.enabled) { 'Ready' } else { 'Disabled' }); Principal = [pscustomobject]@{ UserId = '' }; Actions = @([pscustomobject]@{ Execute = "$($v.exe)"; Arguments = "$($v.args)"; WorkingDirectory = '' }) } } }
function FakeSvc { foreach ($p in @($Fake.services.PSObject.Properties)) { $v = $p.Value; [pscustomobject]@{ Name = $p.Name; DisplayName = "$($v.display)"; PathName = "$($v.path)"; StartMode = @{ 2 = 'Auto'; 3 = 'Manual'; 4 = 'Disabled' }[[int]$v.start]; ProcessId = [int]$v.pid } } }
function Collect {
  $L = New-Object Collections.Generic.List[object]
  # Все значения ключа: фильтр «^PS» по свойствам Get-ItemProperty прятал и записи с именем на «PS»
  foreach ($k in $approved.Keys) { $p = Get-Item -LiteralPath (RegP $k); foreach ($vn in @(if ($p) { $p.GetValueNames() })) { $id = $(if ($vn) { $vn } else { '(default)' })
    $b = (Get-ItemProperty (RegP $approved[$k])).($id); $on = -not ($b -and ($b[0] -band 1))
    $c = "$($p.GetValue($vn))"; $f = ExeOf $c; $L.Add([pscustomobject]@{ Kind = 'Реестр'; Name = $id; On = $on; File = $f; Cmd = $c; Pub = (Pub $f); Key = $approved[$k]; Id = $id }) } }
  foreach ($d in $folders.Keys) { Get-ChildItem -LiteralPath $d -File | Where-Object Name -ne 'desktop.ini' | ForEach-Object {
    $b = (Get-ItemProperty (RegP $folders[$d])).($_.Name); $on = -not ($b -and ($b[0] -band 1)); $f = $_.FullName; $c = $f
    if ($_.Extension -eq '.lnk') { $sc = (New-Object -ComObject WScript.Shell).CreateShortcut($_.FullName); $f = $sc.TargetPath; $c = "$f $($sc.Arguments)"; $s = ScriptOf $f "$($sc.Arguments)" $sc.WorkingDirectory; if ($s) { $f = $s } }
    $L.Add([pscustomobject]@{ Kind = 'Папка'; Name = $_.BaseName; On = $on; File = $f; Cmd = $c; Pub = (Pub $f); Key = $folders[$d]; Id = $_.Name }) } }
  # Задачи отключённых учётных записей (например, WsiAccount) никогда не запускаются, а менять их Windows не даёт — не показываем.
  $dead = @(if (-not $Stand) { Get-CimInstance Win32_UserAccount -Filter 'LocalAccount=True AND Disabled=True' | ForEach-Object Name })
  $(if ($Stand) { FakeTasks } else { Get-ScheduledTask }) | Where-Object { $_.TaskPath -notlike '\Microsoft\*' -and $dead -notcontains $_.Principal.UserId } | ForEach-Object {
    $f = ExeOf "$($_.Actions[0].Execute)" "$($_.Actions[0].Arguments)" "$($_.Actions[0].WorkingDirectory)"; $L.Add([pscustomobject]@{ Kind = 'Задача'; Name = $_.TaskName; On = ($_.State -ne 'Disabled'); File = $f; Cmd = "$($_.Actions[0].Execute) $($_.Actions[0].Arguments)"; Pub = $(if ($f) { Pub $f } else { 'действие COM' }); Key = $_.TaskPath; Id = $_.TaskName }) }
  # Журнала ещё нет (ничего не отключали) — отключённых мной служб нет
  $off = @($(if (Test-Path -LiteralPath $J) { Import-Csv $J -Delimiter ';' -Encoding UTF8 }) | Where-Object { $_.'Тип' -eq 'Служба' } | ForEach-Object { $_.'Имя' })
  if ($Json -or $Arg) { $off += @(foreach ($j in @(Opened)) { foreach ($x in @($j.items)) { if ($x.kind -eq 'service') { "$($x.name)" } } }) } # отключённые из окна — тоже в списке
  $(if ($Stand) { FakeSvc } else { Get-CimInstance Win32_Service }) | Where-Object { ($_.StartMode -eq 'Auto' -or $off -contains $_.Name) } | Where-Object { $_.PathName -and $_.PathName -notmatch '\\Windows\\(System32|SysWOW64)\\(svchost|lsass|services|spoolsv|SearchIndexer|dllhost|wbem)' } | ForEach-Object {
    $f = ExeOf $_.PathName; $pb = Pub $f
    if ($pb -notmatch '^Microsoft') { $L.Add([pscustomobject]@{ Kind = 'Служба'; Name = $_.DisplayName; On = ($_.StartMode -eq 'Auto'); File = $f; Pub = $pb; Key = $_.StartMode; Id = $_.Name; Pid = $_.ProcessId }) } }
  $L | Sort-Object Kind, Name }
function Jot($it, $act) { if (-not (Test-Path $J)) { 'Время;Действие;Тип;Имя;Было' | Set-Content $J -Encoding UTF8 }; "{0:yyyy-MM-dd HH:mm};{1};{2};{3};{4}" -f (Get-Date), $act, $it.Kind, $it.Id, $it.Key | Add-Content $J -Encoding UTF8 }
function Toggle($it) {
  $to = -not $it.On
  switch ($it.Kind) {
    { $_ -in 'Реестр', 'Папка' } { if (-not (Test-Path $it.Key)) { New-Item $it.Key -Force | Out-Null }
      $v = [byte[]](0,0,0,0,0,0,0,0,0,0,0,0); $v[0] = $(if ($to) { 2 } else { 3 }); Set-ItemProperty -Path $it.Key -Name $it.Id -Value $v -Type Binary }
    'Задача' { if ($to) { Enable-ScheduledTask -TaskPath $it.Key -TaskName $it.Id | Out-Null } else { Disable-ScheduledTask -TaskPath $it.Key -TaskName $it.Id | Out-Null } }
    'Служба' { Set-Service -Name $it.Id -StartupType $(if ($to) { 'Automatic' } else { 'Manual' }) } }
  $now = switch ($it.Kind) {
    { $_ -in 'Реестр', 'Папка' } { $b = (Get-ItemProperty $it.Key).($it.Id); -not ($b -and ($b[0] -band 1)) }
    'Задача' { (Get-ScheduledTask -TaskPath $it.Key -TaskName $it.Id).State -ne 'Disabled' }
    'Служба' { (Get-CimInstance Win32_Service -Filter "Name='$($it.Id)'").StartMode -eq 'Auto' } }
  if ($now -eq $to) { Jot $it $(if ($to) { 'вкл' } else { 'выкл' }); $true } else { $false } }
function Say($n, $it, $ok) { if ($ok) { Write-Host ("  {0}{1} — {2}" -f $n, $it.Name, $(if ($it.On) { 'выключено' } else { 'включено' })) -ForegroundColor Green }
  else { Write-Host ("  {0}{1} — НЕ получилось: Windows не дала доступ. Ничего не изменено." -f $n, $it.Name) -ForegroundColor Red } }

# Совет по пункту: 2 — рекомендую отключить, 1 — можно отключить, 0 — оставить.
function Advice($it) {
  $s = "$($it.Name) $($it.File) $($it.Pub)"
  if ($s -match $Keep) { return 0, 'драйвер или нужная программа — не трогать' }
  if ($s -match 'Windhawk') { return 0, 'оформление Windows этой сборки' }
  # Запускатель без файла в аргументах (-enc, -c, cmd /c): издатель — Windows, но что запускается, не видно
  if ($it.Pub -eq 'команда без файла') { if ("$($it.Cmd)" -match '(?i)(^|\s)[-/](e|ec|en\w*)(\s|$)') { return 1, 'команда зашифрована — так часто прячутся вирусы' }; return 1, 'команда спрятана в задаче — покажи помощнику' }
  if ($it.Pub -eq 'не нашёл по имени') { return 0, 'не нашёл файл по имени — не знаю, что это' }
  if ($it.Pub -eq 'файл не найден') { return 2, 'программы уже нет — запись лишняя' }
  if ($s -match 'SoftLanding|GameModeX|booster|Driver ?Booster|iTop|Nahimic|Overwolf|Mail\.ru|Amigo|Avast|AVG|CCleaner|IObit|SystemCare|Wise ?Care|McAfee|Baidu|360 ?Total|Razer ?Cortex') { return 2, 'реклама или лишний «ускоритель»' }
  if ($it.Pub -eq 'действие COM') { return 0, 'задача без файла' }
  if ($it.Pub -eq 'БЕЗ ПОДПИСИ') { return 1, 'без подписи: не знаешь, что это, — отключи' }
  # Обновлятор — по имени файла .exe, не по названию: задача «…UpdateCleanup…» — не обновлятор
  if ((LeafOf $it.File) -match '(?i)update.*\.exe$') { return 1, 'обновления: обновится, когда откроешь программу' }
  if ($s -match 'Steam|Discord|Telegram|uTorrent|qBittorrent|Epic|EA ?app|Origin|Battle\.net|Spotify|Музык|Music|OneDrive|Skype|Zoom|Viber|WhatsApp|Teams|Ubisoft|GOG|Riot|Opera|Chrome|Yandex|Яндекс|Browser') { return 1, 'откроешь, когда понадобится' }
  return 0, 'оставить, если не знаешь, что это' }

# ---------- Для окна (AUTOSTART-UI) ----------
# Что это и что будет, если отключить — простыми словами (по названию, иначе по виду и совету)
function What($it, $adv) { $s = "$($it.Name) $($it.File)"
  if ($s -match 'Steam|Epic|EA ?app|Origin|Battle\.net|Ubisoft|GOG|Riot') { return 'Магазин игр. Через него запускаются игры.' }
  if ($s -match 'Discord') { return 'Голосовой чат и сообщения.' }; if ($s -match 'Telegram|Viber|WhatsApp') { return 'Сообщения и звонки.' }; if ($s -match 'Skype|Zoom|Teams') { return 'Звонки и встречи.' }
  if ($s -match 'Spotify|Музык|Music') { return 'Музыка.' }; if ($s -match 'OneDrive') { return 'Копии твоих файлов в облаке.' }; if ($s -match 'uTorrent|qBittorrent') { return 'Скачивание файлов через торрент.' }
  if ($s -match 'Opera|Chrome|Yandex|Яндекс|Browser') { return 'Браузер.' }; if ($s -match 'Creative ?Cloud') { return 'Программы Adobe и их обновления.' }
  if ($it.Pub -eq 'файл не найден') { return 'Запись о программе, которой уже нет.' }; if ($adv[1] -like 'реклама*') { return 'Программа, которая показывает рекламу или обещает «ускорить» компьютер.' }
  if ($adv[1] -like 'обновления*') { return 'Проверяет обновления программы.' }; if ($it.Pub -eq 'команда без файла') { return 'Запускает команду, а что в ней — не видно.' }
  if ($it.Kind -eq 'Задача') { return 'Задача по расписанию: запускается сама.' }; if ($it.Kind -eq 'Служба') { return 'Служба: работает в фоне, без окна.' }; 'Программа, которая открывается сама при включении.' }
function IfOff($it, $adv) { if ($it.Pub -eq 'файл не найден') { return 'Ничего не изменится: программы уже нет.' }; if ($it.Kind -eq 'Служба') { return 'Служба запустится, когда программа её позовёт.' }
  if ($adv[1] -like 'обновления*') { return 'Программа обновится, когда ты её откроешь.' }; if ("$($it.Name) $($it.File)" -match 'Discord|Telegram|Viber|WhatsApp|Skype|Zoom|Teams') { return 'Сообщения придут, только когда откроешь программу.' }
  if ($it.Kind -eq 'Задача') { return 'Задача не запустится сама. Программа останется.' }; 'Не откроется сама при включении. Откроешь, когда понадобится.' }
function Kept($it) { ($it.Name + ' ' + $it.File + ' ' + $it.Pub) -match $Keep }
# Ключ строки для окна: вид, место и имя (у службы место — режим запуска, он меняется)
function RowH($it) { $b = [Security.Cryptography.SHA1]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes("$($it.Kind)|$(if ($it.Kind -ne 'Служба') { $it.Key })|$($it.Id)")); -join @($b[0..4] | ForEach-Object { $_.ToString('x2') }) }
# С правами: всё, кроме значений HKCU (их пишу без прав: с повышением HKCU может быть чужим)
function Adm($it) { "$($it.Key)" -notlike 'HKCU:*' }
# Пункт журнала (pct-core) и запись: значение StartupApproved (3 — отключено, 2 — включено, как Диспетчер задач), задача, служба (3 — вручную, 2 — авто)
function Spec($it) { switch ($it.Kind) { 'Задача' { @{ kind = 'task'; path = "$($it.Key)$($it.Id)" } } 'Служба' { @{ kind = 'service'; name = "$($it.Id)" } } default { @{ kind = 'reg'; key = (Jk $it.Key); name = "$($it.Id)" } } } }
function Target($it, [bool]$On) { $t = Spec $it; $v = [byte[]](0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0); $v[0] = $(if ($On) { 2 } else { 3 })
  switch ($t.kind) { 'reg' { $t.existed = $true; $t.type = 'Binary'; $t.old = [Convert]::ToBase64String($v) } 'task' { $t.old = $On } default { $t.old = $(if ($On) { 2 } else { 3 }); $t.delayed = $false } }; $t }
function SvcStart($it) { if ($Stand) { return [int](PctUndoFake).services.($it.Id).start }; $k = PctRegKey "HKLM\SYSTEM\CurrentControlSet\Services\$($it.Id)"; if ($k) { try { [int]$k.GetValue('Start', 0) } finally { $k.Close() } } }
function RegBytes($it) { $k = PctRegKey (Jk $it.Key); if ($k) { try { , $k.GetValue($it.Id) } finally { $k.Close() } } }
# Как сейчас (чтение обратно)
function OnNow($it) { switch ((Spec $it).kind) { 'reg' { $b = RegBytes $it; -not ($b -and ($b[0] -band 1)) }
    'task' { $p = "$($it.Key)$($it.Id)"; if ($Stand) { [bool](PctUndoFake).tasks.$p.enabled } else { $s = New-Object -ComObject Schedule.Service; $s.Connect(); [bool]$s.GetFolder('\').GetTask($p).Enabled } }
    default { (SvcStart $it) -eq 2 } } }
# Стоит записанное Помощником (окном или старой консолью — они пишут одно и то же): иначе человек поменял сам
function Mine($it) { switch ((Spec $it).kind) { 'reg' { "$((RegBytes $it) -join ',')" -eq '3,0,0,0,0,0,0,0,0,0,0,0' } 'task' { -not (OnNow $it) } default { (SvcStart $it) -eq 3 } } }
# Старый журнал консоли: последнее действие по пункту — «выкл»
function Csv($it) { $l = @($(if (Test-Path -LiteralPath $J) { Import-Csv $J -Delimiter ';' -Encoding UTF8 }) | Where-Object { $_.'Тип' -eq $it.Kind -and $_.'Имя' -eq $it.Id }); $l.Count -and $l[-1].'Действие' -eq 'выкл' }
# Открытые журналы окна, от нового к старому; $Adm — только с правами ($true) или только без ($false)
function Opened($Adm) { $r = @(); $fs = @(); try { $fs = @([IO.Directory]::GetFiles((PctDir 'reports'), 'undo-startup-*.json') | Sort-Object -Descending) } catch {}
  foreach ($f in $fs) { $j = PctUndoLoad ([IO.Path]::GetFileName($f)); if ($j -is [string] -or $j.closed) { continue }; if ($null -ne $Adm -and [bool]$j.admin -ne $Adm) { continue }; $r += $j }; $r }
function Same($x, $it) { $s = Spec $it; if ("$($x.kind)" -ne $s.kind) { return $false }; switch ($s.kind) { 'reg' { "$($x.key)" -eq $s.key -and "$($x.name)" -eq $s.name } 'task' { "$($x.path)" -eq $s.path } default { "$($x.name)" -eq $s.name } } }
# Пункты журналов по строке: от нового к старому (журнал, пункт)
function Hits($Js, $it) { foreach ($j in $Js) { foreach ($x in @(PctUndoPending $j)) { if (Same $x $it) { , @($j, $x) } } } }
# Память: только настоящая — рабочий набор запущенных процессов этого файла (у службы — её процесса). Не запущена — -1
function Mem($Items) { $ws = @{}; $byPid = @{}
  if ($Stand) { foreach ($p in @($Fake.procs.PSObject.Properties)) { $ws[$p.Name.ToLower()] = [long]$p.Value } }
  else { foreach ($p in @(Get-CimInstance Win32_Process -Property ProcessId, ExecutablePath, WorkingSetSize)) { $byPid[[int]$p.ProcessId] = [long]$p.WorkingSetSize; if ($p.ExecutablePath) { $k = "$($p.ExecutablePath)".ToLower(); $ws[$k] = [long]$ws[$k] + [long]$p.WorkingSetSize } } }
  foreach ($it in $Items) { $b = $(if ($it.Kind -eq 'Служба' -and $it.Pid -and -not $Stand) { [long]$byPid[[int]$it.Pid] } elseif ($it.File) { [long]$ws["$($it.File)".ToLower()] } else { [long]0 })
    $it | Add-Member NoteProperty Mb $(if ($it.On -and $b -gt 0) { [int][math]::Max(1, [math]::Round($b / 1MB)) } else { -1 }) -Force } }
function StandBad { $Stand -and (-not $StandOk -or -not $Fake) }
if ($Json) { $sw = [Diagnostics.Stopwatch]::StartNew(); $o = [ordered]@{ err = '' }
  if (StandBad) { PctUndoLog "startup-all: отказ, стенд не подходит ($St)"; $o.err = 'stand' }
  else { $items = @(Collect); Mem $items; $js = @(Opened)
    $o.rows = @(foreach ($it in $items) { $a = Advice $it; $lock = ''; $mine = $false
      if (-not $it.On) { $hit = @(Hits $js $it); if ($hit.Count) { if (Mine $it) { $mine = $true } else { $lock = 'self' } } elseif ((Csv $it) -and (Mine $it)) { $mine = $true } else { $lock = 'ext' } }
      [ordered]@{ h = (RowH $it); kind = @{ 'Реестр' = 'reg'; 'Папка' = 'folder'; 'Задача' = 'task'; 'Служба' = 'svc' }[$it.Kind]; name = "$($it.Name)"; pub = $(if ($it.Pub -ceq 'БЕЗ ПОДПИСИ') { 'без подписи' } else { "$($it.Pub)" }); on = [bool]$it.On
        adv = [int]$a[0]; why = "$($a[1])"; keep = [bool](Kept $it); grp = $(if ($it.Kind -in 'Реестр', 'Папка' -and $a[1] -notlike 'обновления*') { 'app' } else { 'other' }); adm = [bool](Adm $it); lock = $lock; mine = $mine; mb = [int]$it.Mb; what = (What $it $a); iff = (IfOff $it $a) } }) }
  $o.ms = [int]$sw.ElapsedMilliseconds; [IO.File]::WriteAllText($Json, ($o | ConvertTo-Json -Depth 4 -Compress), (New-Object Text.UTF8Encoding $false)); return } # окно читает файл после выхода процесса
if ($Arg) {
  if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
  function Enter { Write-Host "`nEnter — закрыть."; Read-Host | Out-Null }
  function RcOf([string]$Journal) { try { foreach ($f in [IO.Directory]::GetFiles("$(PctDir 'reports')\receipts", '*-startup*.json')) { $x = [IO.File]::ReadAllText($f) | ConvertFrom-Json; if ("$($x.undo.journal)" -eq $Journal) { return [IO.Path]::GetFileName($f) } } } catch { PctUndoLog "startup-all: чеки не прочитал: $($_.Exception.Message)" }; '' }
  # Человек поменял сам: не трогаю, пункт закрываю — возвращать нечего
  function Drop($Jr, $X) { $X.state = 'undone'; if (-not @($Jr.items | Where-Object { $_.state -ne 'undone' }).Count) { $Jr.closed = (Get-Date).ToString('s') }; PctUndoSave $Jr }
  Write-Host "`nАВТОЗАГРУЗКА`n" -ForegroundColor Cyan; Step -Safe
  if (StandBad) { Step 'Проверяю стенд'; Step -Fail 'стенд задан неверно' -Do 'Нужны PCT_PRIV_ROOT=Software\PomoshnikTest\<имя> и PCT_UNDO_FAKE.'; PctUndoLog "startup-all: отказ, стенд не подходит ($St)"; Enter; return }
  $part, $op, $hs = "$Arg" -split '\.', 3; $hs = @("$hs" -split '-' | Where-Object { $_ -match '^[0-9a-f]{10}$' } | Select-Object -Unique)
  if ($part -notin 'a', 'u' -or $op -notin 'off', 'best', 'on' -or -not $hs.Count) { Step 'Читаю задание'; Step -Fail 'не знаю, что менять' -Do 'Нажми выключатель в «Автозагрузке».'; Enter; return }
  $isAdm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $Stand -and $part -eq 'a' -and -not $isAdm) { Step 'Проверяю права'; Step -Fail 'нет разрешения Windows' -Do 'Нажми ещё раз и выбери «Да» в окне Windows.'; Enter; return }
  if (-not $Stand -and $part -eq 'u' -and (PctElevated)) { Step 'Проверяю права'; Step -Fail 'запущено с правами — свои программы так не меняю' -Do 'Нажми выключатель в окне Помощника.'; Enter; return }
  $lk = PctLock 'startup' 10; if (-not $lk) { Step 'Проверяю, не идёт ли другое изменение'; Step -Fail 'идёт другое изменение' -Do 'Дождись, пока оно закончится, и нажми ещё раз.'; Enter; return }
  try {
    PctUndoLog "startup-all: начал $Arg$(if ($Stand) { ' (стенд)' })"; $verb = @{ off = 'Отключаю'; best = 'Отключаю, как советую'; on = 'Возвращаю как было' }[$op]
    Step -Plan 'Смотрю, как сейчас', $verb, 'Проверяю'; Step 'Смотрю, как сейчас' -Hint 'Ничего не меняю'
    $pick = @(Collect | Where-Object { $hs -contains (RowH $_) -and (Adm $_) -eq ($part -eq 'a') }); $kept = @($pick | Where-Object { Kept $_ }); $pick = @($pick | Where-Object { -not (Kept $_) })
    if ($kept.Count) { PctUndoLog "startup-all: не трогаю (драйвер или нужная программа): $(@($kept | ForEach-Object { $_.Name }) -join ', ')" }
    if ($op -eq 'best') { $pick = @($pick | Where-Object { (Advice $_)[0] -eq 2 }) }
    if ($op -ne 'on') {
      $pick = @($pick | Where-Object { $_.On }); if (-not $pick.Count) { Step -Done $(if ($kept.Count) { 'драйвер или нужная программа — не трогаю' } else { 'уже не запускается' }); return }
      Step -Done "запускается: $($pick.Count)"; Step -Unsafe; Step $verb -Hint 'Сначала запоминаю, как было'
      $jr = PctUndoNew 'startup' 'Автозагрузка' -Admin:($part -eq 'a'); $done = @(); $bad = @()
      foreach ($it in $pick) { $x = PctUndoAdd $jr (Spec $it) $it.Name; [void](PctUndoItem (Target $it $false)); if (-not (OnNow $it)) { $done += $it } else { $x.state = 'undone'; $bad += $it } }
      if (-not @($jr.items | Where-Object { $_.state -ne 'undone' }).Count) { $jr.closed = (Get-Date).ToString('s') }; PctUndoSave $jr
      Step 'Проверяю' -Hint 'Читаю обратно'; PctUndoLog "startup-all: $Arg — отключил $($done.Count) из $($pick.Count)"
      if ($done.Count) { $rc = PctReceipt 'startup' 'Автозагрузка'; foreach ($it in $done) { PctRcDo $rc $it.Name 'запускается → не запускается' }; foreach ($it in $bad) { PctRcDo $rc $it.Name 'не вышло' }
        $head = $(if ($bad.Count) { 'Не вышло: отключил не всё' } elseif ($op -eq 'best') { "Сделал как советую: отключил $($done.Count)" } elseif ($done.Count -eq 1) { "Отключил «$($done[0].Name)»" } else { "Отключил: $($done.Count)" })
        [void](PctReceiptEnd $rc $head $jr '' 'Сработает при следующем включении.') }
      if (-not $bad.Count) { Step -Done 'сработает при следующем включении'; Write-Host "`nГотово. Сработает при следующем включении." -ForegroundColor Green; return }
      if (-not $done.Count) { Step -Fail 'Windows не дала поменять' -Do 'Попробуй ещё раз или позови помощь.'; return }
      Step -Fail "отключил $($done.Count) из $($pick.Count)" -Do 'Нажми выключатель ещё раз или позови помощь.'; return }
    # ---------- Вернуть: только то, что отключил Помощник, и только если стоит его запись ----------
    $js = @(Opened ($part -eq 'a')); $back = @(); $self = @(); $old = @()
    foreach ($it in @($pick | Where-Object { -not $_.On })) { $hit = @(Hits $js $it)
      if ($hit.Count) { if (Mine $it) { $back += , @($it, $hit) } else { foreach ($b in $hit) { Drop $b[0] $b[1] }; $self += $it; PctUndoLog "startup-all: $($it.Name) — поменяли мимо Помощника, не трогаю" } }
      elseif ((Csv $it) -and (Mine $it)) { $old += $it } }
    if (-not ($back.Count + $old.Count)) { Step -Done $(if ($self.Count) { 'ты уже поменял это сам — не трогаю' } elseif ($kept.Count) { 'драйвер или нужная программа — не трогаю' } else { 'не Помощник отключал — не трогаю' }); return }
    Step -Done "отключено Помощником: $($back.Count + $old.Count)"; Step -Unsafe; Step $verb -Hint 'Возвращаю, как было до Помощника'
    $rc = PctReceipt 'startup' 'Автозагрузка' @() 'undo' $(if ($back.Count) { RcOf $back[0][1][0][0].file } else { '' }); $okN = 0; $bad = @()
    foreach ($b in $back) { $h0 = $b[1][0]; $ok = (PctUndoOne $h0[0] $h0[1]) -and (OnNow $b[0]); if ($ok) { for ($i = 1; $i -lt $b[1].Count; $i++) { Drop $b[1][$i][0] $b[1][$i][1] }; $okN++; PctRcDo $rc $b[0].Name 'как было' } else { $bad += $b[0] } }
    foreach ($it in $old) { if ((PctUndoItem (Target $it $true)) -and (OnNow $it)) { Jot $it 'вкл'; $okN++; PctRcDo $rc $it.Name 'как было' } else { $bad += $it } }
    foreach ($it in $self) { PctRcDo $rc $it.Name 'не трогал: ты уже поменял это сам' }
    Step 'Проверяю' -Hint 'Читаю обратно'; $sn = $(if ($self.Count) { "Не трогал: $(@($self | ForEach-Object { $_.Name }) -join ', ') — ты уже поменял это сам." } else { '' })
    [void](PctReceiptEnd $rc $(if ($bad.Count) { 'Вернул не всё' } else { 'Вернул как было' }) $null 'Это возврат. Чтобы отключить снова, нажми тот же выключатель.' $sn)
    PctUndoLog "startup-all: $Arg — вернул $okN из $($back.Count + $old.Count)"
    if ($bad.Count) { Step -Fail "вернул $okN из $($back.Count + $old.Count)" -Do 'Нажми выключатель ещё раз или позови помощь.' } elseif ($self.Count) { Step -Done 'как было, кроме того, что ты поменял это сам' } else { Step -Done 'как было' }
  } finally { PctUnlock $lk; Enter }
  return }

while ($true) {
  Clear-Host
  Write-Host "АВТОЗАГРУЗКА — ВСЁ, что запускается само (кроме частей самой Windows)`n" -ForegroundColor Cyan
  $items = @(Collect); $i = 0; $rec = @()
  foreach ($it in $items) { $i++; $adv = Advice $it
    $nm = $(if ($it.Name.Length -gt 34) { $it.Name.Substring(0, 33) + '…' } else { $it.Name })
    $pb = $(if ($it.Pub.Length -gt 24) { $it.Pub.Substring(0, 23) + '…' } else { $it.Pub })
    $tip = $(if (-not $it.On) { 'отключено' } elseif ($adv[0] -eq 2) { 'РЕКОМЕНДУЮ ОТКЛЮЧИТЬ: ' + $adv[1] } elseif ($adv[0] -eq 1) { 'можно отключить: ' + $adv[1] } else { 'оставить: ' + $adv[1] })
    if ($it.On -and $adv[0] -eq 2) { $rec += $it }
    $c = $(if (-not $it.On) { 'DarkGray' } elseif ($adv[0] -eq 2) { 'Yellow' } elseif ($adv[0] -eq 1) { 'White' } else { 'DarkGray' })
    Write-Host ("{0,3}. [{1}] {2,-6} {3,-34} {4,-24} {5}" -f $i, $(if ($it.On) { 'ВКЛ ' } else { 'выкл' }), $it.Kind, $nm, $pb, $tip) -ForegroundColor $c }
  Write-Host "`nВКЛ — запускается сама. Отключённая «Служба» не ломается: она стартует, когда программа её позовёт."
  Write-Host 'Жёлтым — рекомендую отключить. Белым — можно, если не нужно в фоне. Серым — оставить.' -ForegroundColor Yellow
  Write-Host "`nНомер (или несколько через пробел) — ВКЛЮЧИТЬ/ВЫКЛЮЧИТЬ." -ForegroundColor Green
  if ($rec) { Write-Host "Буква р — отключить всё, что рекомендую ($($rec.Count) шт.)." -ForegroundColor Green }
  Write-Host 'Просто Enter — выйти.' -ForegroundColor Green
  $a = Read-Host '>'
  if (-not $a.Trim()) { break }
  if ($a.Trim() -match '^[рРpP]$') { foreach ($it in $rec) { Say '' $it (Toggle $it) }; Start-Sleep 3; continue }
  # Не длиннее 6 цифр: [int] от «99999999999» бросил бы ошибку
  foreach ($n in ($a -split '[ ,;]+' | Where-Object { $_ -match '^\d{1,6}$' })) {
    # «0» — не пункт: $items[-1] был бы последним
    $it = $(if ([int]$n -ge 1) { $items[[int]$n - 1] }); if (-not $it) { continue }
    if (($it.Name + ' ' + $it.File + ' ' + $it.Pub) -match $Keep) { Write-Host "  $n. $($it.Name) — это драйвер или нужная программа, не трогаю." -ForegroundColor Yellow; Start-Sleep 2; continue }
    Say "$n. " $it (Toggle $it) }
  Start-Sleep 3 }
Write-Host "`nИзменения вступят в силу после перезагрузки. Журнал: $J"; Start-Sleep 3