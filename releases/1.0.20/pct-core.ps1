# Общие пути и порт Помощника. Подключение: . "$PSScriptRoot\pct-core.ps1". При подключении ничего не делает, только задаёт функции.
# Корень: $env:PCT_ROOT (для проверок) → папка выше helpers, если скрипт лежит в helpers → C:\PC-Tweaks-Laptop.
function PctRoot { if ($env:PCT_ROOT) { return $env:PCT_ROOT }
  if ((Split-Path $PSScriptRoot -Leaf) -eq 'helpers') { return (Split-Path $PSScriptRoot -Parent) }; 'C:\PC-Tweaks-Laptop' }
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
function PctUnlock($L) { if ($L -and $L.M) { try { $L.M.ReleaseMutex() } catch {}; $L.M.Dispose(); $L.M = $null } }
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
  $zc = "$Hd\zapret-cmd.txt"; $z = Test-Path -LiteralPath $zc; $pac = Test-Path -LiteralPath "$Hd\smart-proxy-on.txt"
  $ad = "$(Get-Content -LiteralPath "$Hd\anydesk-path.txt" -Encoding UTF8 -TotalCount 1 -ErrorAction SilentlyContinue)"
  $ad = [bool](@($ad, "${env:ProgramFiles(x86)}\AnyDesk\AnyDesk.exe", "$env:ProgramFiles\AnyDesk\AnyDesk.exe") | Where-Object { $_ -and (Test-Path -LiteralPath $_) }) -or [bool](Get-Process AnyDesk -ErrorAction SilentlyContinue)
  $happ = (Test-Path -LiteralPath 'D:\Happ') -or [bool](Get-Process Happ -ErrorAction SilentlyContinue)
  $yn = { param($v) if ($v) { 'да' } else { 'нет' } }
  PctProfileLog "нашёл: обход=$(& $yn $z), прокси=$(& $yn $pac), Happ=$(& $yn $happ), AnyDesk=$(& $yn $ad)"
  try { PctProfileSave ([ordered]@{ schema = 1; created = (Get-Date).ToString('o'); source = 'migrate'; legacyRoot = $r
    modules = [ordered]@{ core = $true; pc = $true; ru = ($z -or $pac) }
    vpn = [ordered]@{ client = $(if ($happ) { 'Happ' } else { '' }); socks = (PctSocks); pac = $pac }
    sites = [ordered]@{ file = "$Hd\proxy-sites.txt" }; zapret = [ordered]@{ cmdFile = $(if ($z) { $zc } else { '' }) }
    help = [ordered]@{ kind = $(if ($ad) { 'anydesk' } else { '' }); enabled = $ad } }) } catch { PctProfileLog "не сохранил: $($_.Exception.Message)"; throw }
  PctProfileLog "сохранил профиль: $(PctProfilePath)"
  $f = @(if ($z) { 'обход' }; if ($pac) { 'прокси' }; if ($happ) { 'Happ' })
  if ($f) { 'Собрал профиль из твоих настроек: ' + ($f -join ', ') } else { 'Собрал профиль из твоих настроек' } }
