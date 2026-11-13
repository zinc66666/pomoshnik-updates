# Общие пути и порт Помощника. Подключение: . "$PSScriptRoot\pct-core.ps1" — до любого командлета. При подключении задаёт функции; с повышением ещё чистит окружение (ниже).
# U1b: с повышением (администратор при включённом UAC) окружение — от пользователя: HKCU\Environment пишет любой её процесс без прав. Убираю все PCT_* (корень, адрес обновления, подмены),
# в PSModulePath — только системные папки (иначе модуль из «Документов» загрузится раньше системного). Только .NET: командлет до очистки загрузил бы модуль по старому пути.
# UAC выключен — границы нет (любой её процесс — администратор), окружение как есть. Копия PctElevated и PctSafeEnv — в updater.ps1 (тест сверяет)
function PctElevated { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -and
  "$([Microsoft.Win32.Registry]::GetValue('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System', 'EnableLUA', 1))" -ne '0' }
function PctSafeEnv { foreach ($k in @([Environment]::GetEnvironmentVariables().Keys)) { if ("$k" -like 'PCT_*') { [Environment]::SetEnvironmentVariable("$k", $null) } }
  $env:PSModulePath = "$PSHOME\Modules;$([Environment]::GetFolderPath('ProgramFiles'))\WindowsPowerShell\Modules" }
if (PctElevated) { PctSafeEnv }
# Папка профиля по SID из HKLM (ProfileList), не из USERPROFILE/LOCALAPPDATA: окружение с повышением — от её процессов. Путь с %…% или не абсолютный — $null (группы профиля не трогать)
function PctHome { $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)")
  $p = $(if ($k) { "$($k.GetValue('ProfileImagePath', '', 'DoNotExpandEnvironmentNames'))"; $k.Close() }); if ($p -match '^[A-Za-z]:\\' -and $p -notmatch '%') { $p.TrimEnd('\') } }
# Корень: $env:PCT_ROOT (для проверок, только без повышения) → папка выше helpers, если скрипт лежит в helpers → C:\PC-Tweaks-Laptop.
function PctRoot { if ($env:PCT_ROOT) { return $env:PCT_ROOT }
  if ([IO.Path]::GetFileName($PSScriptRoot) -eq 'helpers') { return [IO.Path]::GetDirectoryName($PSScriptRoot) }; 'C:\PC-Tweaks-Laptop' } # .NET, как PctRepDir: Split-Path грузит модуль (~180 мс)
function PctDir([ValidateSet('helpers', 'guard', 'run', 'reports')][string]$Name) { Join-Path (PctRoot) $Name }
# SOCKS Happ: vpn.socks из профиля (только как JSON, только 127.0.0.1:<порт до 65535>), иначе 127.0.0.1:10808
function PctSocks { $s = ''; try { $s = "$(([IO.File]::ReadAllText("$env:LOCALAPPDATA\Pomoshnik\profile.json") | ConvertFrom-Json).vpn.socks)" } catch {}
  if ($s -match '^127\.0\.0\.1:(\d{2,5})$' -and [int]$Matches[1] -le 65535) { $s } else { '127.0.0.1:10808' } }
function PctSocksPort { [int](PctSocks).Split(':')[1] }
# Фоновое дело для окна: run\bg-<имя>.json — шаг, подсказка, номер шага n из of, время t, pid. -End — итог (окно покажет его в течение 10 мин). Сбой записи (файл занят чтением окна) — до 3 повторов через 50 мс, после них молча
function PctBg([string]$Name, [string]$Step, [string]$Hint = '', [int]$N = 0, [int]$Of = 0, [string]$End) { try { $d = PctDir 'run'; [void][IO.Directory]::CreateDirectory($d); $p = "$d\bg-$Name.json"; $t = "$p.$PID.tmp"
  $o = [ordered]@{ name = $Name; step = $Step; hint = $Hint; n = $N; of = $Of; t = (Get-Date -Format s); pid = $PID }; if ($PSBoundParameters.ContainsKey('End')) { $o.step = ''; $o.end = $End }
  $j = $o | ConvertTo-Json -Compress
  for ($i = 0; ; $i++) { try { [IO.File]::WriteAllText($t, $j, (New-Object Text.UTF8Encoding $false)); if ([IO.File]::Exists($p)) { [IO.File]::Replace($t, $p, [NullString]::Value) } else { [IO.File]::Move($t, $p) }; break } catch { if ($i -ge 3) { throw }; [Threading.Thread]::Sleep(50) } } } catch { try { [IO.File]::Delete($t) } catch {} } }
# Одно изменение за раз между процессами и пользователями (SYSTEM, администратор, она): мьютекс Global\Pomoshnik.<имя>. PctLock — объект или $null (занято). Повторный захват тем же потоком проходит
# Брошенный мьютекс (процесс упал) — взят. Нет прав на Global\ — объект без мьютекса (работа без блокировки) и строка в reports\lock.log. Освобождать PctUnlock в finally
function PctLock([string]$Name, [int]$Wait = 0) { $n = "Global\Pomoshnik.$Name"; $m = $null; $rw = [Security.AccessControl.MutexRights]'Synchronize, Modify'
  try { for ($i = 0; -not $m -and $i -lt 3; $i++) { try { $m = [Threading.Mutex]::OpenExisting($n, $rw) } catch [Threading.WaitHandleCannotBeOpenedException] {
        $s = New-Object Security.AccessControl.MutexSecurity; foreach ($a in @(@('S-1-5-18', 'FullControl'), @('S-1-5-32-544', 'FullControl'), @('S-1-5-11', $rw))) { $s.AddAccessRule((New-Object Security.AccessControl.MutexAccessRule((New-Object Security.Principal.SecurityIdentifier $a[0]), $a[1], 'Allow'))) }
        $c = $false; try { $m = [Threading.Mutex]::new($false, $n, [ref]$c, $s) } catch [UnauthorizedAccessException] {} } }
    if (-not $m) { throw 'мьютекс не открылся' } }
  catch { try { $d = PctDir 'reports'; [void][IO.Directory]::CreateDirectory($d); [IO.File]::AppendAllText("$d\lock.log", "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $n нет прав, работаю без блокировки: $($_.Exception.Message)`n", (New-Object Text.UTF8Encoding $false)) } catch {}
    return [pscustomobject]@{ Name = $Name; M = $null } }
  $got = $false; try { $got = $m.WaitOne($Wait * 1000) } catch [Threading.AbandonedMutexException] { $got = $true }
  if (-not $got) { $m.Dispose(); return $null }; [pscustomobject]@{ Name = $Name; M = $m } }
# Сеть: один процесс за раз рвёт или проверяет сеть (энергосбережение сетевой карты и подбор обхода). Занято — $Busy (строка для человека), потом ждёт до $Wait с; $null — не дождался. Берут после замка своей задачи, освобождают PctUnlock
function PctNetLock([scriptblock]$Busy, [int]$Wait = 900) { $l = PctLock 'net'; if (-not $l) { if ($Busy) { & $Busy | Out-Null }; $l = PctLock 'net' $Wait }; $l }
# Уведомления: выпуск кладёт notify.ps1 в helpers; старая установка — только guard\notify.ps1. Подключение: . (PctNotifyPath)
function PctNotifyPath { $n = "$(PctDir 'helpers')\notify.ps1"; if (Test-Path -LiteralPath $n) { $n } else { "$(PctDir 'guard')\notify.ps1" } }
# U1b: helpers\ и guard\ пишут только администраторы. Данные, которые пишут процессы без повышения, — reports\<имя>. Файл со старого места ($From) переношу при первом обращении:
# копия (новый файл берёт права reports\), затем удаление старого. Копия не вышла — путь старого места (там данные); её успел сделать другой процесс — новый
function PctData([string]$Name, [ValidateSet('helpers', 'guard')][string]$From) { $d = PctDir 'reports'; $p = "$d\$Name"; $o = "$(PctDir $From)\$Name"
  if (-not [IO.File]::Exists($p)) { try { [void][IO.Directory]::CreateDirectory($d) } catch {}; if ([IO.File]::Exists($o)) { try { [IO.File]::Copy($o, $p) } catch { if (-not [IO.File]::Exists($p)) { return $o } }; try { [IO.File]::Delete($o) } catch {} } }
  $p }
# Обновление от окна: задача PCT-Helper-Update-Now (наивысшие права, ставит U1b) — без вопроса UAC. Нет задачи — $false, окно запускает updater.ps1 само. PCT_UPDTASK_FAKE=<файл> — строка «run» вместо запуска, none — задачи нет
function PctUpdateTask { if ($env:PCT_UPDTASK_FAKE) { if ($env:PCT_UPDTASK_FAKE -eq 'none') { return $false }; Add-Content -LiteralPath $env:PCT_UPDTASK_FAKE 'run'; return $true }
  try { $s = New-Object -ComObject Schedule.Service; $s.Connect(); [void]$s.GetFolder('\').GetTask('PCT-Helper-Update-Now').Run($null); $true } catch { $false } }
function PctUnlock($L) { if ($L -and $L.M) { try { $L.M.ReleaseMutex() } catch {}; $L.M.Dispose(); $L.M = $null } }
# Папка reports\ — как PctRoot, но .NET: Split-Path и Join-Path грузят модуль (+180 мс на запуск сторожа)
function PctRepDir { "$(if ($env:PCT_ROOT) { $env:PCT_ROOT } elseif ([IO.Path]::GetFileName($PSScriptRoot) -eq 'helpers') { [IO.Path]::GetDirectoryName($PSScriptRoot) } else { 'C:\PC-Tweaks-Laptop' })\reports" }
# Нагрузка сторожа (GUARDS-CPU): PctCpu <задача> $PSCommandPath — в начале скрипта сторожа; итог по ходу — $global:PctCpuR = 'fix' | 'warn' | 'fail' | 'wait' (отложил до конца игры, PctGame; иначе ok).
# При выходе процесса — строка в reports\guards-cpu.log: «время запуска, задача, ЦП мс, пик памяти МБ, итог, длительность с[ game]» (game — дождался конца игры, PctGame). Только если скрипт — сам процесс задачи (-File <скрипт>):
# из окна (run.ps1) и из другого скрипта не пишу. Событие выхода, не try/finally: try вокруг скрипта обрывает его на ошибке метода, а без try он шёл дальше. Без командлетов (модуль — сотни мс ЦП)
# Сбой записи глотаю: дело сторож уже сделал. Больше 60 000 байт (~1200 строк) — оставляю 1000 последних: неделя для листа «Обслуживание» (GUARDS-SCENE-2), ~110 строк в сутки — 9 суток.
# Обрезка — под одним открытием файла (другой сторож ждёт). -Reports — папка журнала (updater.ps1 -Root)
function PctCpu([string]$Task, [string]$Script, [string]$Reports) { try { $c = [Environment]::CommandLine
    if (-not $Script -or ($c.IndexOf("-File `"$Script`"", [StringComparison]::OrdinalIgnoreCase) -lt 0 -and $c.IndexOf("-File $Script ", [StringComparison]::OrdinalIgnoreCase) -lt 0 -and -not $c.EndsWith("-File $Script", [StringComparison]::OrdinalIgnoreCase))) { return }
    if (-not $Reports) { $Reports = PctRepDir }
    $global:PctCpuF = "$Reports\guards-cpu.log"; $global:PctCpuT = $Task; $global:PctCpuR = 'ok'
    # действие — как можно меньше обращений к .NET: первое обращение PowerShell к свойству или методу стоит 3–14 мс
    [void]$ExecutionContext.Events.SubscribeEvent($null, $null, 'PowerShell.Exiting', $null, { try { $p = [Diagnostics.Process]::GetCurrentProcess(); $t = $p.StartTime; $f = $global:PctCpuF
        $l = "{0:yyyy-MM-dd HH\:mm} {1} {2:0} {3:0} {4} {5:0}{6}`n" -f $t, $global:PctCpuT, $p.TotalProcessorTime.TotalMilliseconds, ($p.PeakWorkingSet64 / 1048576), $global:PctCpuR, ([DateTime]::Now - $t).TotalSeconds, $global:PctCpuG
        for ($i = 0; ; $i++) { try { [IO.File]::AppendAllText($f, $l); break } catch { if ($i -ge 4) { throw }; [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($f)); [Threading.Thread]::Sleep(40) } }
        # Порог — по байтам: файл читаю только для обрезки (~раз в 200 запусков), а не на каждом запуске. Обрезка — под замком (FileShare.None): другой сторож ждёт, его строка не теряется
        if ([IO.FileInfo]::new($f).Length -gt 60000) { $s = [IO.File]::Open($f, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
          try { $b = [byte[]]::new($s.Length); $n = 0; while ($n -lt $b.Length) { $n += $s.Read($b, $n, $b.Length - $n) }
            $a = [Text.Encoding]::UTF8.GetString($b).Split([char[]]"`n", [StringSplitOptions]::RemoveEmptyEntries)
            if ($a.Count -gt 1000) { $o = [Text.Encoding]::UTF8.GetBytes([string]::Join("`n", $a, $a.Count - 1000, 1000) + "`n"); $s.SetLength(0); $s.Write($o, 0, $o.Length) } } finally { $s.Dispose() } } } catch {} }, $false, $false) } catch {} }
# Полный экран (GUARDS-GAME): SHQueryUserNotificationState (shell32) — 2 приложение на весь экран, 3 игра Direct3D на весь экран, 4 показ презентации → $true; ошибка — $false (не ждать)
# Без компиляции (Add-Type — ~350 мс на запуск): готовый класс PctFull из Pomoshnik.exe рядом, сборка из байтов (файл не занят — обновление его заменит); нет exe или класса — P/Invoke через Reflection.Emit (~50 мс)
# Тип — в $global:PctFullT: следующая проверка того же процесса ~0 мс. Стенд: PCT_GAME_FAKE=<файл> — файл есть = полный экран; каждый вызов — строка в <файл>.n (тест: настройка выключена — вызовов нет)
function PctFull { if ($env:PCT_GAME_FAKE) { try { [IO.File]::AppendAllText("$env:PCT_GAME_FAKE.n", "1`n") } catch {}; return [IO.File]::Exists($env:PCT_GAME_FAKE) }
  try { if (-not $global:PctFullT) { $e = "$PSScriptRoot\Pomoshnik.exe"; $t = $null
      if ([IO.File]::Exists($e)) { try { $t = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($e)).GetType('PctFull') } catch {} }
      if (-not $t) { $b = [AppDomain]::CurrentDomain.DefineDynamicAssembly([Reflection.AssemblyName]::new('PctFullE'), [Reflection.Emit.AssemblyBuilderAccess]::Run).DefineDynamicModule('PctFullE').DefineType('PctFullE', [Reflection.TypeAttributes]385)
        # Public, Static, PinvokeImpl; Standard; Winapi; Unicode; PreserveSig — числами: перевод строки в перечисление стоит PowerShell лишних мс
        $b.DefinePInvokeMethod('SHQueryUserNotificationState', 'shell32.dll', [Reflection.MethodAttributes]8214, [Reflection.CallingConventions]1, [int], [Type[]]@([int].MakeByRefType()), [Runtime.InteropServices.CallingConvention]1, [Runtime.InteropServices.CharSet]3).SetImplementationFlags([Reflection.MethodImplAttributes]128); $t = $b.CreateType() }
      $global:PctFullT = $t }
    $s = 0; if ($global:PctFullT::SHQueryUserNotificationState([ref]$s) -ne 0) { return $false }; $s -ge 2 -and $s -le 4 } catch { $false } }
# «Ждать конца игры» (GUARDS-GAME): плановый сторож ждёт, пока игра или фильм на весь экран. Настройка — файл reports\guards-game.on: ставит guards-game.ps1 из окна без повышения,
# сторож от человека и с повышением читает тот же файл (без разбора JSON — модуль стоил бы сотни мс). Выключена — только проверка файла, PctFull не зову. Выключили во время ожидания — дальше сразу.
# Полный экран — сон, проверка раз в 60 с до $Max с (меньше ExecutionTimeLimit задачи, с запасом на само дело). Дождался — $true, в guards-cpu.log пометка game; предел вышел — $false и итог wait:
# сторож выходит как обычно, дело сделает следующий запуск по расписанию. -Bg — фоновое дело окна (шаг «Жду конца игры»). -Reports — как у PctCpu. Стенд: PCT_GAME_STEP, PCT_GAME_MAX — шаг и предел, с
# Параметры без типов: первый вызов функции с [int]/[string] стоит PowerShell ~8 мс, а выключенная настройка должна стоить ~0
function PctGame($Max, $Reports, $Bg) { if (-not $Reports) { $Reports = PctRepDir }; if (-not [IO.File]::Exists("$Reports\guards-game.on") -or -not (PctFull)) { return $true }; PctGameWait $Max "$Reports\guards-game.on" $Bg }
# Ожидание — отдельной функцией: её тело PowerShell разбирает только при игре на весь экран
function PctGameWait($Max, $on, $Bg) { $st = 60; if ($env:PCT_GAME_STEP) { $st = [int]$env:PCT_GAME_STEP }; if ($env:PCT_GAME_MAX) { $Max = [int]$env:PCT_GAME_MAX }
  if ($Bg) { PctBg $Bg 'Жду конца игры' 'Проверю сразу после' }; $t0 = [DateTime]::Now
  while (($left = $Max - ([DateTime]::Now - $t0).TotalSeconds) -gt 0) { [Threading.Thread]::Sleep([int](1000 * [Math]::Min($st, $left)))
    if (-not [IO.File]::Exists($on)) { return $true }; if (-not (PctFull)) { $global:PctCpuG = ' game'; return $true } }
  $global:PctCpuR = 'wait'; if ($Bg) { PctBg $Bg -End 'отложил до конца игры' }; $false }
# Профиль: %LOCALAPPDATA%\Pomoshnik\profile.json. PctProfile — объект или $null (нет файла, битый JSON)
function PctProfilePath { Join-Path $env:LOCALAPPDATA 'Pomoshnik\profile.json' }
function PctProfile { try { $o = [IO.File]::ReadAllText((PctProfilePath)) | ConvertFrom-Json -ErrorAction Stop; if ($o -is [Management.Automation.PSCustomObject]) { $o } } catch {} }
function PctProfileLog([string]$Text) { try { $d = PctDir 'reports'; [void][IO.Directory]::CreateDirectory($d)
  [IO.File]::AppendAllText("$d\profile.log", "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Text`n", (New-Object Text.UTF8Encoding $false)) } catch {} }
# Запись: временный файл → замена (прошлый → profile.prev.json), UTF-8 без BOM. Сбой — исключение
function PctProfileSave($Obj) { $p = PctProfilePath; $d = Split-Path $p; [void][IO.Directory]::CreateDirectory($d); $t = "$p.tmp"
  [IO.File]::WriteAllText($t, ($Obj | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
  if ([IO.File]::Exists($p)) { [IO.File]::Replace($t, $p, "$d\profile.prev.json") } else { [IO.File]::Move($t, $p) } }
# Прежняя установка без профиля: собрать его из файлов корня (только пути и флаги). Профиль есть, даже битый, — не трогать
function PctMigrate { $p = PctProfilePath
  if ([IO.File]::Exists($p)) { if (-not (PctProfile)) { PctProfileLog "профиль не читается, работаю без него: $p" }; return }
  $r = PctRoot; if (-not (Test-Path -LiteralPath $r)) { return }; $Hd = PctDir 'helpers'
  PctProfileLog "начинаю: собираю профиль из $r"
  $zc = "$Hd\zapret-cmd.txt"; $z = Test-Path -LiteralPath $zc; $pac = Test-Path -LiteralPath (PctData 'smart-proxy-on.txt' 'helpers')
  $ad = "$(Get-Content -LiteralPath "$Hd\anydesk-path.txt" -Encoding UTF8 -TotalCount 1 -ErrorAction SilentlyContinue)"
  $ad = [bool](@($ad, "${env:ProgramFiles(x86)}\AnyDesk\AnyDesk.exe", "$env:ProgramFiles\AnyDesk\AnyDesk.exe") | Where-Object { $_ -and (Test-Path -LiteralPath $_) }) -or [bool](Get-Process AnyDesk -ErrorAction SilentlyContinue)
  $happ = (Test-Path -LiteralPath 'D:\Happ') -or [bool](Get-Process Happ -ErrorAction SilentlyContinue)
  $yn = { param($v) if ($v) { 'да' } else { 'нет' } }
  PctProfileLog "нашёл: обход=$(& $yn $z), прокси=$(& $yn $pac), Happ=$(& $yn $happ), AnyDesk=$(& $yn $ad)"
  try { PctProfileSave ([ordered]@{ schema = 1; created = (Get-Date).ToString('o'); source = 'migrate'; legacyRoot = $r
    modules = [ordered]@{ core = $true; pc = $true; ru = ($z -or $pac) }
    vpn = [ordered]@{ client = $(if ($happ) { 'Happ' } else { '' }); socks = (PctSocks); pac = $pac }
    sites = [ordered]@{ file = (PctData 'proxy-sites.txt' 'helpers') }; zapret = [ordered]@{ cmdFile = $(if ($z) { $zc } else { '' }) }
    help = [ordered]@{ kind = $(if ($ad) { 'anydesk' } else { '' }); enabled = $ad } }) } catch { PctProfileLog "не сохранил: $($_.Exception.Message)"; throw }
  PctProfileLog "сохранил профиль: $(PctProfilePath)"
  $f = @(if ($z) { 'обход' }; if ($pac) { 'прокси' }; if ($happ) { 'Happ' })
  if ($f) { 'Собрал профиль из твоих настроек: ' + ($f -join ', ') } else { 'Собрал профиль из твоих настроек' } }

# ---------- Питание (energy.ps1): тип устройства, настройки схем powercfg, устройства, бэкап и откат ----------
# PCT_ENERGY_FAKE=<файл JSON> — подмена для проверки: laptop, ms, ac; active — GUID копии схемы (не настоящей активной); balanced — копия в роли «Сбалансированной»; hp — схема вместо «Высокой производительности» (GUID, которого нет, — схемы нет);
# overlay; wifi; devices [{id, name, kind, enable, stuck — запись «удалась», но Windows не меняет}]; nics [{adapter, kw, name, val}]; vendors. С подменой схемы читаю и пишу по-настоящему (только копии), остальное — в этом файле
function PctEnFake { if ($env:PCT_ENERGY_FAKE) { [IO.File]::ReadAllText($env:PCT_ENERGY_FAKE) | ConvertFrom-Json } }
function PctEnFakeSave($F) { [IO.File]::WriteAllText($env:PCT_ENERGY_FAKE, ($F | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false)) }
# Схемы Windows: сбалансированная, высокая производительность, экономия, максимальная производительность (и подменённая «Сбалансированная»). Их не удаляю никогда
function PctEnBuiltIn { $f = PctEnFake; @('381b4222-f694-41f0-9685-ff5bb260df2e', '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c', 'a1841308-3541-4fab-bc81-f71556f20b4a', 'e9a42b02-d5df-448d-aa00-03f14749eb61') + @(if ($f -and $f.balanced) { "$($f.balanced)" }) }
# Настройки: подгруппа, настройка, значение «без экономии» (сверено с powercfg /qh 29.10)
function PctEnKeys { [ordered]@{
  usb = @('2a737441-1930-4402-8d77-b2bebba308a3', '48e6b7a6-50f5-4782-a5d4-53bb8f07e226', 0)      # выборочная приостановка USB: 0 — выкл
  aspm = @('501a4d13-42af-4429-9fd1-a8218c268e20', 'ee12f906-d277-404b-b6da-e5fa1a576df5', 0)     # ASPM PCI Express: 0 — выкл
  disk = @('0012ee47-9041-4b5d-9b77-535fba8b1442', '6738e2c4-e8a5-4a42-b16a-e040e769756e', 0)     # отключать диск через, с: 0 — никогда
  wifi = @('19cbb8fa-5279-450e-9fac-8a3d5fedd0c1', '12bbebe6-58d6-4636-95bb-3217ef867c1a', 0)     # Wi-Fi: 0 — максимальная производительность
  sleep = @('238c9fa8-0aad-41ed-83f4-97be242c8f20', '29f6c1db-86da-48c5-9fdb-f2b67b1f44da', 0)    # сон через, с: 0 — никогда
  video = @('7516b95f-f776-4464-8c53-06167f40cc99', '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e', 0)    # отключать экран через, с: 0 — никогда
  cpumin = @('54533251-82be-4824-96c1-47b60b740d00', '893dee8e-2bef-41e0-89c6-b55d0929964c', 5) } } # минимум процессора, %: 5 — как в «Сбалансированной»
# Modern Standby по выводу powercfg /a: строка с S0 в отступе 4 пробела — состояние; под недоступным идёт причина с большим отступом (таб). Язык Windows не важен
function PctEnMS([string[]]$Lines) { for ($i = 0; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -match '^ {4}\S.*S0') { $n = $(if ($i + 1 -lt $Lines.Count) { $Lines[$i + 1] } else { '' }); if ($n -notmatch '^(\t| {5,})\S') { return $true } } }; $false }
# Тип: Laptop — есть батарея; MS — Modern Standby; AC — от сети (BatteryStatus 2 — сеть, 3 — заряжена, 6–9 — заряжается)
function PctEnDevice { $f = PctEnFake; if ($f) { return [pscustomobject]@{ Laptop = [bool]$f.laptop; MS = [bool]$f.ms; AC = [bool]$f.ac } }
  $b = @(Get-CimInstance Win32_Battery); [pscustomobject]@{ Laptop = [bool]$b; MS = (PctEnMS @(powercfg /a)); AC = (-not $b) -or [bool]($b | Where-Object { $_.BatteryStatus -in 2, 3, 6, 7, 8, 9 }) } }
function PctEnSchemes { @(powercfg /list) | ForEach-Object { if ($_ -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\s+\((.*)\)') { [pscustomobject]@{ G = $Matches[1]; N = $Matches[2] } } } }
function PctEnActive { $f = PctEnFake; if ($f) { return "$($f.active)" }; if ("$(powercfg /getactivescheme)" -match '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}') { $Matches[0] } }
# Включить схему; та же схема — применить её изменённые настройки
function PctEnSetActive([string]$G) { $f = PctEnFake; if ($f) { $f.active = $G; PctEnFakeSave $f; return $true }; $null = powercfg /setactive $G 2>&1; -not $LASTEXITCODE }
# Значение настройки: AC (от сети) и DC (от батареи) — два последних 0x… в выводе /qh; нет настройки — $null
function PctEnGet([string]$Scheme, [string]$Key) { $k = (PctEnKeys)[$Key]; $o = @(powercfg /qh $Scheme $k[0] $k[1] 2>$null); if ($LASTEXITCODE) { return }
  $h = @($o | ForEach-Object { if ($_ -match ':\s*0x([0-9a-fA-F]+)\s*$') { [Convert]::ToInt64($Matches[1], 16) } }); if ($h.Count -ge 2) { [pscustomobject]@{ AC = $h[-2]; DC = $h[-1] } } }
function PctEnSet([string]$Scheme, [string]$Key, [ValidateSet('AC', 'DC')][string]$Src, [long]$V) { $k = (PctEnKeys)[$Key]; $c = $(if ($Src -eq 'AC') { '/setacvalueindex' } else { '/setdcvalueindex' })
  $null = powercfg $c $Scheme $k[0] $k[1] $V 2>&1; -not $LASTEXITCODE }
# Схема есть в Windows (её можно скопировать): powercfg /qh читает минимум процессора без ошибки. Прав не нужно
function PctEnHas([string]$G) { if (-not $G) { return $false }; $k = (PctEnKeys)['cpumin']; $null = powercfg /qh $G $k[0] $k[1] 2>&1; -not $LASTEXITCODE }
# Копия схемы с новым именем → GUID копии или $null (схемы нет в Windows)
function PctEnCopy([string]$Base, [string]$Name) { $o = "$(powercfg /duplicatescheme $Base 2>&1)"; if ($LASTEXITCODE -or $o -notmatch '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}') { return }
  $g = $Matches[0]; $null = powercfg /changename $g $Name 2>&1; $g }
# Удалить только свою копию: схемы Windows и активную (настоящую и подменённую) — никогда
function PctEnDelete([string]$G) { if (-not $G -or $G -in (PctEnBuiltIn)) { return $false }
  $real = $(if ("$(powercfg /getactivescheme)" -match '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}') { $Matches[0] }); if ($G -eq $real -or $G -eq (PctEnActive)) { return $false }
  $null = powercfg /delete $G 2>&1; -not $LASTEXITCODE }
# Ползунок режима питания (работает при сбалансированной схеме). Ставлю и читаю только от сети: powercfg /overlaysetactive меняет режим для текущего питания
function PctEnOverlay { $f = PctEnFake; if ($f) { return "$($f.overlay)" }
  $v = "$((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes').ActiveOverlayAcPowerScheme)"; if ($v) { $v } else { '00000000-0000-0000-0000-000000000000' } }
function PctEnOverlaySet([string]$G) { $f = PctEnFake; if ($f) { $f.overlay = $G; PctEnFakeSave $f; return $true }; $null = powercfg /overlaysetactive $G 2>&1; -not $LASTEXITCODE }
# «Разрешить отключение этого устройства» (MSPower_DeviceEnable): kind hub — USB-концентраторы, input — мышь, клавиатура, устройства ввода USB, net — сетевые карты
function PctEnDevices { $f = PctEnFake; if ($f) { return @($f.devices | ForEach-Object { [pscustomobject]@{ Id = $_.id; N = $_.name; K = $_.kind; On = [bool]$_.enable } }) }
  $pn = @{}; foreach ($p in @(Get-CimInstance Win32_PnPEntity -Property PNPDeviceID, Name, PNPClass, Service)) { if ($p.PNPDeviceID) { $pn[$p.PNPDeviceID] = $p } }
  foreach ($m in @(Get-CimInstance -Namespace root\wmi MSPower_DeviceEnable)) { $id = $m.InstanceName -replace '_\d+$'; $p = $pn[$id]; if (-not $p) { continue }
    $k = $(if ($p.PNPClass -eq 'USB' -and $p.Service -match '^usbhub3?$') { 'hub' } elseif ($p.PNPClass -in 'Mouse', 'Keyboard' -or ($p.PNPClass -eq 'HIDClass' -and $p.Service -eq 'HidUsb')) { 'input' } elseif ($p.PNPClass -eq 'Net' -and $id -match '^(PCI|USB)\\') { 'net' })
    if ($k) { [pscustomobject]@{ Id = $m.InstanceName; N = $p.Name; K = $k; On = [bool]$m.Enable } } } }
function PctEnDeviceSet([string]$Id, [bool]$On) { $f = PctEnFake
  if ($f) { $d = @($f.devices | Where-Object { $_.id -eq $Id }); if (-not $d) { return $false }; if (-not $d[0].stuck) { $d[0].enable = $On; PctEnFakeSave $f }; return $true }
  try { $m = @(Get-CimInstance -Namespace root\wmi MSPower_DeviceEnable -ErrorAction Stop | Where-Object { $_.InstanceName -eq $Id }); if (-not $m) { return $false }; Set-CimInstance -InputObject $m[0] -Property @{ Enable = $On } -ErrorAction Stop; $true } catch { $false } }
# Энергосбережение проводной сетевой карты (EEE, Green Ethernet): свойство, где «0» — выкл
function PctEnNics { $f = PctEnFake; if ($f) { return @($f.nics | ForEach-Object { [pscustomobject]@{ A = $_.adapter; Kw = $_.kw; N = $_.name; V = "$($_.val)" } }) }
  foreach ($a in @(Get-NetAdapter -Physical | Where-Object { $_.NdisPhysicalMedium -eq 14 })) {
    foreach ($p in @(Get-NetAdapterAdvancedProperty -Name $a.Name -AllProperties | Where-Object { $_.RegistryKeyword -match '^(\*EEE|AdvancedEEE|EEELinkAdvertisement|EnableGreenEthernet|GreenEthernet)$' -and $_.DisplayName -and @($_.ValidRegistryValues) -contains '0' })) {
      [pscustomobject]@{ A = $a.Name; Kw = $p.RegistryKeyword; N = $p.DisplayName; V = "$(@($p.RegistryValue)[0])" } } } }
function PctEnNicSet([string]$A, [string]$Kw, [string]$V) { $f = PctEnFake
  if ($f) { $n = @($f.nics | Where-Object { $_.adapter -eq $A -and $_.kw -eq $Kw }); if (-not $n) { return $false }; $n[0].val = $V; PctEnFakeSave $f; return $true }
  try { Set-NetAdapterAdvancedProperty -Name $A -RegistryKeyword $Kw -RegistryValue $V -ErrorAction Stop; $true } catch { $false } }
# Бэкап: %LOCALAPPDATA%\Pomoshnik\energy-backup.json — схема до (active), копия Помощника (copy), ползунок до (overlay), старые значения (values, devices, nics).
# Повторный запуск дописывает, первое старое значение не перезаписывает. Файл схемы до — powercfg /export (export), для ручного возврата
function PctEnBackupPath { Join-Path $env:LOCALAPPDATA 'Pomoshnik\energy-backup.json' }
function PctEnBackup { try { $o = [IO.File]::ReadAllText((PctEnBackupPath)) | ConvertFrom-Json -ErrorAction Stop; if ($o -is [Management.Automation.PSCustomObject]) { $o } } catch {} }
function PctEnBackupSave($B) { $p = PctEnBackupPath; [void][IO.Directory]::CreateDirectory((Split-Path $p)); $t = "$p.tmp"
  [IO.File]::WriteAllText($t, ($B | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false)); if ([IO.File]::Exists($p)) { [IO.File]::Replace($t, $p, [NullString]::Value) } else { [IO.File]::Move($t, $p) } }
# Начать или продолжить бэкап: новый — с экспортом активной схемы
function PctEnBackupStart([string]$Active, [string]$Name) { $b = PctEnBackup; if ($b) { return $b }; $d = Split-Path (PctEnBackupPath); [void][IO.Directory]::CreateDirectory($d)
  $x = "$d\energy-$(Get-Date -Format 'yyyyMMdd-HHmmss').pow"; $null = powercfg /export $x $Active 2>&1; if ($LASTEXITCODE) { $x = '' }
  $b = [pscustomobject]@{ schema = 1; created = (Get-Date).ToString('s'); active = $Active; activeName = $Name; export = $x; copy = ''; overlay = ''; values = @(); devices = @(); nics = @() }; PctEnBackupSave $b; $b }
# Запомнить старое значение, если такого ещё нет (ключ — поля Key), и сразу сохранить
function PctEnRemember($B, [string]$List, $Item, [string[]]$Key) { foreach ($x in @($B.$List)) { $same = $true; foreach ($k in $Key) { if ("$($x.$k)" -ne "$($Item.$k)") { $same = $false } }; if ($same) { return } }
  $B.$List = @(@($B.$List) + $Item); PctEnBackupSave $B }
# Откат по бэкапу: сеть, устройства, значения схем, ползунок, схема до, удаление копии. Всё вернул — бэкап в energy-backup.<время>.done.json; нет — в бэкапе остаётся невозвращённое.
# → Ok — сколько вернул, Bad — что не вернул; $null — бэкапа нет
function PctEnUndo { $b = PctEnBackup; if (-not $b) { return }; $bad = New-Object Collections.ArrayList; $ok = 0
  $k = @(); foreach ($x in @($b.nics)) { if (PctEnNicSet $x.adapter $x.kw $x.old) { $ok++ } else { $k += $x; [void]$bad.Add("сетевая карта $($x.adapter): $($x.name)") } }; $b.nics = $k
  $k = @(); foreach ($x in @($b.devices)) { if (PctEnDeviceSet $x.id ([bool]$x.old)) { $ok++ } else { $k += $x; [void]$bad.Add("устройство: $($x.name)") } }; $b.devices = $k
  $act = PctEnActive; $re = $false
  $k = @(); foreach ($x in @($b.values)) { if ($b.copy -and $x.scheme -eq $b.copy) { $ok++; continue }
    if (PctEnSet $x.scheme $x.key $x.src $x.old) { $ok++; if ($x.scheme -eq $act) { $re = $true } } else { $k += $x; [void]$bad.Add("настройка схемы: $($x.key)") } }; $b.values = $k
  if ($re) { [void](PctEnSetActive $act) }
  if ($b.overlay) { if ((PctEnDevice).AC -and (PctEnOverlaySet $b.overlay)) { $b.overlay = ''; $ok++ } else { [void]$bad.Add('режим питания: нужна зарядка') } }
  if ($b.copy) { $sw = $true; if ((PctEnActive) -eq $b.copy) { $sw = PctEnSetActive $b.active }
    if (-not $sw) { [void]$bad.Add('схема питания: не включилась прежняя') } elseif (PctEnDelete $b.copy) { $b.copy = ''; $ok++ } else { [void]$bad.Add('копия схемы: не удалилась') } }
  if ($bad.Count) { PctEnBackupSave $b } else { PctEnBackupDone }
  [pscustomobject]@{ Ok = $ok; Bad = @($bad) } }
function PctEnBackupDone { $p = PctEnBackupPath; $t = Get-Date -Format 'yyyyMMdd-HHmmss-fff'; $a = $p -replace '\.json$', ".$t.done.json"; for ($i = 1; [IO.File]::Exists($a); $i++) { $a = $p -replace '\.json$', ".$t-$i.done.json" }; [IO.File]::Move($p, $a) }
# Возврат по журналу (PctUndoOne): тот же пункт убираю из energy-backup.json, иначе «Вернуть как было» в самом «Энергосбережении» вернуло бы его второй раз. Бэкап опустел — закрыт (.done.json)
function PctEnForget($X) { $b = PctEnBackup; if (-not $b) { return }
  switch ($X.kind) { 'power-value' { $b.values = @($b.values | Where-Object { -not ($_.scheme -eq $X.scheme -and $_.key -eq $X.key -and $_.src -eq $X.src) }) }
    'power-copy' { if ($b.copy -eq $X.copy) { $b.copy = '' }; $b.values = @($b.values | Where-Object { $_.scheme -ne $X.copy }) } 'power-overlay' { $b.overlay = '' }
    'power-device' { $b.devices = @($b.devices | Where-Object { $_.id -ne $X.id }) } 'power-nic' { $b.nics = @($b.nics | Where-Object { -not ($_.adapter -eq $X.adapter -and $_.kw -eq $X.kw) }) } default { return } }
  if (@($b.values).Count + @($b.devices).Count + @($b.nics).Count -or $b.copy -or $b.overlay) { PctEnBackupSave $b } else { PctEnBackupDone } }

# ---------- Мышь и тачпад (mouse.ps1): что подключено, разбор замера, повышенная точность указателя, бэкап и откат ----------
# PCT_MOUSE_FAKE=<файл JSON> — подмена для проверки: laptop, ms, ac; pointers [{id, name, kind mouse|touchpad|tablet, bus usb|radio|bt|ps2|i2c|virtual, precision}]; accel [порог1, порог2, ускорение]; reg {MouseThreshold1, MouseThreshold2, MouseSpeed};
# devices — как в PCT_ENERGY_FAKE (mouse.ps1 с подменой ставит PCT_ENERGY_FAKE на тот же файл: запрет отключения — функциями PctEnDevices/PctEnDeviceSet); vendors
function PctMsFake { if ($env:PCT_MOUSE_FAKE) { [IO.File]::ReadAllText($env:PCT_MOUSE_FAKE) | ConvertFrom-Json } }
function PctMsFakeSave($F) { [IO.File]::WriteAllText($env:PCT_MOUSE_FAKE, ($F | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false)) }
# Ключ устройства по коду: «VID&PID» (USB; Bluetooth — VID&0002xxxx_PID&xxxx) или «VEN&DEV» (I2C); нет — путь без \\?\ и {класса}. По нему сверяю мышь из Windows, замер и «Разрешить отключение»
function PctMsKey([string]$Id) { if ($Id -match '(?:VID|VEN)[_&](?:000[12])?([0-9A-Za-z]{4})[&_](?:PID|DEV)[_&]([0-9A-Za-z]{4})') { "$($Matches[1])&$($Matches[2])".ToUpper() } else { ($Id -replace '^\\\\\?\\' -replace '#\{[^}]*\}$' -replace '#', '\').ToUpper() } }
# Права администратора (PCT_ADMIN_FAKE=1/0 — подмена для проверки)
function PctIsAdmin { if ($env:PCT_ADMIN_FAKE) { return $env:PCT_ADMIN_FAKE -eq '1' }; ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
# Мышь и тачпад из Win32_PointingDevice. Kind: touchpad — Precision (у того же родителя коллекция HID 0x0D/0x05) или по имени и коду; Bus: virtual — не настоящее устройство (фирменная программа),
# bt — Bluetooth, radio — приёмник 2,4 ГГц (по названию от устройства: Receiver, Wireless, Lightspeed…), usb, i2c, ps2. N — название от устройства, без серийного номера
function PctMsDevices { $f = PctMsFake; if ($f) { return @($f.pointers | ForEach-Object { [pscustomobject]@{ Id = $_.id; N = $_.name; Kind = $_.kind; Bus = $_.bus; Ptp = [bool]$_.precision; Kbd = [bool]$_.kbd } }) }
  $pt = @(Get-CimInstance Win32_PointingDevice | Where-Object { $_.PNPDeviceID }); if (-not $pt) { return }
  # Get-PnpDeviceProperty со списком устройств повторяет ответ первого — по одному
  $pr = { param($i, $k) "$((Get-PnpDeviceProperty -InstanceId $i -KeyName $k -ErrorAction SilentlyContinue).Data)" }
  $ptp = @{}; foreach ($x in @(Get-CimInstance Win32_PnPEntity -Filter "PNPClass='HIDClass'" | Where-Object { "$($_.CompatibleID)" -match 'HID_DEVICE_UP:000D_U:0005' })) { $ptp[(& $pr $x.PNPDeviceID 'DEVPKEY_Device_Parent')] = $true }
  # Клавиатура с функциями мыши (Wooting и подобные): у мыши и клавиатуры один родитель
  $kbp = @{}; foreach ($x in @(Get-CimInstance Win32_PnPEntity -Filter "PNPClass='Keyboard'")) { $kbp[(& $pr $x.PNPDeviceID 'DEVPKEY_Device_Parent')] = $true }
  $bat = [bool](Get-CimInstance Win32_Battery | Select-Object -First 1); $reg = Test-Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad'
  foreach ($p in $pt) { $id = $p.PNPDeviceID; $pa = & $pr $id 'DEVPKEY_Device_Parent'; $n = $(if ($pa) { & $pr $pa 'DEVPKEY_Device_BusReportedDeviceDesc' }); if (-not $n) { $n = "$($p.Name)" }
    PctMsClassify $id $pa $n ([bool]$ptp[$pa]) $bat $reg ([bool]$kbp[$pa]) } }
# Вид и шина одного указателя по коду, родителю и названию (чистая функция — тест подаёт данные ноутбука). tablet — драйвер графического планшета (ROOT\HIDCLASS, PENTABLET/WACOM/XP-PEN): не мышь, не мерю.
# touchpad: Precision-коллекция, имя, код ACPI\SYN|ELAN|ETD|ALP|DLL|GXTP (у себя или у родителя) или родитель ACPI\ (I2C HID) на устройстве с батареей. Precision — коллекция HID 0x0D или ключ PrecisionTouchPad в HKCU
function PctMsClassify([string]$Id, [string]$Pa, [string]$N, [bool]$PtpHid, [bool]$Battery, [bool]$PtpReg, [bool]$KbdParent) { $all = "$Id $Pa"
  if ($Pa -match '^ROOT\\HIDCLASS' -and $all -match '(?i)PENTABLET|WACOM|XP-?PEN') { return [pscustomobject]@{ Id = $Id; N = 'графический планшет (драйвер)'; Kind = 'tablet'; Bus = 'driver'; Ptp = $false; Kbd = $false } }
  $tp = $PtpHid -or $N -match '(?i)touch ?pad|тачпад|сенсорн' -or $all -match '(?i)(^|\s)ACPI\\(SYN|ELAN|ETD|ALP|DLL|GXTP)' -or ($Pa -match '^ACPI\\' -and $Id -match '^HID\\' -and $Battery)
  $bus = $(if ($Pa -and $Pa -notmatch '^(USB|ACPI|HID|BTHENUM|BTHLEDEVICE|BTHLE)\\') { 'virtual' } elseif ($all -match '(?i)00001124-0000-1000-8000-00805F9B34FB|00001812-0000-1000-8000-00805F9B34FB|(^|\s)BTH') { 'bt' }
    elseif ($Id -match '^ACPI\\') { 'ps2' } elseif ($Pa -match '^ACPI\\') { 'i2c' } elseif ($N -match '(?i)receiver|wireless|dongle|2\.4|lightspeed|unifying|bolt|nano|приёмник|беспровод') { 'radio' } else { 'usb' })
  if ($tp -and $bus -ne 'virtual' -and (-not $N -or $N -match '(?i)^HID|совместим')) { $N = 'Тачпад' }
  [pscustomobject]@{ Id = $Id; N = $N; Kind = $(if ($tp) { 'touchpad' } else { 'mouse' }); Bus = $bus; Ptp = $($PtpHid -or ($tp -and $PtpReg)); Kbd = [bool]($KbdParent -and -not $tp) } }
# Название для человека: мышь — от устройства, клавиатура с мышью — так и называю, тачпад — «тачпад»; нет в списке Windows — вид
function PctMsName($X) { $p = $X.Ptr; if ($X.Kind -eq 'touchpad') { return 'тачпад' }
  if ($p -and $p.Kbd) { return $(if ($p.N) { "клавиатура с функциями мыши «$($p.N)»" } else { 'клавиатура с функциями мыши' }) }; if ($p -and $p.N) { "$($p.N)" } else { 'мышь' } }
# Что показать человеку: движение без имени устройства (синтетическое) — только в журнал
function PctMsShown($G) { @($G | Where-Object { $_.Key }) }
function PctMsSum($G) { if (-not $G) { return 'замер не получился' }; @($G | ForEach-Object { "$(PctMsName $_) — $($_.S.Hz) Гц" }) -join ', ' }
# Разбор замера одного устройства: времена событий движения, мкс по возрастанию → Hz — медиана частоты по окнам 100 мс (в окне ≥ 3 событий: (n − 1) / (последнее − первое)), Sp — разброс окон (10–90 %, Гц),
# Gap — пропуски: интервал длиннее 3 медианных, но короче 100 мс (дольше — рука остановилась), Win — окон, N — событий. Меньше 5 окон (полсекунды движения) — $null: замер не получился
function PctMsStats([double[]]$T) { if (-not $T -or $T.Count -lt 10) { return }; $r = New-Object Collections.ArrayList; $i = 0
  while ($i -lt $T.Count) { $w = [math]::Floor($T[$i] / 100000); $j = $i; while ($j + 1 -lt $T.Count -and [math]::Floor($T[$j + 1] / 100000) -eq $w) { $j++ }
    if ($j - $i -ge 2 -and $T[$j] -gt $T[$i]) { [void]$r.Add(($j - $i) * 1e6 / ($T[$j] - $T[$i])) }; $i = $j + 1 }
  if ($r.Count -lt 5) { return }; $s = @($r | Sort-Object); $hz = $s[[int][math]::Floor($s.Count / 2)]; $lim = 3e6 / $hz; $g = 0
  for ($k = 1; $k -lt $T.Count; $k++) { $d = $T[$k] - $T[$k - 1]; if ($d -gt $lim -and $d -lt 100000) { $g++ } }
  [pscustomobject]@{ Hz = [math]::Round($hz); Sp = [math]::Round($s[[int][math]::Floor(0.9 * ($s.Count - 1))] - $s[[int][math]::Floor(0.1 * ($s.Count - 1))]); Gap = $g; Win = $s.Count; N = $T.Count } }
# Замер по устройствам: события Raw Input (время, мкс; номер источника), источники (путь HID; вид 0 — мышь, 1 — тачпад HID 0x0D), мышь и тачпад из PctMsDevices → [{Key, Kind, Ptr, S — PctMsStats}] только с удачным разбором.
# Источники одного устройства (несколько коллекций) — вместе. Мышь без имени (синтетическое движение; тачпад Precision двигает указатель так же) не считаю, если в замере есть тачпад HID
function PctMsGroups([double[]]$Times, [int[]]$Devs, [string[]]$Names, [int[]]$Kinds, $Ptrs) { $g = [ordered]@{}; $tpHid = $false
  for ($i = 0; $i -lt $Names.Count; $i++) { if ($Kinds[$i] -eq 1 -and $Devs -contains $i) { $tpHid = $true } }
  for ($i = 0; $i -lt $Names.Count; $i++) { if ($Kinds[$i] -eq 0 -and -not $Names[$i] -and $tpHid) { continue }
    $k = $(if ($Names[$i]) { PctMsKey $Names[$i] } else { '' }); $p = @($Ptrs | Where-Object { $k -and (PctMsKey $_.Id) -eq $k })[0]; if ($p -and $p.Kind -eq 'tablet') { continue }
    $kd = $(if ($Kinds[$i] -eq 1 -or ($p -and $p.Kind -eq 'touchpad')) { 'touchpad' } else { 'mouse' }); $gk = "$kd|$k"
    if (-not $g.Contains($gk)) { $g[$gk] = [pscustomobject]@{ Key = $k; Kind = $kd; Ptr = $p; T = New-Object Collections.Generic.List[double] } }
    for ($j = 0; $j -lt $Devs.Count; $j++) { if ($Devs[$j] -eq $i) { $g[$gk].T.Add($Times[$j]) } } }
  foreach ($x in $g.Values) { $s = PctMsStats @($x.T | Sort-Object); if ($s) { [pscustomobject]@{ Key = $x.Key; Kind = $x.Kind; Ptr = $x.Ptr; S = $s } } } }
# Повышенная точность указателя: SPI_GETMOUSE → порог1, порог2, ускорение (брать через @()); включена — ускорение не 0 (Windows: вкл 6, 10, 1; выкл 0, 0, 0). Запись — SPI_SETMOUSE с записью в профиль и рассылкой,
# и те же значения в HKCU\Control Panel\Mouse (MouseThreshold1, MouseThreshold2, MouseSpeed). Скорость указателя не трогаю
function PctMsSpi { if (-not ('Pct.MsSpi' -as [type])) { Add-Type -Namespace Pct -Name MsSpi -MemberDefinition '[DllImport("user32.dll", SetLastError = true)] public static extern bool SystemParametersInfo(uint a, uint b, int[] c, uint d);' } }
function PctMsAccel { $f = PctMsFake; if ($f) { return @($f.accel | ForEach-Object { [int]$_ }) }; PctMsSpi; $m = New-Object int[] 3; if ([Pct.MsSpi]::SystemParametersInfo(3, 0, $m, 0)) { $m } }
function PctMsAccelReg { $f = PctMsFake; $r = $(if ($f) { $f.reg } else { Get-ItemProperty 'HKCU:\Control Panel\Mouse' }); if ($r) { [int]"$($r.MouseThreshold1)"; [int]"$($r.MouseThreshold2)"; [int]"$($r.MouseSpeed)" } }
function PctMsAccelSet([int[]]$V) { if ($V.Count -ne 3) { return $false }; $f = PctMsFake
  if ($f) { $f.accel = $V; $f.reg = [pscustomobject]@{ MouseThreshold1 = "$($V[0])"; MouseThreshold2 = "$($V[1])"; MouseSpeed = "$($V[2])" }; PctMsFakeSave $f; return $true }
  PctMsSpi; if (-not [Pct.MsSpi]::SystemParametersInfo(4, 0, $V, 3)) { return $false }
  try { $k = 'HKCU:\Control Panel\Mouse'; Set-ItemProperty $k MouseThreshold1 "$($V[0])" -ErrorAction Stop; Set-ItemProperty $k MouseThreshold2 "$($V[1])" -ErrorAction Stop; Set-ItemProperty $k MouseSpeed "$($V[2])" -ErrorAction Stop; $true } catch { $false } }
# Бэкап: %LOCALAPPDATA%\Pomoshnik\mouse-backup.json — точность указателя до (accel; пусто — не менял), запрет отключения (devices: id, name, old). Первое старое значение не перезаписываю
function PctMsBackupPath { Join-Path $env:LOCALAPPDATA 'Pomoshnik\mouse-backup.json' }
function PctMsBackup { try { $o = [IO.File]::ReadAllText((PctMsBackupPath)) | ConvertFrom-Json -ErrorAction Stop; if ($o -is [Management.Automation.PSCustomObject]) { $o } } catch {} }
function PctMsBackupSave($B) { $p = PctMsBackupPath; [void][IO.Directory]::CreateDirectory((Split-Path $p)); $t = "$p.tmp"
  [IO.File]::WriteAllText($t, ($B | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false)); if ([IO.File]::Exists($p)) { [IO.File]::Replace($t, $p, [NullString]::Value) } else { [IO.File]::Move($t, $p) } }
function PctMsBackupStart { $b = PctMsBackup; if ($b) { return $b }; $b = [pscustomobject]@{ schema = 1; created = (Get-Date).ToString('s'); accel = @(); devices = @() }; PctMsBackupSave $b; $b }
function PctMsRemember($B, $Item) { if (@($B.devices | Where-Object { $_.id -eq $Item.id }).Count) { return }; $B.devices = @(@($B.devices) + $Item); PctMsBackupSave $B }
# Откат: точность указателя (с перечитыванием), запрет отключения. Всё вернул — бэкап в mouse-backup.<время>.done.json; нет — в бэкапе остаётся невозвращённое. → Ok, Bad; $null — бэкапа нет
function PctMsUndo { $b = PctMsBackup; if (-not $b) { return }; $bad = New-Object Collections.ArrayList; $ok = 0
  $a = [int[]]@($b.accel | ForEach-Object { [int]$_ }); if ($a.Count -eq 3) { if ((PctMsAccelSet $a) -and (@(PctMsAccel) -join ',') -eq ($a -join ',')) { $b.accel = @(); $ok++ } else { [void]$bad.Add('повышенная точность указателя') } }
  $k = @(); foreach ($x in @($b.devices)) { if (PctEnDeviceSet $x.id ([bool]$x.old)) { $ok++ } else { $k += $x; [void]$bad.Add("устройство: $($x.name)") } }; $b.devices = $k
  if ($bad.Count) { PctMsBackupSave $b } else { $p = PctMsBackupPath; $t = Get-Date -Format 'yyyyMMdd-HHmmss-fff'; $n = $p -replace '\.json$', ".$t.done.json"; for ($i = 1; [IO.File]::Exists($n); $i++) { $n = $p -replace '\.json$', ".$t-$i.done.json" }; [IO.File]::Move($p, $n) }
  [pscustomobject]@{ Ok = $ok; Bad = @($bad) } }

# ---------- Чек после действия (RECEIPT) и журнал возврата (основа 9l) ----------
# Чек: reports\receipts\<ГГГГММДД-ЧЧММСС>-<инструмент>.json, UTF-8 без BOM. tool, title, kind (do — действие, undo — возврат), t, sec, head — итог строкой, done [{text, val}] — что сделал простыми словами,
# kinds — какие быстрые замеры брал, m [{key, name, unit B|n|ms|%, before, after, better up|down, noise, verdict}] — до и после (null — «не мерил»), undo {can, why, journal}, note, of — чек, который возвращали.
# Окно узнаёт чек по строке S|receipt|<имя> (run.ps1). Чеки и журналы старше 90 дней удаляет PctReceiptEnd (лента «Что Помощник менял» хранит 90 дней)
# Быстрые замеры (≤ 1 с вместе): disk — свободно на каждом диске, mem — свободная память, procs — процессы, autorun — программы в автозагрузке, net — задержка до 1.1.1.1 и github.com (сети нет — «не мерил»).
# Шум — разница меньше него «без заметной разницы»: место 10 МБ, память 100 МБ, процессы 5, задержка 20 мс; автозагрузка — точное число. Элемент: имя, единица, число или $null, лучше up|down, шум
function PctRcMeasure([string[]]$Kinds) { $o = [ordered]@{}
  foreach ($k in $Kinds) { switch ($k) {
    'disk' { foreach ($d in @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady })) { $l = $d.Name.Substring(0, 1).ToUpper(); $o["disk:$l"] = @("Свободно на ${l}:", 'B', [double]$d.AvailableFreeSpace, 'up', 10MB) } }
    'mem' { $v = $null; try { Add-Type -AssemblyName Microsoft.VisualBasic; $v = [double](New-Object Microsoft.VisualBasic.Devices.ComputerInfo).AvailablePhysicalMemory } catch {}; $o['mem'] = @('Свободно памяти', 'B', $v, 'up', 100MB) }
    'procs' { $p = [Diagnostics.Process]::GetProcesses(); $o['procs'] = @('Процессов', 'n', [double]$p.Count, 'down', 5); foreach ($x in $p) { $x.Dispose() } }
    'autorun' { $o['autorun'] = @('Программ в автозагрузке', 'n', [double](PctRcAutorun), 'down', 0) }
    'net' { $h = @('1.1.1.1', 'github.com'); $ts = @{}; $on = $false; try { $on = [Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable() } catch {}
      if ($on) { foreach ($x in $h) { try { $ts[$x] = (New-Object Net.NetworkInformation.Ping).SendPingAsync($x, 500) } catch {} } }
      foreach ($x in $h) { $v = $null; $t = $ts[$x]; if ($t) { try { if ($t.Wait(900) -and $t.Result.Status -eq 'Success') { $v = [double]$t.Result.RoundtripTime } } catch {} }; $o["net:$x"] = @("Задержка до $x", 'ms', $v, 'down', 20) } } } }
  $o }
# Программы в автозагрузке: Run (свой и общий, 64 и 32 бит) и папки «Автозагрузка», без выключенных в Диспетчере задач (StartupApproved: первый байт нечётный — выключена)
function PctRcAutorun { $n = 0; $sa = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
  $off = { param($h, $k, $v) try { $s = $h.OpenSubKey("$sa\$k"); if ($s) { $b = $s.GetValue($v); $s.Close(); return ($b -is [byte[]] -and $b.Count -gt 0 -and [bool]($b[0] -band 1)) } } catch {}; $false }
  foreach ($r in @(@([Microsoft.Win32.Registry]::CurrentUser, 'Software\Microsoft\Windows\CurrentVersion\Run', 'Run'), @([Microsoft.Win32.Registry]::LocalMachine, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'Run'), @([Microsoft.Win32.Registry]::LocalMachine, 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'Run32'))) {
    try { $k = $r[0].OpenSubKey($r[1]); if ($k) { foreach ($v in $k.GetValueNames()) { if ($v -and -not (& $off $r[0] $r[2] $v)) { $n++ } }; $k.Close() } } catch {} }
  foreach ($f in @(@([Environment]::GetFolderPath('Startup'), [Microsoft.Win32.Registry]::CurrentUser), @([Environment]::GetFolderPath('CommonStartup'), [Microsoft.Win32.Registry]::LocalMachine))) {
    try { if ($f[0] -and [IO.Directory]::Exists($f[0])) { foreach ($x in [IO.Directory]::GetFiles($f[0])) { $nm = [IO.Path]::GetFileName($x); if ($nm -ne 'desktop.ini' -and -not (& $off $f[1] 'StartupFolder' $nm)) { $n++ } } } } catch {} }
  $n }
# Итог замера: better / worse — стало лучше или хуже, same — разница меньше шума, unknown — не мерил (нет «до» или «после»)
function PctRcVerdict($Before, $After, [string]$Better, [double]$Noise) { if ($null -eq $Before -or $null -eq $After) { return 'unknown' }; $d = [double]$After - [double]$Before
  if ($d -eq 0 -or [math]::Abs($d) -lt $Noise) { 'same' } elseif (($d -gt 0) -eq ($Better -eq 'up')) { 'better' } else { 'worse' } }
# Начать чек: замер «до» (Kinds — какие быстрые замеры подходят инструменту) → объект для PctRcDo, PctRcAdd, PctReceiptEnd. Kind undo и Of — чек возврата
function PctReceipt([string]$Tool, [string]$Title, [string[]]$Kinds = @(), [string]$Kind = 'do', [string]$Of = '') {
  [pscustomobject]@{ Tool = $Tool; Title = $Title; Kind = $Kind; Of = $Of; Kinds = @($Kinds); T0 = Get-Date; Sw = [Diagnostics.Stopwatch]::StartNew(); Before = (PctRcMeasure $Kinds); Done = (New-Object Collections.ArrayList); Own = (New-Object Collections.ArrayList) } }
# Строка «что сделал» (Val — размер или «было → стало», можно пусто) и свой замер инструмента (у «Энергосбережения» — срочные задачи устройств): число или $null, лучше up|down, шум
function PctRcDo($R, [string]$Text, [string]$Val = '') { [void]$R.Done.Add([ordered]@{ text = $Text; val = $Val }) }
function PctRcAdd($R, [string]$Key, [string]$Name, [string]$Unit, $Before, $After, [string]$Better = 'up', [double]$Noise = 0) {
  [void]$R.Own.Add([ordered]@{ key = $Key; name = $Name; unit = $Unit; before = $Before; after = $After; better = $Better; noise = $Noise; verdict = (PctRcVerdict $Before $After $Better $Noise) }) }
# Закончить: замер «после», запись чека, строка S|receipt|<имя> окну. Journal — журнал возврата (пустой — вернуть нечего), NoUndo — почему вернуть нельзя. → путь к чеку
function PctReceiptEnd($R, [string]$Head, $Journal, [string]$NoUndo = '', [string]$Note = '') {
  $a = PctRcMeasure $R.Kinds; $m = New-Object Collections.ArrayList
  foreach ($k in @(@($R.Before.Keys) + @($a.Keys | Where-Object { -not $R.Before.Contains($_) }))) { $x = $(if ($R.Before.Contains($k)) { $R.Before[$k] } else { $a[$k] })
    $b = $(if ($R.Before.Contains($k)) { $R.Before[$k][2] }); $f = $(if ($a.Contains($k)) { $a[$k][2] })
    [void]$m.Add([ordered]@{ key = $k; name = $x[0]; unit = $x[1]; before = $b; after = $f; better = $x[3]; noise = $x[4]; verdict = (PctRcVerdict $b $f $x[3] $x[4]) }) }
  foreach ($x in $R.Own) { [void]$m.Add($x) }
  $jn = $(if ($Journal -and @($Journal.items).Count) { $Journal.file } else { '' })
  $o = [ordered]@{ schema = 1; tool = $R.Tool; title = $R.Title; kind = $R.Kind; t = $R.T0.ToString('s'); sec = [int]$R.Sw.Elapsed.TotalSeconds; head = $Head; done = @($R.Done); kinds = @($R.Kinds); m = @($m)
    undo = [ordered]@{ can = [bool]$jn; why = $(if ($jn) { '' } else { $NoUndo }); journal = $jn }; note = $Note; of = $R.Of }
  $d = Join-Path (PctDir 'reports') 'receipts'; [void][IO.Directory]::CreateDirectory($d); $nm = "$($R.T0.ToString('yyyyMMdd-HHmmss'))-$($R.Tool)"; $p = "$d\$nm.json"; for ($i = 1; [IO.File]::Exists($p); $i++) { $p = "$d\$nm-$i.json" }
  $t = "$p.$PID.tmp"; [IO.File]::WriteAllText($t, ($o | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false)); [IO.File]::Move($t, $p)
  if (Test-Path function:Emit) { if (Test-Path function:RunFlush) { RunFlush }; Emit 'S' 'receipt' (Split-Path $p -Leaf) }
  PctRcClean; $p }
# Чеки и журналы возврата старше 90 дней (по дате в имени) — удалить. Нет прав на файл — молча: удалит запуск с правами
function PctRcClean { $lim = (Get-Date).Date.AddDays(-90); $r = PctDir 'reports'; $all = @()
  foreach ($q in @(@("$r\receipts", '*.json'), @($r, 'undo-*.json'))) { try { $all += @([IO.Directory]::GetFiles($q[0], $q[1])) } catch {} }
  foreach ($f in $all) { try { if ([IO.Path]::GetFileName($f) -match '(\d{8})-\d{6}' -and [datetime]::ParseExact($Matches[1], 'yyyyMMdd', $null) -lt $lim) { [IO.File]::Delete($f) } } catch {} } }

# Журнал возврата: reports\undo-<инструмент>-<ГГГГММДД-ЧЧММСС>.json — до изменения исходное значение каждого пункта: items [{n — номер, kind, text — для человека, state saved|undone, цель, old}], closed — когда вернул всё.
# kind: reg (key «HKCU\…»/«HKLM\…», name; old, type, existed), service (name; old — Start 2/3/4, delayed), task (path; old — включена), file (path; old — байты base64, existed),
# power-value / power-copy / power-overlay / power-device / power-nic — «Энергосбережение». admin — возврат с правами администратора: такой журнал запечатан (владелец «Администраторы», остальным только чтение);
# с повышением при UAC читаю только запечатанный — иначе её процесс без прав подменил бы, что вернуть с правами. PCT_UNDO_FAKE=<файл JSON> — подмена служб и задач: services {имя: {start, delayed, stuck}}, tasks {путь: {enabled, stuck}}
function PctUndoNew([string]$Tool, [string]$Title, [switch]$Admin) { [pscustomobject]@{ schema = 1; tool = $Tool; title = $Title; t = (Get-Date).ToString('s'); admin = [bool]$Admin; closed = ''; file = "undo-$Tool-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"; items = @() } }
function PctUndoPath($J) { Join-Path (PctDir 'reports') $J.file }
function PctUndoLog([string]$T) { try { $d = PctDir 'reports'; [void][IO.Directory]::CreateDirectory($d); [IO.File]::AppendAllText("$d\undo.log", "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $T`n", (New-Object Text.UTF8Encoding $false)) } catch {} }
function PctUndoFake { if ($env:PCT_UNDO_FAKE) { [IO.File]::ReadAllText($env:PCT_UNDO_FAKE) | ConvertFrom-Json } }
function PctUndoFakeSave($F) { [IO.File]::WriteAllText($env:PCT_UNDO_FAKE, ($F | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false)) }
# Запись: временный файл → замена. Журнал с правами: временный файл сразу создан запечатанным и без общего доступа (её процесс не успеет открыть его на запись), после замены — печать ещё раз
function PctUndoSave($J) { $p = PctUndoPath $J; [void][IO.Directory]::CreateDirectory((Split-Path $p)); $t = "$p.$PID.tmp"; $x = (New-Object Text.UTF8Encoding $false).GetBytes(($J | ConvertTo-Json -Depth 6))
  $seal = $J.admin -and ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if ($seal) { $fs = New-Object IO.FileStream($t, [IO.FileMode]::Create, [Security.AccessControl.FileSystemRights]::FullControl, [IO.FileShare]::None, 4096, [IO.FileOptions]::None, (PctUndoSec)); try { $fs.Write($x, 0, $x.Length) } finally { $fs.Dispose() } }
  else { [IO.File]::WriteAllBytes($t, $x) }
  if ([IO.File]::Exists($p)) { [IO.File]::Replace($t, $p, [NullString]::Value) } else { [IO.File]::Move($t, $p) }
  if ($seal) { PctUndoSeal $p } }
# Печать: владелец «Администраторы», Администраторы и SYSTEM — полный доступ, остальные вошедшие — только чтение, без наследования от папки
function PctUndoSec { $a = New-Object Security.AccessControl.FileSecurity; $a.SetAccessRuleProtection($true, $false)
  foreach ($s in @(@('S-1-5-32-544', 'FullControl'), @('S-1-5-18', 'FullControl'), @('S-1-5-11', 'ReadAndExecute'))) { $a.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier $s[0]), $s[1], 'Allow'))) }
  $a.SetOwner((New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544')); $a }
function PctUndoSeal([string]$P) { try { [IO.File]::SetAccessControl($P, (PctUndoSec)) } catch { PctUndoLog "не запечатал $P`: $($_.Exception.Message)" } }
# Запечатан (файл или папка): владелец — Администраторы или SYSTEM, писать, удалять и менять права могут только они
function PctUndoTrusted([string]$P) { try { $a = $(if ([IO.Directory]::Exists($P)) { [IO.Directory]::GetAccessControl($P) } else { [IO.File]::GetAccessControl($P) }); $ok = @('S-1-5-32-544', 'S-1-5-18'); if ($ok -notcontains $a.GetOwner([Security.Principal.SecurityIdentifier]).Value) { return $false }
    $w = [Security.AccessControl.FileSystemRights]'WriteData, AppendData, WriteAttributes, WriteExtendedAttributes, Delete, ChangePermissions, TakeOwnership'
    foreach ($r in $a.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) { if ($r.AccessControlType -eq 'Allow' -and $ok -notcontains $r.IdentityReference.Value -and [bool]($r.FileSystemRights -band $w)) { return $false } }; $true } catch { $false } }
# Реестр «HKCU\…» / «HKLM\…» → ключ .NET (без командлетов): Write — открыть на запись, Create — создать, если нет
function PctRegKey([string]$Path, [switch]$Write, [switch]$Create) { $h, $s = $Path -split '\\', 2; $b = $(switch ($h) { 'HKCU' { [Microsoft.Win32.Registry]::CurrentUser } 'HKLM' { [Microsoft.Win32.Registry]::LocalMachine } }); if (-not $b -or -not $s) { return }
  if ($Create) { $b.CreateSubKey($s) } else { $b.OpenSubKey($s, [bool]$Write) } }
# Исходное значение пункта (хэш-таблица), пока его не меняли
function PctUndoOld($X) { $f = PctUndoFake
  switch ($X.kind) {
    'reg' { $X.existed = $false; $X.old = $null; $X.type = ''; $k = PctRegKey $X.key
      if ($k) { if ($k.GetValueNames() -contains $X.name) { $X.existed = $true; $X.type = "$($k.GetValueKind($X.name))"; $v = $k.GetValue($X.name, $null, 'DoNotExpandEnvironmentNames'); $X.old = $(if ($v -is [byte[]]) { [Convert]::ToBase64String($v) } else { $v }) }; $k.Close() } }
    'service' { if ($f) { $s = $f.services.($X.name); $X.old = [int]$s.start; $X.delayed = [bool]$s.delayed } else { $k = PctRegKey "HKLM\SYSTEM\CurrentControlSet\Services\$($X.name)"; if ($k) { $X.old = [int]$k.GetValue('Start', 3); $X.delayed = [int]$k.GetValue('DelayedAutostart', 0) -eq 1; $k.Close() } } }
    'task' { if ($f) { $X.old = [bool]$f.tasks.($X.path).enabled } else { $s = New-Object -ComObject Schedule.Service; $s.Connect(); $X.old = [bool]$s.GetFolder('\').GetTask($X.path).Enabled } }
    'file' { $X.existed = [IO.File]::Exists($X.path); $X.old = $(if ($X.existed) { [Convert]::ToBase64String([IO.File]::ReadAllBytes($X.path)) } else { '' }) } } }
# Записать пункт в журнал до изменения: Item — хэш-таблица (kind и цель; old — уже известное старое значение, иначе читаю сам), Text — что это для человека (одинаковый текст — один шаг возврата)
function PctUndoAdd($J, $Item, [string]$Text) { if (-not $Item.Contains('old')) { PctUndoOld $Item }
  if (-not @($J.items).Count) { $b = $J.file -replace '\.json$'; for ($i = 1; [IO.File]::Exists((PctUndoPath $J)); $i++) { $J.file = "$b-$i.json" } }
  $Item.n = @($J.items).Count + 1; $Item.text = $Text; $Item.state = 'saved'; $x = [pscustomobject]$Item; $J.items = @(@($J.items) + $x); PctUndoSave $J; $x }
# Драйверы (DRIVERS-2): pnputil → Code (0 — вышло, 3010 — вышло, нужна перезагрузка), Out — строки вывода. PCT_DRVINST_FAKE=<json> — подмена (только тесты): вызов — строкой в <файл>.log;
# store — oem#.inf в хранилище (после строки «install» в журнале подмены — ещё added; other — пакет другому устройству, его нет в enum-devices), inf — имя .inf в копии, fail — команды, которые отвечают ошибкой (export-driver, delete-driver, add-driver, enum-drivers)
function PctDrvFake { if ($env:PCT_DRVINST_FAKE) { [IO.File]::ReadAllText($env:PCT_DRVINST_FAKE) | ConvertFrom-Json } }
function PctDrvFakeLog([string]$T) { [IO.File]::AppendAllText("$env:PCT_DRVINST_FAKE.log", "$T`n", (New-Object Text.UTF8Encoding $false)) }
function PctPnp([string[]]$A) { $f = PctDrvFake
  if ($f) { PctDrvFakeLog "pnputil $($A -join ' ')"; $v = "$($A[0])".TrimStart('/'); $c = $(if (@($f.fail) -contains $v) { 1 } else { 0 }); $o = @()
    $in = [IO.File]::ReadAllText("$env:PCT_DRVINST_FAKE.log") -match '(?m)^install '
    if ($v -eq 'enum-drivers') { $s = @($f.store); if ($in) { $s += $f.added; $s += $f.other }; $o = @($s | Where-Object { $_ } | ForEach-Object { "Published Name: $_" }) }
    if ($v -eq 'enum-devices') { $s = @($f.store); if ($in) { $s += $f.added }; $o = @($s | Where-Object { $_ } | ForEach-Object { "Driver Name: $_" }) }
    if ($v -eq 'export-driver' -and -not $c) { [void][IO.Directory]::CreateDirectory($A[2]); [IO.File]::WriteAllText("$($A[2])\$($f.inf)", '; копия на стенде') }
    return [pscustomobject]@{ Code = $c; Out = $o } }
  $o = @(& "$env:SystemRoot\System32\pnputil.exe" @A 2>&1 | ForEach-Object { "$_" }); [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o } }
function PctPnpOk($R) { $R -and ($R.Code -eq 0 -or $R.Code -eq 3010) }
# Папка копии драйвера: reports\drivers-backup\<имя>; с повышением — запечатана, как журнал возврата (файлы внутри наследуют печать)
function PctDrvBakDir([string]$Name) { $d = Join-Path (PctDir 'reports') "drivers-backup\$Name"
  if (PctElevated) { $a = New-Object Security.AccessControl.DirectorySecurity; $a.SetAccessRuleProtection($true, $false)
    foreach ($s in @(@('S-1-5-32-544', 'FullControl'), @('S-1-5-18', 'FullControl'), @('S-1-5-11', 'ReadAndExecute'))) { $a.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier $s[0]), $s[1], 'ContainerInherit, ObjectInherit', 'None', 'Allow'))) }
    $a.SetOwner((New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544')); [void][IO.Directory]::CreateDirectory($d, $a) } else { [void][IO.Directory]::CreateDirectory($d) }; $d }
# Вернуть один пункт → $true — вернул (или возвращать уже нечего: копии схемы нет); $false — не вышло, пункт остаётся в журнале
function PctUndoItem($X) { $f = PctUndoFake
  try { switch ($X.kind) {
    'reg' { if ($X.existed) { $k = PctRegKey $X.key -Create; if (-not $k) { return $false }
          $v = switch ($X.type) { 'DWord' { [int]$X.old } 'QWord' { [long]$X.old } 'Binary' { , [Convert]::FromBase64String("$($X.old)") } 'MultiString' { [string[]]@($X.old) } default { "$($X.old)" } }
          $k.SetValue($X.name, $v, [Microsoft.Win32.RegistryValueKind]$X.type); $k.Close() }
        else { $k = PctRegKey $X.key -Write; if ($k) { $k.DeleteValue($X.name, $false); $k.Close() } }; return $true }
    'service' { if ($f) { $s = $f.services.($X.name); if (-not $s -or $s.stuck) { return $false }; $s.start = [int]$X.old; $s.delayed = [bool]$X.delayed; PctUndoFakeSave $f; return $true }
      $m = @{ 2 = $(if ($X.delayed) { 'delayed-auto' } else { 'auto' }); 3 = 'demand'; 4 = 'disabled' }[[int]$X.old]; if (-not $m) { return $false }; $null = sc.exe config $X.name start= $m 2>&1; return -not $LASTEXITCODE }
    'task' { if ($f) { $t = $f.tasks.($X.path); if (-not $t -or $t.stuck) { return $false }; $t.enabled = [bool]$X.old; PctUndoFakeSave $f; return $true }
      $s = New-Object -ComObject Schedule.Service; $s.Connect(); $t = $s.GetFolder('\').GetTask($X.path); $t.Enabled = [bool]$X.old; return [bool]$t.Enabled -eq [bool]$X.old }
    'file' { if ($X.existed) { [void][IO.Directory]::CreateDirectory((Split-Path $X.path)); [IO.File]::WriteAllBytes($X.path, [Convert]::FromBase64String("$($X.old)")) } elseif ([IO.File]::Exists($X.path)) { [IO.File]::Delete($X.path) }; return $true }
    'power-value' { if (-not (PctEnHas $X.scheme)) { return $true }; if (-not (PctEnSet $X.scheme $X.key $X.src ([long]$X.old)) -or (PctEnGet $X.scheme $X.key).($X.src) -ne [long]$X.old) { return $false }
      if ($X.scheme -eq (PctEnActive)) { [void](PctEnSetActive $X.scheme) }; return $true }
    'power-copy' { if ((PctEnActive) -eq $X.copy -and -not (PctEnSetActive $X.prev)) { return $false }; if (-not (PctEnHas $X.copy)) { return $true }; return [bool](PctEnDelete $X.copy) }
    'power-overlay' { if (-not (PctEnDevice).AC) { return $false }; return [bool](PctEnOverlaySet $X.old) }
    'power-device' { return [bool](PctEnDeviceSet $X.id ([bool]$X.old)) }
    'power-nic' { return [bool](PctEnNicSet $X.adapter $X.kw "$($X.old)") }
    # Драйвер (DRIVERS-2): driver-del — убрать новый пакет с устройств (пакета уже нет в хранилище — возвращать нечего); driver-add — поставить копию прежнего (только из reports\drivers-backup, с повышением — запечатанную)
    'driver-del' { if ("$($X.new)" -notmatch '^oem\d+\.inf$') { return $false }; if (PctPnpOk (PctPnp @('/delete-driver', "$($X.new)", '/uninstall'))) { return $true }
      $e = PctPnp @('/enum-drivers'); return (PctPnpOk $e) -and -not @($e.Out | Where-Object { "$_" -match "(?i)\b$([regex]::Escape("$($X.new)"))\b" }).Count }
    'driver-add' { $b = "$($X.bak)"; if (-not $b.StartsWith("$(PctDir 'reports')\drivers-backup\", 'OrdinalIgnoreCase') -or $b -notmatch '\.inf$' -or -not [IO.File]::Exists($b)) { return $false }
      if ((PctElevated) -and -not ((PctUndoTrusted $b) -and (PctUndoTrusted (Split-Path $b)))) { PctUndoLog "отказ: копия драйвера не запечатана — $b"; return $false }
      $r = PctPnp @('/add-driver', $b, '/install'); if (PctPnpOk $r) { return $true }
      # 259 — пакет добавлен, но устройству не поставлен: вернул, только если устройство уже на прежней версии
      if ($r.Code -eq 259 -and $X.dev -and $X.oldver) { $d = @(Get-CimInstance Win32_PnPSignedDriver -Property DeviceID, DriverVersion | Where-Object { "$($_.DeviceID)" -eq "$($X.dev)" })[0]; return "$($d.DriverVersion)" -eq "$($X.oldver)" }; return $false }
    # Приложение (APPS-REMOVE): вернуть из Store — только из белого списка (PctAppxInstall сверяет сам); уже стоит — возвращать нечего
    'appx' { return (PctAppxInstall "$($X.pfn)") -eq 'ok' } } }
  catch { PctUndoLog "пункт $($X.n) ($($X.kind)): $($_.Exception.Message)" }; $false }
# Вернуть пункт и сразу записать журнал (сбой посередине — при следующем возврате только оставшиеся). Всё вернул — журнал закрыт
function PctUndoOne($J, $X) { $ok = PctUndoItem $X; if ($ok) { $X.state = 'undone'; if ("$($X.kind)" -like 'power-*') { PctEnForget $X } } else { PctUndoLog "не вернул: $($X.text) ($($X.kind)) — $($J.file)" }
  if (-not @($J.items | Where-Object { $_.state -ne 'undone' }).Count) { $J.closed = (Get-Date).ToString('s') }; PctUndoSave $J; $ok }
# Невозвращённые пункты, с последнего
function PctUndoPending($J) { $a = @($J.items | Where-Object { $_.state -ne 'undone' }); [array]::Reverse($a); $a }
function PctUndoAll($J) { $ok = 0; $bad = New-Object Collections.ArrayList; foreach ($x in @(PctUndoPending $J)) { if (PctUndoOne $J $x) { $ok++ } else { [void]$bad.Add($x.text) } }; [pscustomobject]@{ Ok = $ok; Bad = @($bad) } }
# Журнал по имени (только reports\undo-*.json); с повышением при UAC — только запечатанный. → журнал или строка-причина
function PctUndoLoad([string]$Name) { if ($Name -notmatch '^undo-[a-z0-9-]+-\d{8}-\d{6}(-\d+)?\.json$') { return 'неверное имя журнала' }; $p = Join-Path (PctDir 'reports') $Name
  if (-not [IO.File]::Exists($p)) { return 'журнала нет' }; if ((PctElevated) -and -not (PctUndoTrusted $p)) { PctUndoLog "отказ: журнал не запечатан — $p"; return 'журнал мог поменять другой процесс' }
  try { $j = [IO.File]::ReadAllText($p) | ConvertFrom-Json -ErrorAction Stop } catch { return 'журнал не читается' }
  if ($j -isnot [Management.Automation.PSCustomObject]) { return 'журнал не читается' }; $j.file = $Name; $j.items = @($j.items); $j }
# Инструмент вернул всё сам (своим бэкапом): его журналы закрыты — лента покажет «вернул»
function PctUndoCloseAll([string]$Tool) { $fs = @(); try { $fs = @([IO.Directory]::GetFiles((PctDir 'reports'), "undo-$Tool-*.json")) } catch {}
  foreach ($f in $fs) { $j = PctUndoLoad ([IO.Path]::GetFileName($f)); if ($j -is [string] -or $j.closed) { continue }; foreach ($x in @($j.items)) { $x.state = 'undone' }; $j.closed = (Get-Date).ToString('s'); PctUndoSave $j } }
# ---------- Лишние приложения (APPS-REMOVE): белый список, пакеты текущего пользователя, удаление, возврат из Store ----------
# Белый список — только он и только здесь (apps-remove.ps1 и возврат по журналу). K — ключ строки окна, Pfn — PackageFamilyName (сверено с каталогом Store 12.11.2026), Store — номер в Store для возврата,
# Adv 2 — лишнее (совет удалить), 1 — по желанию; Grp fun — игры и развлечения, news — новости и советы; Ico — значок Segoe. Чего нет в списке, не удаляю никогда
function PctAppsList { foreach ($a in @(
    @('xbox', 'Microsoft.GamingApp_8wekyb3d8bbwe', '9MV0B5HZVK9Z', 1, 'fun', 'Xbox', 'игры, Game Pass', 'Приложение Xbox: друзья, магазин игр, Game Pass.', 'Игры из Game Pass без него не запустятся. Steam и другие — запустятся.', 0xE7FC),
    @('clip', 'Clipchamp.Clipchamp_yxz26nhyzhsrt', '9P1J8S7CCWWT', 1, 'fun', 'Clipchamp', 'видеоредактор', 'Видеоредактор от Microsoft.', '', 0xE714),
    @('sol', 'Microsoft.MicrosoftSolitaireCollection_8wekyb3d8bbwe', '9WZDNCRFHWD2', 1, 'fun', 'Солитёр', 'пасьянсы', 'Пасьянсы с рекламой внутри.', '', 0xE7FC),
    @('todo', 'Microsoft.Todos_8wekyb3d8bbwe', '9NBLGGH5R558', 1, 'fun', 'To Do', 'списки дел', 'Списки дел от Microsoft.', 'Списки хранятся в учётной записи Microsoft: вернёшь приложение — они вернутся.', 0xE73A),
    @('maps', 'Microsoft.WindowsMaps_8wekyb3d8bbwe', '9WZDNCRDTBVB', 1, 'fun', 'Карты', 'карты и маршруты', 'Карты Windows. Карты в браузере работают и без них.', '', 0xE707),
    @('video', 'Microsoft.ZuneVideo_8wekyb3d8bbwe', '9WZDNCRFJ3P2', 1, 'fun', 'Кино и ТВ', 'видеоплеер', 'Старый видеоплеер от Microsoft.', 'Видео будет открываться в другом плеере.', 0xE8B2),
    @('news', 'Microsoft.BingNews_8wekyb3d8bbwe', '9WZDNCRFHVFW', 2, 'news', 'Новости', 'лента новостей', 'Лента новостей от Microsoft.', '', 0xE900),
    @('wthr', 'Microsoft.BingWeather_8wekyb3d8bbwe', '9WZDNCRFJ3Q2', 1, 'news', 'Погода', 'прогноз', 'Прогноз погоды.', '', 0xE706),
    @('tips', 'Microsoft.Getstarted_8wekyb3d8bbwe', '9WZDNCRDTBJJ', 2, 'news', 'Советы', 'подсказки', 'Подсказки, как пользоваться Windows.', '', 0xE82F),
    @('fb', 'Microsoft.WindowsFeedbackHub_8wekyb3d8bbwe', '9NBLGGH4R32N', 2, 'news', 'Центр отзывов', 'отзывы', 'Отправить отзыв в Microsoft.', '', 0xE939),
    @('m365', 'Microsoft.MicrosoftOfficeHub_8wekyb3d8bbwe', '9WZDNCRD29V9', 2, 'news', 'Microsoft 365', 'реклама подписки', 'Ярлыки Office и реклама подписки Microsoft 365.', 'Word и Excel, если они установлены, останутся.', 0xE8A5))) {
    [pscustomobject]@{ K = $a[0]; Pfn = $a[1]; Store = $a[2]; Adv = $a[3]; Grp = $a[4]; N = $a[5]; Sub = $a[6]; What = $a[7]; Iff = $a[8]; Ico = $a[9] } } }
# Вторая защита: эти никогда, даже если попали в список по ошибке (Store, App Installer, Блокнот, Фото, Калькулятор, Терминал, Безопасность Windows, Game Bar и части Xbox, панели драйверов, фреймворки)
function PctAppsNever { '(?i)^Microsoft\.(WindowsStore|StorePurchaseApp|DesktopAppInstaller|Winget\.|WindowsNotepad|Windows\.Photos|WindowsCalculator|WindowsTerminal|SecHealthUI|XboxGamingOverlay|XboxGameOverlay|Xbox\.TCUI|XboxIdentityProvider|XboxSpeechToTextOverlay|VCLibs|NET\.|UI\.Xaml|WindowsAppRuntime)|Realtek|NVIDIA|Intel|AMD|AdvancedMicroDevices|Dolby|Synaptics|ELAN' }
# Стенд (только тесты): PCT_APPS_FAKE=<файл JSON> — pkgs [{pfn, full, ver, loc, framework, nonremovable}] вместо Get-AppxPackage; stuck [pfn] — Windows не даёт удалить, «install:<pfn>» — Store не ставит;
# net false — нет интернета, winget false — winget нет (открою страницу Store). Каждый вызов — строкой в <файл>.log. Переменная задана, а файл не читается — ни подмены, ни настоящих пакетов: пусто и отказ
function PctAppsFake { if ($env:PCT_APPS_FAKE) { try { [IO.File]::ReadAllText($env:PCT_APPS_FAKE) | ConvertFrom-Json } catch {} } }
function PctAppsFakeSave($F) { [IO.File]::WriteAllText($env:PCT_APPS_FAKE, ($F | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false)) }
function PctAppsFakeLog([string]$T) { [IO.File]::AppendAllText("$env:PCT_APPS_FAKE.log", "$T`n", (New-Object Text.UTF8Encoding $false)) }
# Пакеты текущего пользователя (без прав): Pfn, Full — полное имя, Ver, Loc — папка установки, Fw — фреймворк, NonRem — Windows не даёт удалить
function PctAppx { if ($env:PCT_APPS_FAKE) { $f = PctAppsFake; return @($f.pkgs | ForEach-Object { [pscustomobject]@{ Pfn = "$($_.pfn)"; Full = "$($_.full)"; Ver = "$($_.ver)"; Loc = "$($_.loc)"; Fw = [bool]$_.framework; NonRem = [bool]$_.nonremovable } }) }
  @(Get-AppxPackage | ForEach-Object { [pscustomobject]@{ Pfn = "$($_.PackageFamilyName)"; Full = "$($_.PackageFullName)"; Ver = "$($_.Version)"; Loc = "$($_.InstallLocation)"; Fw = [bool]$_.IsFramework; NonRem = [bool]$_.NonRemovable } }) }
function PctAppxHas([string]$Pfn) { [bool]@(PctAppx | Where-Object { $_.Pfn -eq $Pfn -and -not $_.Fw }).Count }
# Удалить у текущего пользователя: без -AllUsers и без удаления из образа — прав не нужно, Store вернёт. Только из белого списка; сбой — исключение (ловит apps-remove.ps1)
function PctAppxRemove([string]$Pfn, [string]$Full) { if (-not @(PctAppsList | Where-Object { $_.Pfn -eq $Pfn }).Count -or $Pfn -match (PctAppsNever) -or $Full -notlike "$($Pfn -replace '_.*$')_*") { throw "не из белого списка: $Pfn" }
  if ($env:PCT_APPS_FAKE) { $f = PctAppsFake; if (-not $f) { throw 'подмена PCT_APPS_FAKE не читается' }; PctAppsFakeLog "remove $Full"; if (@($f.stuck) -contains $Pfn) { throw 'Windows не дала удалить (стенд)' }; $f.pkgs = @($f.pkgs | Where-Object { "$($_.full)" -ne $Full }); PctAppsFakeSave $f; return }
  Remove-AppxPackage -Package $Full -ErrorAction Stop }
# Интернет есть: Store отвечает (curl.exe, 6 с)
function PctNetOk { $c = "$(& curl.exe -s -o NUL -m 6 -w '%{http_code}' 'https://storeedgefd.dsx.mp.microsoft.com/' 2>$null)"; $c -match '^[1-5]\d\d$' }
# Вернуть из Store (только из белого списка, только себе): winget install --source msstore без вопросов, прав не нужно. Нет winget или winget не поставил при живом интернете — страница Store (человек нажмёт «Получить»).
# → ok — стоит (или уже стояло), page — открыл Store, net — нет интернета, fail — не из белого списка
function PctAppxInstall([string]$Pfn) { $a = @(PctAppsList | Where-Object { $_.Pfn -eq $Pfn })[0]; if (-not $a -or $Pfn -match (PctAppsNever)) { PctUndoLog "отказ: $Pfn не из белого списка"; return 'fail' }
  if (PctAppxHas $Pfn) { return 'ok' }
  if ($env:PCT_APPS_FAKE) { $f = PctAppsFake; if (-not $f) { return 'fail' }; PctAppsFakeLog "install $($a.Store)"; if ($f.winget -eq $false) { PctAppsFakeLog "page $($a.Store)"; return 'page' }; if ($f.net -eq $false) { return 'net' }; if (@($f.stuck) -contains "install:$Pfn") { PctAppsFakeLog "page $($a.Store)"; return 'page' }
    $f.pkgs = @(@($f.pkgs) + [pscustomobject]@{ pfn = $Pfn; full = "$($Pfn -replace '_.*$')_9.9.9.0_x64__$($Pfn -replace '^.*_')"; ver = '9.9.9.0'; loc = ''; framework = $false; nonremovable = $false }); PctAppsFakeSave $f; return 'ok' }
  $w = "$((Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source)"
  if (-not $w) { if (-not (PctNetOk)) { return 'net' }; Start-Process "ms-windows-store://pdp/?ProductId=$($a.Store)"; return 'page' }
  $o = @(& $w install --id $a.Store --source msstore --accept-package-agreements --accept-source-agreements --disable-interactivity --silent 2>&1); $c = $LASTEXITCODE
  if (PctAppxHas $Pfn) { return 'ok' }; PctUndoLog "winget $($a.Store): код $c — $((@($o | Select-Object -Last 2) -join ' ').Trim())"; if (-not (PctNetOk)) { return 'net' }; Start-Process "ms-windows-store://pdp/?ProductId=$($a.Store)"; 'page' }
# Временные папки меняются на ходу. Get-ChildItem -Recurse на исчезнувшем файле бросает Win32Exception и обрывает обход: в окне (try в run.ps1) — всю проверку, без try — ложный 0. Здесь исчез файл — не считаю только его
# Папка с меткой ссылки: имя-заместитель (бит 0x20000000 метки: точка соединения, символьная ссылка) ведёт в другое место — не обхожу. Облачная папка (OneDrive) — не заместитель: файлы в ней свои. Метку не прочитать — не обхожу: вдруг ссылка
function PctNameSurrogate([string]$Path) { try { if (-not ('Pct.FindTag' -as [type])) { Add-Type -Namespace Pct -Name FindTag -MemberDefinition '[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode, Pack = 4)] public struct D { public uint A; public long C, R, W; public uint H, L, Tag, X; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string N; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 14)] public string S; }
[DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindFirstFileW(string p, out D d);
[DllImport("kernel32.dll")] public static extern bool FindClose(IntPtr h);' }
    $d = New-Object Pct.FindTag+D; $h = [Pct.FindTag]::FindFirstFileW($Path, [ref]$d); if ($h -eq [IntPtr](-1)) { return $true }; [void][Pct.FindTag]::FindClose($h); [bool]($d.Tag -band 0x20000000) } catch { $true } }
function PctTreeBytes([string[]]$Dirs) { $s = [long]0; $st = New-Object Collections.Stack; foreach ($d in $Dirs) { $st.Push($d) }
  while ($st.Count) { $d = $st.Pop(); try { foreach ($e in ([IO.DirectoryInfo]$d).EnumerateFileSystemInfos()) { try { if ($e -is [IO.DirectoryInfo]) { if (-not ($e.Attributes -band 1024) -or -not (PctNameSurrogate $e.FullName)) { $st.Push($e.FullName) } } else { $s += $e.Length } } catch {} } } catch {} }
  $s }
