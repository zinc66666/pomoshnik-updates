# «Большая уборка», часть A: смотрю мусор по группам, спрашиваю про каждую, убираю выбранное, показываю место до и после.
# -Scan — только смотрю, ничего не удаляю. PCT_CLEAN_FAKE=<папка> — все корни групп внутри неё (C:\x → <папка>\C\x): проверка удаления без настоящих дисков.
param([switch]$Scan)
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
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
# Внутри групп не трогаю обход (zapret), Happ и временные файлы Помощника (pct-*: обновление, номер AnyDesk)
$keepName = '(?i)zapret|^happ$|^pct-|^pomoshnik$|^pc-tweaks'
function Under($a, $b) { $a -eq $b -or $a.StartsWith("$b\", 'OrdinalIgnoreCase') }
# Корень группы годится: глубже диска, вне запретных папок и не их родитель, не ссылка, в поддельном режиме — внутри поддельного дерева
function Allowed($p) { if ($p -notmatch '^[A-Za-z]:\\[^\\]+\\') { return $false }; if ($Fake -and -not (Under $p $Fake)) { return $false }
  foreach ($k in $keep) { if ((Under $p $k) -or (Under $k $p)) { return $false } }; if ((Split-Path $p -Leaf) -match $keepName) { return $false }
  $i = [IO.DirectoryInfo]$p; if ($i.Exists -and ($i.Attributes -band 1024)) { return $false }; $true }

# ---------- Группы и их корни (только эти пути) ----------
$Grp = [ordered]@{
  temp = @{ N = 'Временные файлы'; U = 'Убираю временные файлы'; What = 'Это остатки, которые программы бросили после работы.'; After = 'После удаления ничего не изменится: программам они больше не нужны.'; Rec = 'Рекомендую.'; Q = 'Удалить временные файлы?' }
  bin  = @{ N = 'Корзина'; U = 'Очищаю Корзину'; What = 'Это файлы, которые ты сама удалила.'; After = 'После очистки вернуть их будет нельзя.'; Rec = 'По ситуации: сначала загляни в Корзину, нет ли там нужного.'; Q = 'Очистить Корзину?' }
  web  = @{ N = 'Кэш браузеров'; U = 'Убираю кэш браузеров'; What = 'Это копии картинок и страниц, чтобы сайты открывались быстрее. Пароли, вход на сайты, история и вкладки останутся.'; After = 'После удаления сайты один раз откроются чуть дольше.'; Rec = 'Рекомендую, если мало места.'; Q = 'Удалить кэш браузеров?'; Small = 1 }
  chat = @{ N = 'Кэш Discord и Telegram'; U = 'Убираю кэш Discord и Telegram'; What = 'Это картинки и видео из чатов, сохранённые на ноутбуке. Вход и переписка останутся.'; After = 'После удаления старые картинки в чатах загрузятся заново.'; Rec = 'Рекомендую, если мало места.'; Q = 'Удалить кэш Discord и Telegram?'; Small = 1 }
  gpu  = @{ N = 'Кэш видеокарты'; U = 'Убираю кэш видеокарты'; What = 'Это заготовки, чтобы игры и видео запускались быстрее.'; After = 'После удаления игры первый раз запустятся дольше и пару минут могут подтормаживать.'; Rec = 'По ситуации: удаляй, если игры начали глючить.'; Q = 'Удалить кэш видеокарты?'; Small = 1 }
  upd  = @{ N = 'Загрузки обновлений Windows'; U = 'Убираю загрузки обновлений'; What = 'Это уже скачанные обновления и копии, которыми Windows делится с другими компьютерами.'; After = 'После удаления Windows сама скачает заново то, что понадобится.'; Rec = 'Рекомендую.'; Q = 'Удалить загрузки обновлений?' }
  dump = @{ N = 'Отчёты о сбоях'; U = 'Убираю отчёты о сбоях'; What = 'Это записи о том, как падали программы и Windows.'; After = 'После удаления по ним уже не разобрать старые сбои.'; Rec = 'По ситуации: если ноутбук недавно сам перезагружался, оставь их и позови помощь.'; Q = 'Удалить отчёты о сбоях?'; Small = 1 } }
$items = New-Object Collections.ArrayList; $seen = @{}
# Корень: группа, подпись источника, путь, процесс (открыт — пропускаю), имя программы для подсказки
function Add($g, $l, $p, $proc = '', $app = '') { if (-not $p) { return }; $m = Map $p; if ($seen.ContainsKey($m)) { return }; $seen[$m] = 1
  if (-not (Test-Path -LiteralPath $m)) { return }; if (-not (Allowed $m)) { Jr "отказ: путь вне разрешённых корней или рядом с запретной папкой: $m"; return }
  [void]$items.Add([pscustomobject]@{ G = $g; L = $l; P = $m; Proc = $proc; App = $app; B = [long]0; F = 0; Skip = $false }) }
# Профили браузера на основе Chromium: папка с Preferences; чищу только Cache, Code Cache, GPUCache и кэш шейдеров браузера
function Chromium($l, $base, $proc, $app, $local = '') { $b = Map $base; if (-not (Test-Path -LiteralPath $b)) { return }
  foreach ($c in @('ShaderCache', 'GrShaderCache', 'GraphiteDawnCache')) { Add 'web' $l "$base\$c" $proc $app }
  $pr = @($base) + @(Get-ChildItem -LiteralPath $b -Directory -Force | Where-Object { Test-Path -LiteralPath "$($_.FullName)\Preferences" } | ForEach-Object { "$base\$($_.Name)" })
  foreach ($p in $pr) { foreach ($c in @('Cache', 'Code Cache', 'GPUCache')) { Add 'web' $l "$p\$c" $proc $app } }
  if ($local) { Add 'web' $l "$local\Cache" $proc $app } }
$la = $env:LOCALAPPDATA; $ra = $env:APPDATA; $wd = $env:windir; $pd = $env:ProgramData; $low = "$env:USERPROFILE\AppData\LocalLow"
Add 'temp' 'временные файлы' $env:TEMP; Add 'temp' 'временные файлы' "$wd\Temp"
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$drives = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object { $_.Name.Substring(0, 1) })
foreach ($d in $drives) { Add 'bin' 'Корзина' "${d}:\`$Recycle.Bin\$sid" }
Chromium 'кэш Chrome' "$la\Google\Chrome\User Data" 'chrome' 'Chrome'
Chromium 'кэш Edge' "$la\Microsoft\Edge\User Data" 'msedge' 'Edge'
Chromium 'кэш Яндекс Браузера' "$la\Yandex\YandexBrowser\User Data" 'browser' 'Яндекс Браузер'
foreach ($o in @('Opera Stable', 'Opera GX Stable')) { Chromium 'кэш Opera' "$ra\Opera Software\$o" 'opera' 'Opera' "$la\Opera Software\$o" }
foreach ($f in @(Get-ChildItem -LiteralPath (Map "$la\Mozilla\Firefox\Profiles") -Directory -Force)) { Add 'web' 'кэш Firefox' "$la\Mozilla\Firefox\Profiles\$($f.Name)\cache2" 'firefox' 'Firefox' }
foreach ($c in @('Cache', 'Code Cache', 'GPUCache')) { Add 'chat' 'кэш Discord' "$ra\discord\$c" 'Discord' 'Discord' }
foreach ($u in @(Get-ChildItem -LiteralPath (Map "$ra\Telegram Desktop\tdata") -Directory -Force -Filter 'user_data*')) { foreach ($c in @('cache', 'media_cache')) { Add 'chat' 'кэш Telegram' "$ra\Telegram Desktop\tdata\$($u.Name)\$c" 'Telegram' 'Telegram' } }
foreach ($p in @("$la\D3DSCache", "$la\NVIDIA\DXCache", "$la\NVIDIA\GLCache", "$low\NVIDIA\PerDriverVersion\DXCache", "$low\NVIDIA\PerDriverVersion\GLCache", "$pd\NVIDIA Corporation\NV_Cache", "$la\AMD\DxCache", "$la\AMD\DxcCache", "$la\AMD\GLCache", "$la\AMD\VkCache")) { Add 'gpu' 'кэш видеокарты' $p }
Add 'upd' 'загрузки обновлений Windows' "$wd\SoftwareDistribution\Download"
Add 'upd' 'копии обновлений для других компьютеров' "$wd\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"
foreach ($p in @("$wd\Minidump", "$wd\MEMORY.DMP", "$wd\LiveKernelReports", "$la\CrashDumps", "$pd\Microsoft\Windows\WER\ReportArchive", "$pd\Microsoft\Windows\WER\ReportQueue", "$la\Microsoft\Windows\WER\ReportArchive", "$la\Microsoft\Windows\WER\ReportQueue")) { Add 'dump' 'отчёты о сбоях' $p }

# Размер дерева: внутрь ссылок (junction, symlink) не захожу
function Size($p) { $b = [long]0; $n = 0; if ([IO.File]::Exists($p)) { return @(([IO.FileInfo]$p).Length, 1) }
  $st = New-Object Collections.Stack; $st.Push([IO.DirectoryInfo]$p)
  while ($st.Count) { $d = $st.Pop(); try { foreach ($e in $d.EnumerateFileSystemInfos()) { if ($e.Attributes -band 1024) { continue }; if ($e -is [IO.DirectoryInfo]) { $st.Push($e) } else { $b += $e.Length; $n++ } } } catch {} }
  @($b, $n) }
# Удаление содержимого: ссылку удаляю как ссылку, занятый файл пропускаю (busy), запретные имена не трогаю. Корневая папка остаётся
$script:freed = [long]0; $script:busy = 0
function WipeIn([IO.DirectoryInfo]$d) { try { $all = @($d.EnumerateFileSystemInfos()) } catch { return }
  foreach ($e in $all) { if ($e.Name -match $keepName) { Jr "не тронул: $($e.FullName)"; continue }; if ($e.Name -eq 'desktop.ini' -and $d.Name -like 'S-1-5-*') { continue }
    if ($e -is [IO.DirectoryInfo]) { if (-not ($e.Attributes -band 1024)) { WipeIn $e }; try { if ($e.Attributes -band 1) { $e.Attributes = 'Directory' }; $e.Delete($false) } catch {} }
    else { try { $n = $e.Length; if ($e.Attributes -band 1) { $e.Attributes = 'Normal' }; $e.Delete(); $script:freed += $n } catch { $script:busy++ } } } }
function Wipe($it) { if (-not $seen.ContainsKey($it.P) -or -not (Allowed $it.P)) { Jr "отказ: $($it.P)"; return }
  if ([IO.File]::Exists($it.P)) { try { $n = ([IO.FileInfo]$it.P).Length; [IO.File]::Delete($it.P); $script:freed += $n } catch { $script:busy++ }; return }
  # Копии обновлений для других компьютеров: штатная команда Windows, без остановки службы
  if (-not $Fake -and $it.L -like 'копии обновлений*' -and (Get-Command Delete-DeliveryOptimizationCache)) { $b0 = (Size $it.P)[0]; Delete-DeliveryOptimizationCache -Force; $script:freed += [math]::Max(0, $b0 - (Size $it.P)[0]); return }
  WipeIn ([IO.DirectoryInfo]$it.P) }
function Open($proc) { $proc -and (Get-Process -Name $proc) }
function Free { $o = [ordered]@{}; foreach ($d in $drives) { $o[$d] = ([IO.DriveInfo]"${d}:\").AvailableFreeSpace }; $o }
function Sum($list) { $s = [long]0; foreach ($i in $list) { $s += $i.B }; $s }
function ByDrv($list) { $h = [ordered]@{}; foreach ($i in $list) { $k = Drv $i.P; $h[$k] = [long]$h[$k] + $i.B }; $s = @($h.Keys | Where-Object { $h[$_] -ge 1MB } | ForEach-Object { "${_}: $(Sz $h[$_])" })
  if ($s.Count -gt 1) { "$(Sz (Sum $list)) ($($s -join ', '))" } elseif ($s.Count -eq 1) { "$(Sz (Sum $list)) на диске $(@($h.Keys | Where-Object { $h[$_] -ge 1MB })[0])" } else { Sz (Sum $list) } }
# Совет по открытой программе: Discord и Telegram живут у часов после закрытия окна; есть окно — закрыть; нет окна (Edge в фоне) — почищу в другой раз
$script:winC = @{}
function HasWin($proc) { if (-not $script:winC.ContainsKey($proc)) { $script:winC[$proc] = [bool](Get-Process -Name $proc | Where-Object { $_.MainWindowHandle -ne 0 }) }; $script:winC[$proc] }
function Note($i) { $a = $i.App
  if ($i.G -eq 'chat') { "$a работает у часов. Чтобы почистить его кэш: правой кнопкой по значку у часов → «Выйти», потом запусти уборку ещё раз." }
  elseif (HasWin $i.Proc) { "$a открыт — закрой $a, чтобы почистить его кэш." }
  else { "$a работает в фоне. Его кэш почищу в следующий раз, когда $a будет закрыт." } }
# Коротко — для строки шага (полный совет — в вопросе и журнале)
function Short($i) { $a = $i.App; if ($i.G -eq 'chat') { "$a у часов" } elseif (HasWin $i.Proc) { "$a открыт" } else { "$a в фоне" } }
function StepNote($l) { $u = @($l | Select-Object -ExpandProperty App -Unique); if ($u.Count -eq 1) { Short $l[0] } else { "открыто программ: $($u.Count)" } }
function Notes($l) { $seenA = @{}; (@($l | Where-Object { -not $seenA[$_.App] -and ($seenA[$_.App] = 1) } | ForEach-Object { Note $_ }) -join ' ') }

Write-Host "`nБОЛЬШАЯ УБОРКА`n" -ForegroundColor Cyan
Step -Safe
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $Scan -and -not $admin) { Step 'Проверяю права'; Step -Fail 'нет разрешения Windows' -Do 'Запусти «Большую уборку» из Помощника и нажми «Да» в окне Windows.'; Write-Host 'Нужно разрешение Windows. Запусти «Большую уборку» из Помощника.' -ForegroundColor Yellow; Enter; return }
$lk = $null; if (-not $Scan) { $lk = PctLock 'clean'; if (-not $lk) { Step 'Проверяю, не идёт ли уборка'; Step -Fail 'уборка уже идёт' -Do 'Дождись, пока она закончится.'; Write-Host 'Уборка уже идёт. Дождись, пока она закончится.' -ForegroundColor Yellow; Enter; return } }
try {
  Jr "начал: $(if ($Scan) { 'только смотрю' } else { 'уборка' })$(if ($Fake) { ", поддельное дерево $Fake" })"
  # Экран хода не прокручивается: шагов не больше 9. Подсчёт — 3 шага, уборка — до 3 (подсчёт, уборка, группы); по каждой группе — строка в подробностях и размер в вопросе
  $ph = @(@('Считаю временные файлы и Корзину', 'Убираю временные файлы и Корзину', 'temp', 'bin'), @('Считаю кэш программ', 'Убираю кэш программ', 'web', 'chat', 'gpu'), @('Считаю обновления и отчёты о сбоях', 'Убираю обновления и отчёты о сбоях', 'upd', 'dump'))
  $wo = Map "$env:SystemDrive\Windows.old"; $wob = 0; $hasWo = Test-Path -LiteralPath $wo
  Step -Plan (@($ph | ForEach-Object { $_[0] }) + @(if ($hasWo) { 'Смотрю старую Windows' }) + @(if (-not $Scan) { 'Спрашиваю, что убрать' }))
  $free0 = Free; $sw = [Diagnostics.Stopwatch]::StartNew()
  # ---------- Смотрю ----------
  foreach ($p in $ph) { Step $p[0] -Hint 'Ничего не удаляю'; $go = @(); $off = @()
    foreach ($k in $p[2..($p.Count - 1)]) { $g = $Grp[$k]; $li = @($items | Where-Object { $_.G -eq $k })
      foreach ($i in $li) { $r = Size $i.P; $i.B = $r[0]; $i.F = $r[1]; $i.Skip = [bool](Open $i.Proc) }
      $g.Go = @($li | Where-Object { -not $_.Skip }); $g.Off = @($li | Where-Object { $_.Skip -and $_.B -gt 0 }); $g.B = Sum $g.Go; $go += $g.Go; $off += $g.Off
      foreach ($i in $li) { Write-Host "  $($i.P) — $(Sz $i.B), файлов: $($i.F)$(if ($i.Skip) { " ($(Short $i) — пропущу)" })" -ForegroundColor DarkGray } }
    $t = $(if ((Sum $go) -ge 1MB) { ByDrv $go } else { 'пусто' }); if ($off) { Step -Warn "$t, $(StepNote $off)"; Jr "совет: $(Notes $off)" } else { Step -Done $t } }
  if ($hasWo) { Step 'Смотрю старую Windows' -Hint 'Ничего не удаляю, до минуты'; $wob = (Size $wo)[0]; Step -Done "$(Sz $wob), разберём во второй части" }
  $scanMs = $sw.ElapsedMilliseconds; Jr "посмотрел за $scanMs мс"
  $all = [long]0; foreach ($k in $Grp.Keys) { $all += $Grp[$k].B }
  Write-Host ''; Write-Host "Можно убрать: $(Sz $all)" -ForegroundColor White
  foreach ($k in $Grp.Keys) { $g = $Grp[$k]; if ($g.B -ge 1MB) { Write-Host "  $($g.N) — $(ByDrv $g.Go)" } }
  foreach ($k in $Grp.Keys) { $g = $Grp[$k]; if ($g.Off) { Write-Host "  $(Notes $g.Off)" -ForegroundColor Yellow } }
  if ($wob) { Write-Host "Старая Windows (Windows.old) — $(Sz $wob)." }
  Write-Host 'Старую Windows, большие файлы, программы и одинаковые файлы — это разберём во второй части.' -ForegroundColor DarkGray
  if ($Scan) { Write-Host "`nЯ только посмотрел, ничего не удалял. Смотрел $([math]::Round($scanMs / 1000.0, 1).ToString($ru)) с." -ForegroundColor Green; return }
  # ---------- Спрашиваю ----------
  Step 'Спрашиваю, что убрать' -Hint 'Ответь на вопросы ниже'; $pick = @()
  $ask = @($Grp.Keys | Where-Object { $Grp[$_].B -ge 1MB })
  foreach ($k in $ask) { $g = $Grp[$k]; $rec = $(if ($g.Small -and $g.B -lt 50MB) { 'Не нужно: места освободится совсем мало.' } else { $g.Rec })
    $off = ''; if ($g.Off) { $off = " $(Notes $g.Off)" }
    Write-Host "$($g.N) — $(ByDrv $g.Go). $($g.What)$off" -ForegroundColor White; Write-Host "$($g.After) $rec"
    $ans = Read-Host "$($g.Q) (д/н)"; if ("$ans".Trim() -match '^(?i)(д|да|y|yes|l)') { $pick += $k; Jr "она выбрала: $($g.N), $(Sz $g.B)" } }
  if (-not $pick) { Step -Done $(if ($ask) { 'ничего не убираю' } else { 'мусора почти нет' }); Write-Host "`n$(if ($ask) { 'Ничего не удалил: ты не выбрала ни одной группы.' } else { 'Мусора почти нет — убирать нечего.' })" -ForegroundColor Green; return }
  Step -Done "убрать: $($pick.Count) из $($ask.Count)"
  # ---------- Убираю: шаг на часть (одна выбранная группа — её подпись), в подсказке — сколько уже освобождено, в подробностях — что удаляю сейчас ----------
  $cl = foreach ($p in $ph) { $pk = @($p[2..($p.Count - 1)] | Where-Object { $pick -contains $_ }); if ($pk) { [pscustomobject]@{ T = $(if ($pk.Count -eq 1) { $Grp[$pk[0]].U } else { $p[1] }); K = $pk } } }
  Step -Plan (@($cl | ForEach-Object { $_.T }) + @('Сравниваю место до и после'))
  Step -Unsafe; $upBusy = (Get-Process -Name TiWorker) -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or ($Fake -and $env:PCT_CLEAN_UPBUSY)
  $script:winC = @{}
  foreach ($c in $cl) { Step $c.T -Hint $(if ($script:freed) { "Освобождено пока $(Sz $script:freed)" } else { 'Документы, фото и пароли не трогаю' }); $f0 = $script:freed; $b0 = $script:busy; $sk = @(); $upw = $false
    foreach ($i in @($c.K | ForEach-Object { $Grp[$_].Go })) {
      if (Open $i.Proc) { $sk += $i; continue }
      if ($upBusy -and $i.L -eq 'загрузки обновлений Windows') { $upw = $true; continue }
      Write-Host "  убираю: $($i.P)" -ForegroundColor DarkGray; Wipe $i }
    $sk += @($c.K | ForEach-Object { $Grp[$_].Off })
    $sn = @(); $sl = @(); if ($sk) { $sn += StepNote $sk; $sl += Notes $sk }; if ($upw) { $sn += 'Windows ставит обновления'; $sl += 'Windows ставит обновления — пропустил' }
    $w = $sl -join ' '
    $t = "$(Sz ($script:freed - $f0))$(if ($script:busy -gt $b0) { ", занято файлов: $($script:busy - $b0)" })"; Jr "$($c.T): освобождено $t$(if ($w) { "; $w" })"
    if ($w) { Step -Warn "$t, $($sn -join ', ')"; Write-Host "  $w" -ForegroundColor Yellow } else { Step -Done $t } }
  # ---------- Было → стало ----------
  Step 'Сравниваю место до и после'; Start-Sleep -Milliseconds 300; $free1 = Free
  $ba = @($drives | ForEach-Object { "${_}: $(($free0[$_] / 1GB).ToString('0.0', $ru)) → $(($free1[$_] / 1GB).ToString('0.0', $ru)) ГБ" })
  Write-Host ''; Write-Host "Освободил $(Sz $script:freed)." -ForegroundColor Green
  foreach ($d in $drives) { Write-Host "Свободно на ${d}: было $(Sz $free0[$d]) → стало $(Sz $free1[$d])" -ForegroundColor White }
  $n = $script:busy; $m = $n % 100; $k = $n % 10; $nf = $(if ($m -ge 11 -and $m -le 14) { 'файлов заняты' } elseif ($k -eq 1) { 'файл занят' } elseif ($k -ge 2 -and $k -le 4) { 'файла заняты' } else { 'файлов заняты' })
  if ($n) { Write-Host "$n $nf — это нормально: так бывает, когда программа открыта." -ForegroundColor DarkGray }
  Step -Done "освобождено $(Sz $script:freed) · свободно $($ba -join ' · ')"; Jr "готово: освобождено $(Sz $script:freed), занято файлов $($script:busy), $($ba -join ', ')"
} finally { PctUnlock $lk; if (-not $Scan) { Enter } }
