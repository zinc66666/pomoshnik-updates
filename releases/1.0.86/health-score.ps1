# Оценка здоровья компьютера (9al, HEALTH-1): короткие повторяемые тесты по областям → балл 0–100 по области, общий — по самому слабому месту (минимум по областям), история оценок.
# -Quick (≤ 10 с): диск (место, исправность), память, включение, сеть, защита, надёжность. -Full (≤ 60 с): плюс фон (15 с покоя), скорость записи диска (файл 256 МБ во временной папке, удаляется и при сбое),
# процессор (фиксированная работа на всех ядрах и частота под ней). Полная — не во время игры на весь экран и не на батарее < 30 %: честный отказ. Без прав администратора; систему не меняю.
# Пишу только временный файл теста скорости и %LOCALAPPDATA%\Pomoshnik\health.json (история, до 200 оценок), из окна (-Arg) — ещё health-last.json рядом. -Json <файл> — итог для окна. -Why — повод оценки (в историю). -Lib — только функции (тесты).
# Источник числа (как TRUST-LABELS): m — замерил сам, w — по данным Windows, a — примерно. Нет данных — балл $null («не знаю»): в общий не входит и нулём не становится. Батарея — только совет, в общий не входит.
# Стенд: PCT_HEALTH_FAKE=<файл JSON> — факты вместо замеров: disk, mem, boot, bg, cpu, net, guard, rel, bat, game. PCT_HEALTH_DISKFAIL=<МБ> — сбой теста скорости после стольких МБ, PCT_HEALTH_DISKHOLD=<мс> — пауза после каждых 4 МБ (удаление файла при сбое и убитом процессе)
# -Arg — для окна через run.ps1 (он передаёт один параметр): quick | full, повод — после точки (quick.big-clean — после инструмента big-clean). Успешная оценка из окна — ещё и в health-last.json (итог для экрана «Здоровье компьютера»)
param([string]$Json, [switch]$Quick, [switch]$Full, [string]$Why = '', [switch]$Lib, [string]$Arg = '')
if ($Arg -match '^(quick|full)(?:\.([A-Za-z0-9_-]{1,40}))?$') { if ($Matches[1] -eq 'full') { $Full = [switch]$true } else { $Quick = [switch]$true }; if ($Matches[2]) { $Why = $Matches[2] } }
$HsLib = $Lib; if (-not $HsLib) { $ErrorActionPreference = 'SilentlyContinue' }
. "$PSScriptRoot\pct-core.ps1"
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
# RvDisk — тип диска с Windows (HDD/SSD) и место: один расчёт с «Почему тормозит». Дот-источник задаёт и $Lib — свой флаг сохранён выше
. "$PSScriptRoot\revive.ps1" -Lib
$HsRu = [Globalization.CultureInfo]'ru-RU'; $HsU8 = New-Object Text.UTF8Encoding $false
$HsOrder = 'disk', 'boot', 'bg', 'mem', 'cpu', 'net', 'rel', 'guard', 'bat'

# ---------- Шкалы и области (чистые функции: факты → балл) ----------
# Кусочно-линейная шкала: $P — пары «порог, балл» по возрастанию порога; между порогами — по прямой, за краями — крайний балл. Шум замера двигает балл на единицы, а не ступенькой
function HsLin([double]$X, [double[]]$P) { $n = $P.Count; if ($X -le $P[0]) { return [int]$P[1] }
  for ($i = 2; $i -lt $n; $i += 2) { if ($X -le $P[$i]) { $x0 = $P[$i - 2]; $y0 = $P[$i - 1]; return [int][math]::Round($y0 + ($P[$i + 1] - $y0) * ($X - $x0) / ($P[$i] - $x0)) } }
  [int]$P[$n - 1] }
function HsN($V, [string]$F = 'N0') { ([double]$V).ToString($F, $HsRu) }
function HsPl([int]$N, [string]$One, [string]$Few, [string]$Many) { $m = $N % 100; if ($m -ge 11 -and $m -le 14) { $Many } elseif ($N % 10 -eq 1) { $One } elseif ($N % 10 -in 2, 3, 4) { $Few } else { $Many } }
function HsP($S, [string]$D) { [pscustomobject]@{ S = $S; D = $D } }
# Область: части «балл, что тянет вниз»; балл области — худшая часть, «что тянет вниз» — её текст, если балл ниже 90. Ни одной части — $null («не знаю»)
# Равные баллы — первая по порядку часть (Sort-Object в 5.1 порядок равных не держит)
function HsArea([string]$Key, [string]$Name, [string]$Src, [string]$Line, $Parts, $N, [switch]$Advice) { $s = $null; $d = ''
  foreach ($x in @($Parts)) { if ($null -ne $x.S -and ($null -eq $s -or [int]$x.S -lt $s)) { $s = [int]$x.S; $d = $x.D } }; if ($null -eq $s -or $s -ge 90) { $d = '' }
  [pscustomobject][ordered]@{ key = $Key; name = $Name; score = $s; line = $Line; down = $d; src = $Src; advice = [bool]$Advice; n = $N } }

# Диск: место на диске с Windows, HDD, исправность и износ всех дисков, скорость записи (полная)
function HsDiskA($D) { if (-not $D) { return HsArea 'disk' 'Диск' 'w' 'Нет данных о диске' @() $null }; $p = @(); $pc = $null; $l = @()
  if ($D.sizeGB -gt 0 -and $null -ne $D.freeGB) { $pc = 100 * $D.freeGB / $D.sizeGB; $l += "Свободно $(HsN $pc) %"
    # Главное — ГБ (обновлениям и временным файлам нужно 20–40 ГБ при любом размере диска); процент — только почти полный SSD (меньше 8 % — пишет медленнее)
    $p += HsP ([math]::Min((HsLin $D.freeGB 2, 10, 5, 30, 10, 50, 20, 70, 40, 90, 60, 100), (HsLin $pc 3, 40, 5, 60, 8, 85, 10, 100))) 'мало места' }
  if ($D.media -eq 'HDD') { $p += HsP 60 'HDD — медленный диск'; $l = @('HDD') + $l }
  if ($D.health -and "$($D.health)" -notin 'Healthy', '0') { $p += HsP 10 'диск сообщает о неисправности' }
  if ($null -ne $D.temp) { $p += HsP (HsLin $D.temp 55, 100, 65, 60, 75, 40) 'диск горячий' }
  if ($null -ne $D.write) { $p += HsP (HsLin $D.write 20, 15, 50, 35, 100, 55, 200, 75, 400, 90, 800, 100) 'медленная запись'; $l += "запись $(HsN $D.write) МБ/с" } elseif ($D.writeNote) { $l += "запись — $($D.writeNote)" }
  if ($null -ne $D.wear) { $p += HsP (HsLin $D.wear 50, 100, 70, 60, 90, 30) 'диск изношен'; $l += "износ $(HsN $D.wear) %" } else { $l += 'износ не знаю' }
  HsArea 'disk' 'Диск' $(if ($null -ne $D.write) { 'm' } else { 'w' }) ($l -join ' · ') $p ([ordered]@{ freePct = $(if ($null -ne $pc) { [math]::Round($pc, 1) } else { $null }); freeGB = $D.freeGB; media = $D.media; write = $D.write; wear = $D.wear; temp = $D.temp }) }
# Память: доступно (с резервным списком, как «Доступно» в диспетчере задач), объём, выгрузка на диск
function HsMemA($M) { if (-not $M -or -not $M.totalGB) { return HsArea 'mem' 'Память' 'w' 'Нет данных о памяти' @() $null }; $t = [double]$M.totalGB
  $p = @(); if ($null -ne $M.availGB) { $p += HsP (HsLin (100 * $M.availGB / $t) 5, 15, 10, 35, 20, 65, 30, 85, 40, 100) 'мало свободной памяти' }
  $cap = $(if ($t -lt 5) { 45 } elseif ($t -lt 7) { 60 } elseif ($t -lt 9.5) { 85 }); if ($cap) { $p += HsP $cap "всего $(HsN $t) ГБ памяти" }
  if ($null -ne $M.pageGB) { $p += HsP (HsLin ($M.pageGB / $t) 0.25, 100, 0.5, 75, 1, 50) 'Windows выгружает память на диск' }
  $pl = $(if ($null -eq $M.pageGB) { 'выгрузка — не знаю' } elseif ($M.pageGB -lt 0.25 * $t) { 'выгрузка мала' } else { "выгружено $(HsN $M.pageGB 'N1') ГБ" })
  HsArea 'mem' 'Память' 'w' "$(if ($null -ne $M.availGB) { "Свободно $(HsN $M.availGB 'N1') из $(HsN $t) ГБ" } else { "Всего $(HsN $t) ГБ, свободно не знаю" }) · $pl" $p ([ordered]@{ availGB = $(if ($null -ne $M.availGB) { [math]::Round($M.availGB, 1) } else { $null }); totalGB = [math]::Round($t, 1); pageGB = $M.pageGB }) }
# Включение: старт ядра → вход → автозапуск отработал (журналы без прав). Вход позже 60 с после старта — ждал пароль: до входа не знаю, балл по времени после входа
function HsBootA($B) { if (-not $B) { return HsArea 'boot' 'Включение' 'w' 'Нет данных о включении' @() $null }; $p = @(); $l = @()
  if ($null -ne $B.sec) { $p += HsP (HsLin $B.sec 20, 100, 40, 90, 60, 70, 90, 50, 120, 35, 180, 20) 'долгое включение'; $l += "Включается $(HsN $B.sec) с" }
  elseif ($null -ne $B.after) { $p += HsP (HsLin $B.after 10, 100, 30, 85, 60, 60, 120, 35) 'долгий запуск после входа'; $l += "После входа $(HsN $B.after) с, до входа не знаю (ждал пароль)" }
  else { $l += 'Время включения не знаю' }
  if ($null -ne $B.autorun) { $p += HsP (HsLin $B.autorun 8, 100, 12, 85, 20, 65, 30, 45) 'много программ в автозапуске'; $l += "$($B.autorun) $(HsPl $B.autorun 'программа' 'программы' 'программ') в автозапуске" }
  HsArea 'boot' 'Включение' $(if ($null -eq $B.sec -and $null -ne $B.after) { 'a' } else { 'w' }) ($l -join ' · ') $p ([ordered]@{ sec = $B.sec; after = $B.after; autorun = $B.autorun }) }
# Фон: процессор и диск в покое (полная, 15 с)
function HsBgA($G) { if (-not $G) { return HsArea 'bg' 'Фон' 'm' 'Только в полной проверке' @() $null }; $p = @()
  if ($null -ne $G.cpu) { $p += HsP (HsLin $G.cpu 3, 100, 8, 85, 15, 65, 30, 40, 50, 20) $(if ($G.top) { "фон грузит процессор: $($G.top)" } else { 'фон грузит процессор' }) }
  if ($null -ne $G.disk) { $p += HsP (HsLin $G.disk 5, 100, 15, 85, 30, 65, 60, 35, 90, 15) 'фон грузит диск' }
  HsArea 'bg' 'Фон' 'm' "В покое процессор $(if ($null -ne $G.cpu) { "$(HsN $G.cpu) %" } else { 'не знаю' }), диск $(if ($null -ne $G.disk) { "$(HsN $G.disk) %" } else { 'не знаю' })" $p ([ordered]@{ cpu = $G.cpu; disk = $G.disk; top = $G.top }) }
# Процессор: частота под фиксированной работой (% от обычной; перегрев и слабое питание её сбрасывают) и время работы против своей медианы из истории. На батарее — не знаю
function HsCpuA($C) { if (-not $C) { return HsArea 'cpu' 'Процессор' 'm' 'Только в полной проверке' @() $null }
  $n = [ordered]@{ perf = $C.perf; work = $C.work; base = $C.base; ac = $C.ac; busy = $C.busy }
  if ($C.ac -eq $false) { return HsArea 'cpu' 'Процессор' 'm' 'На батарее Windows снижает частоту — проверю от сети' @() $n }
  $p = @(); $l = @(); if ($null -ne $C.perf) { $p += HsP (HsLin $C.perf 50, 25, 70, 50, 85, 75, 95, 100) 'под нагрузкой сбрасывает частоту — перегрев или питание'
    $l += $(if ($C.perf -ge 95) { 'Под нагрузкой частоту не сбрасывает' } else { "Под нагрузкой частота $(HsN $C.perf) % от обычной" }) } else { $l += 'Частоту под нагрузкой не знаю' }
  # Своё «обычное» сравниваю только на тихой машине: фон ≥ 10 % (чужая работа) сам растягивает фиксированную работу
  if ($C.work) { $l += "работа $(HsN $C.work 'N1') с"; if ($C.base -and $C.busy -ge 10) { $l += 'с обычным не сравнивал — фон занят' } elseif ($C.base) { $r = $C.work / $C.base; $p += HsP (HsLin $r 1.15, 100, 1.4, 70, 2, 40) "медленнее обычного на $(HsN (($r - 1) * 100)) %" } }
  HsArea 'cpu' 'Процессор' 'm' ($l -join ' · ') $p $n }
# Сеть: отклик ya.ru; обход блокировок — только если он настроен
function HsNetA($N) { if (-not $N) { return HsArea 'net' 'Сеть' 'm' 'Нет данных о сети' @() $null }; $p = @()
  # До 100 мс сайты и видео не замечают отклика; 150 — порог «медленно» в «Состоянии»
  if ($null -eq $N.ms) { $p += HsP 10 'нет связи с интернетом'; $l = 'Нет связи с ya.ru' } else { $p += HsP (HsLin $N.ms 50, 100, 100, 90, 150, 70, 300, 40, 600, 20) 'медленный отклик сети'; $l = "Отклик $(HsN $N.ms) мс$(if ($N.via -eq 'https') { ' (пинг закрыт, по HTTPS)' })" }
  if ($N.zapret -eq $false) { $p += HsP 55 'обход блокировок выключен'; $l += ' · обход выключен' } elseif ($N.zapret -eq $true) { $l += ' · обход работает' }
  HsArea 'net' 'Сеть' 'm' $l $p ([ordered]@{ ms = $N.ms; via = $N.via; zapret = $N.zapret }) }
# Защита: UAC, брандмауэр, антивирус, расширения файлов, предупреждения сторожей за неделю. Не прочитал — часть «не знаю»
function HsGuardA($G) { if (-not $G) { return HsArea 'guard' 'Защита' 'w' 'Нет данных о защите' @() $null }; $p = @(); $l = @()
  if ($null -ne $G.uac -or $null -ne $G.av -or $null -ne $G.fwOff) { $p += HsP 100 '' }
  if ($G.uac -eq $false) { $p += HsP 30 'контроль UAC выключен'; $l += 'UAC выключен' }
  $l += $(if ($G.av -eq $true) { 'Антивирус работает' } elseif ($G.av -eq $false) { $p += HsP 40 'антивирус выключен'; 'Антивирус выключен' } else { 'Антивирус — не знаю' })
  if ($null -eq $G.fwOff) { $l += 'брандмауэр — не знаю' } elseif (@($G.fwOff).Count) { $p += HsP 40 'брандмауэр выключен'; $l += 'брандмауэр выключен' }
  if ($G.extHidden -eq $true) { $p += HsP 85 'расширения файлов скрыты'; $l += 'расширения скрыты' } elseif ($G.extHidden -eq $false) { $l += 'расширения видны' }
  if ($G.alerts -gt 0) { $p += HsP 70 'сторож заметил подозрительное'; $l += "предупреждений сторожа: $($G.alerts)" }
  HsArea 'guard' 'Защита' 'w' ($l -join ' · ') $p ([ordered]@{ uac = $G.uac; av = $G.av; fwOff = $G.fwOff; extHidden = $G.extHidden; alerts = $G.alerts }) }
# Надёжность за 7 дней: синие экраны, аварийные выключения, частые вылеты программ, устройства с ошибкой, ошибки диска в журнале
function HsRelA($R) { if (-not $R) { return HsArea 'rel' 'Надёжность' 'w' 'Нет данных о сбоях' @() $null }; $p = @(HsP 100 '')
  if ($R.bsod -gt 0) { $p += HsP (HsLin $R.bsod 1, 50, 3, 20) 'синий экран' }; if ($R.kp -gt 0) { $p += HsP (HsLin $R.kp 1, 70, 3, 40) 'аварийные выключения' }
  if ($R.apps -gt 0) { $p += HsP 80 $(if ($R.app) { "часто вылетает $($R.app)" } else { 'часто вылетает программа' }) }; if ($R.drv -gt 0) { $p += HsP 75 'устройство работает с ошибкой' }
  if ($R.diskErr -gt 0) { $p += HsP (HsLin $R.diskErr 1, 40, 5, 20) 'ошибки диска в журнале' }
  $l = "Сбоев за неделю: $([int]$R.bsod + [int]$R.kp) · ошибок диска: $([int]$R.diskErr)" + $(if ($R.apps -gt 0) { " · часто вылетают: $($R.apps)" } else { '' })
  HsArea 'rel' 'Надёжность' 'w' $l $p ([ordered]@{ bsod = $R.bsod; kp = $R.kp; apps = $R.apps; drv = $R.drv; diskErr = $R.diskErr }) }
# Батарея — только совет (в общий не входит): износ по ёмкости и циклы
function HsBatA($B) { if (-not $B -or -not $B.present) { return HsArea 'bat' 'Батарея' 'w' 'Батареи нет — это ПК' @() $null -Advice }; $p = @(); $l = @()
  if ($null -ne $B.wear) { $p += HsP (HsLin $B.wear 20, 100, 40, 70, 60, 40) 'аккумулятор изношен'; $l += "Износ $(HsN $B.wear) %" } else { $l += 'Износ не знаю' }
  if ($B.cycles) { if ($B.cycles -ge 800) { $p += HsP 70 'много циклов зарядки' }; $l += "циклов $($B.cycles)" }
  if ($null -ne $B.charge) { $l += "заряд $($B.charge) %$(if ($B.ac) { ', от сети' } else { ', от батареи' })" }
  HsArea 'bat' 'Батарея' 'w' ($l -join ' · ') $p ([ordered]@{ wear = $B.wear; cycles = $B.cycles; charge = $B.charge; ac = $B.ac }) -Advice }
# Все области по фактам; общий — минимум по областям с баллом (без совета): одно слабое место видно сразу, хорошие его не прячут
function HsAreas($F) { @((HsDiskA $F.disk), (HsBootA $F.boot), (HsBgA $F.bg), (HsMemA $F.mem), (HsCpuA $F.cpu), (HsNetA $F.net), (HsRelA $F.rel), (HsGuardA $F.guard), (HsBatA $F.bat)) }
function HsTotal($Areas) { $t = $null; foreach ($a in $Areas) { if (-not $a.advice -and $null -ne $a.score -and ($null -eq $t -or $a.score -lt $t)) { $t = $a.score } }; $t }
# Слабые сверху (как в макете), «не знаю» и совет — в конце; равные — в порядке $HsOrder
function HsSort($Areas) { @($Areas | Sort-Object @{ e = { if ($_.advice) { 1000 } elseif ($null -eq $_.score) { 999 } else { $_.score } } }, @{ e = { [array]::IndexOf($HsOrder, $_.key) } }) }
# Полную не запускаю во время игры или фильма на весь экран и на батарее < 30 % без зарядки: '' — можно, иначе причина
function HsGate($F) { $g = $(if ($null -ne $F -and $null -ne $F.game) { [bool]$F.game } else { PctFull }); if ($g) { return 'game' }
  $b = $(if ($null -ne $F) { $F.bat } else { HsBatF }); if ($b.present -and $b.ac -eq $false -and $null -ne $b.charge -and $b.charge -lt 30) { return 'battery' }; '' }

# ---------- Замеры (только чтение; запись — только файл теста скорости) ----------
function HsFake { if ($env:PCT_HEALTH_FAKE) { [IO.File]::ReadAllText($env:PCT_HEALTH_FAKE) | ConvertFrom-Json } }
function HsDiskF { $r = RvDisk; $ds = @(PctDisks); $bad = @($ds | Where-Object { $_.Pd.HealthStatus -ne 'Healthy' -and $_.Pd.HealthStatus -ne 0 })
  $w = @($ds | ForEach-Object { $_.Rc.Wear } | Where-Object { $null -ne $_ } | Measure-Object -Maximum); $t = @($ds | ForEach-Object { $_.Rc.Temperature } | Where-Object { $_ } | Measure-Object -Maximum)
  [pscustomobject]@{ media = $r.Media; freeGB = $r.FreeGB; sizeGB = $r.SizeGB; health = $(if (-not $ds.Count) { $null } elseif ($bad.Count) { "$($bad[0].Pd.HealthStatus)" } else { 'Healthy' })
    wear = $(if ($w[0].Count) { [int]$w[0].Maximum } else { $null }); temp = $(if ($t[0].Count) { [int]$t[0].Maximum } else { $null }); write = $null; writeNote = '' } }
function HsMemF { $o = Get-CimInstance Win32_OperatingSystem; if (-not $o) { return }; $pf = @(Get-CimInstance Win32_PageFileUsage)
  [pscustomobject]@{ totalGB = $o.TotalVisibleMemorySize / 1MB; availGB = $o.FreePhysicalMemory / 1MB; pageGB = $(if ($pf.Count) { [math]::Round(($pf | Measure-Object CurrentUsage -Sum).Sum / 1KB, 1) } else { $null }) } }
# Журнал Diagnostics-Performance (событие 100) без прав не читается. Беру: старт ядра (Kernel-General 12, StartTime) → вход (Winlogon 7001) → автозапуск отработал (Shell-Core 9706, последнее за 3 мин после входа)
# Автозапуск — как считает «Автозагрузка» (PctRcAutorun): отключённые в диспетчере задач не в счёт
function HsBootF { $b = [pscustomobject]@{ sec = $null; after = $null; autorun = PctRcAutorun }
  $k = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-General'; Id = 12 } -MaxEvents 1; if (-not $k) { return $b }
  $st = "$(@(([xml]$k.ToXml()).Event.EventData.Data | Where-Object { $_.Name -eq 'StartTime' })[0].'#text')"; if (-not $st) { return $b }; $st = ([datetime]$st).ToLocalTime()
  $lg = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Winlogon'; Id = 7001; StartTime = $st; EndTime = $st.AddHours(12) })[-1]; if (-not $lg) { return $b }
  $sh = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Shell-Core/Operational'; Id = 9706; StartTime = $lg.TimeCreated; EndTime = $lg.TimeCreated.AddMinutes(3) })[0]; if (-not $sh) { return $b }
  $bf = ($lg.TimeCreated - $st).TotalSeconds; $af = [math]::Round(($sh.TimeCreated - $lg.TimeCreated).TotalSeconds)
  $b.after = $af; if ($bf -le 60) { $b.sec = [math]::Round($bf + $af) }; $b }
# Фон: 15 с покоя, 5 окон по 3 с, медиана (один всплеск не решает). Процессор и диск — сырые счётчики WMI (_Total — среднее), «кто грузит» — разница времени процессов
function HsBgF([int]$Win = 3000, [int]$N = 5) { $q1 = { Get-CimInstance Win32_PerfRawData_PerfOS_Processor -Filter "Name='_Total'" }; $q2 = { Get-CimInstance Win32_PerfRawData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" }
  $p1 = @{}; Get-Process | ForEach-Object { $p1[$_.Id] = $_.CPU }; $t1 = Get-Date; $a = & $q1; $b = & $q2; $c = @(); $d = @()
  for ($i = 0; $i -lt $N; $i++) { Start-Sleep -Milliseconds $Win; $a2 = & $q1; $b2 = & $q2
    if ($a -and $a2 -and $a2.Timestamp_Sys100NS -gt $a.Timestamp_Sys100NS) { $c += [math]::Max(0, 100 - 100 * ($a2.PercentIdleTime - $a.PercentIdleTime) / ($a2.Timestamp_Sys100NS - $a.Timestamp_Sys100NS)) }
    if ($b -and $b2 -and $b2.PercentIdleTime_Base -gt $b.PercentIdleTime_Base) { $d += [math]::Min(100, [math]::Max(0, 100 - 100 * ($b2.PercentIdleTime - $b.PercentIdleTime) / ($b2.PercentIdleTime_Base - $b.PercentIdleTime_Base))) }
    $a = $a2; $b = $b2 }
  $sec = ((Get-Date) - $t1).TotalSeconds; $cores = [Environment]::ProcessorCount
  $top = @(Get-Process | Where-Object { $_.Id -ne $PID -and $_.Id -ne 0 -and $p1.ContainsKey($_.Id) -and $_.CPU } | ForEach-Object { [pscustomobject]@{ N = $_.ProcessName; C = ($_.CPU - $p1[$_.Id]) / $sec / $cores * 100 } } |
      Group-Object N | ForEach-Object { [pscustomobject]@{ N = $_.Name; C = ($_.Group | Measure-Object C -Sum).Sum } } | Sort-Object C -Descending)[0]
  $med = { param($x) if (-not $x.Count) { return $null }; $s = @($x | Sort-Object); [math]::Round($s[[int][math]::Floor($s.Count / 2)], 1) }
  [pscustomobject]@{ cpu = (& $med $c); disk = (& $med $d); top = $(if ($top -and $top.C -ge 2) { $top.N } else { $null }) } }
# Скорость записи: файл 256 МБ во временной папке, сквозная запись (WriteThrough — мимо кэша Windows) кусками по 4 МБ, не дольше 5 с. Чтение не меряю: файл только что записан и лежит в кэше — число было бы ложным.
# DeleteOnClose — файл удаляет сама Windows при закрытии: и при сбое, и если процесс убит; на всякий случай — проверка в finally. Свободно < 5 ГБ — не пишу. → МБ/с или $null
function HsWrite([string]$Dir = $env:TEMP, [int]$MB = 256, [int]$MaxMs = 5000) { $p = Join-Path $Dir "pct-health-$PID.tmp"; $fs = $null; $done = 0
  try { $buf = New-Object byte[] 4MB; (New-Object Random 7).NextBytes($buf); $fail = [int]"0$env:PCT_HEALTH_DISKFAIL"; $hold = [int]"0$env:PCT_HEALTH_DISKHOLD"
    $fs = New-Object IO.FileStream($p, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None, 4096, [IO.FileOptions]'WriteThrough, DeleteOnClose'); $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($done -lt $MB -and $sw.ElapsedMilliseconds -lt $MaxMs) { if ($fail -and $done -ge $fail) { throw 'сбой теста скорости (стенд)' }; $fs.Write($buf, 0, $buf.Length); $done += 4; if ($hold) { Start-Sleep -Milliseconds $hold } }
    $fs.Flush($true); $ms = $sw.Elapsed.TotalMilliseconds; if ($done -ge 32 -and $ms -gt 0) { [math]::Round($done * 1000 / $ms) } }
  catch { $null } finally { if ($fs) { $fs.Dispose() }; if ([IO.File]::Exists($p)) { Remove-Item -LiteralPath $p -Force } } }
# Процессор: фиксированная работа — каждый логический процессор считает одно и то же число корней (одинаково на любом ПК), потоки ниже обычного приоритета, потолок 15 с.
# Частота — «% Processor Performance» (_Total, доля обычной частоты) по сырым счётчикам между 1,2 с и концом работы (имена Get-Counter переведены)
$HsWorkCs = @'
using System; using System.Threading; using System.Diagnostics;
public static class PctWork { static Thread[] T; static Stopwatch W;
  public static void Go(long n, int maxMs) { int c = Environment.ProcessorCount; T = new Thread[c]; W = Stopwatch.StartNew();
    for (int i = 0; i < c; i++) { T[i] = new Thread(() => { double x = 1; for (long k = 0; k < n; k++) { x = Math.Sqrt(x + k); if ((k & 0xFFFFF) == 0 && W.ElapsedMilliseconds > maxMs) break; } if (x < 0) Console.Write(""); }); T[i].IsBackground = true; T[i].Priority = ThreadPriority.BelowNormal; T[i].Start(); } }
  public static bool Busy() { foreach (var t in T) if (t.IsAlive) return true; return false; }
  public static double Wait() { foreach (var t in T) t.Join(); return W.Elapsed.TotalSeconds; } }
'@
function HsCpuF([long]$N = 4e8, [int]$MaxMs = 15000) { $o = [pscustomobject]@{ perf = $null; work = $null; base = $null; ac = (RvDevice).AC }
  try { if (-not ('PctWork' -as [type])) { Add-Type -TypeDefinition $HsWorkCs -ErrorAction Stop } } catch { return $o }
  $q = { Get-CimInstance Win32_PerfRawData_Counters_ProcessorInformation -Filter "Name='_Total'" }; $null = & $q
  [PctWork]::Go($N, $MaxMs); $a = $null; $b = $null
  try { Start-Sleep -Milliseconds 1200; $a = & $q; while ([PctWork]::Busy()) { $b = & $q; Start-Sleep -Milliseconds 250 } } finally { $s = [PctWork]::Wait() }
  # Упёрся в потолок — работа не закончена: время не число «работы» (не в балл и не в базу), частоту беру
  if ($s -lt $MaxMs / 1000) { $o.work = [math]::Round($s, 2) }; if ($a -and $b) { $db = [double]$b.PercentProcessorPerformance_Base - [double]$a.PercentProcessorPerformance_Base
    if ($db -gt 0) { $o.perf = [math]::Round(([double]$b.PercentProcessorPerformance - [double]$a.PercentProcessorPerformance) / $db) } }; $o }
# Отклик: пинг ya.ru; пинг закрыт (роутер, VPN, сеть на работе) — время TCP-соединения с https://ya.ru (без поиска имени), иначе «нет связи» было бы ложным
function HsNetF($Job) { $z = $null; if ([IO.File]::Exists("$(PctDir 'helpers')\zapret-cmd.txt")) { $z = [bool](Get-Process winws) }; $m = PctPing $Job; $v = 'ping'
  if ($null -eq $m) { $v = $null; $c = "$(& curl.exe -s -o NUL -w '%{http_code} %{time_namelookup} %{time_connect}' --max-time 4 https://ya.ru 2>$null)"
    if ($c -match '^[1-5]\d\d ([\d.]+) ([\d.]+)$') { $m = ([double]$Matches[2] - [double]$Matches[1]) * 1000; $v = 'https' } }
  [pscustomobject]@{ ms = $(if ($null -ne $m) { [math]::Round($m) } else { $null }); via = $v; zapret = $z } }
# Антивирус — Центр безопасности (root\SecurityCenter2, без прав; на Windows Server нет — не знаю): включён, если в productState поле состояния (биты 12–15) = 1
function HsGuardF { $fw = @(PctFw); $av = $null; $ap = @(Get-CimInstance -Namespace root\SecurityCenter2 AntiVirusProduct); if ($ap.Count) { $av = [bool]@($ap | Where-Object { (([int]$_.productState -shr 12) -band 0xF) -eq 1 }).Count }
  $he = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced').HideFileExt
  # Журнал — reports\alerts.log (U1b). PctData не зову: он переносит старый журнал из guard\ (запись) — это делает «Состояние»
  $al = "$(PctDir 'reports')\alerts.log"
  $off = $null; if ($fw.Count) { $off = [string[]]@($fw | Where-Object { -not $_.Enabled } | ForEach-Object { "$($_.Name)" }) }
  [pscustomobject]@{ uac = $(if ($null -ne ($u = PctUac)) { [bool]$u } else { $null }); av = $av; fwOff = $off; extHidden = ($null -eq $he -or $he -ne 0); alerts = @(PctAlerts (Get-Date).AddDays(-7) $al).Count } }
function HsRelF { $s = (Get-Date).AddDays(-7); $c = PctCrash $s; $ab = @($c.Apps | Where-Object Count -ge 3)
  $de = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'disk', 'Microsoft-Windows-Ntfs'; Id = 7, 51, 153, 55; StartTime = $s }).Count
  [pscustomobject]@{ bsod = $c.Bsod; kp = $c.Kp; apps = $ab.Count; app = $(if ($ab.Count) { "$($ab[0].Name)" } else { $null }); drv = $c.Drv.Count; diskErr = $de } }
function HsBatF { $x = PctBattery; if (-not $x) { return [pscustomobject]@{ present = $false } }
  [pscustomobject]@{ present = $true; charge = $x.B.EstimatedChargeRemaining; ac = $x.Ac; cycles = $x.Cy; wear = $(if ($x.Dc -and $x.Fc) { [math]::Max(0, [math]::Round(100 - $x.Fc * 100 / $x.Dc)) } else { $null }) } }

# ---------- История: %LOCALAPPDATA%\Pomoshnik\health.json, последние 200 оценок ----------
function HsHistPath { Join-Path $env:LOCALAPPDATA 'Pomoshnik\health.json' }
# Файл испорчен или его нет — история с нуля (без исключения)
function HsHist { try { $o = [IO.File]::ReadAllText((HsHistPath)) | ConvertFrom-Json -ErrorAction Stop; @($o.items | Where-Object { $_ }) } catch { @() } }
function HsHistAdd($R, [int]$Max = 200) { $p = HsHistPath; $d = Split-Path $p; [void][IO.Directory]::CreateDirectory($d); $a = [ordered]@{}; foreach ($x in $R.areas) { $a[$x.key] = $x.score }
  $e = [pscustomobject][ordered]@{ t = $R.t; kind = $R.kind; total = $R.total; why = $R.why; sec = $R.sec; areas = [pscustomobject]$a; work = $null }
  # В базу процессора — только замер от сети и на тихой машине: на батарее Windows режет частоту, чужая работа растягивает время
  $c = @($R.areas | Where-Object { $_.key -eq 'cpu' })[0].n; if ($c -and $c.ac -ne $false -and -not ($c.busy -ge 10)) { $e.work = $c.work }
  $all = @(HsHist) + $e; if ($all.Count -gt $Max) { $all = $all[($all.Count - $Max)..($all.Count - 1)] }
  $j = [pscustomobject][ordered]@{ schema = 1; items = $all } | ConvertTo-Json -Depth 5
  # Через временный файл и Replace: оборванная запись не портит историю. $null в string PowerShell передаёт как '' — нужен [NullString]
  $t = "$p.$PID.tmp"; try { if ([IO.File]::Exists($p)) { [IO.File]::WriteAllText($t, $j, $HsU8); [IO.File]::Replace($t, $p, [NullString]::Value) } else { [IO.File]::WriteAllText($p, $j, $HsU8) }; $true }
  catch { $false } finally { if ([IO.File]::Exists($t)) { Remove-Item -LiteralPath $t -Force } } }
# «Обычное» время работы процессора на этом ПК: медиана последних 5 полных оценок
function HsCpuBase { $w = @(HsHist | Where-Object { $_.kind -eq 'full' -and $_.work } | Select-Object -Last 5 | ForEach-Object { [double]$_.work } | Sort-Object); if ($w.Count) { $w[[int][math]::Floor($w.Count / 2)] } else { $null } }
# Итог для экрана окна: %LOCALAPPDATA%\Pomoshnik\health-last.json — только успешная оценка (отказ и «уже идёт» не затирают прошлый итог). Через временный файл, как история
function HsLastPath { Join-Path $env:LOCALAPPDATA 'Pomoshnik\health-last.json' }
function HsLast($R) { $p = HsLastPath; $t = "$p.$PID.tmp"; try { [void][IO.Directory]::CreateDirectory((Split-Path $p)); $j = $R | ConvertTo-Json -Depth 6; if ([IO.File]::Exists($p)) { [IO.File]::WriteAllText($t, $j, $HsU8); [IO.File]::Replace($t, $p, [NullString]::Value) } else { [IO.File]::WriteAllText($p, $j, $HsU8) }; $true }
  catch { $false } finally { if ([IO.File]::Exists($t)) { Remove-Item -LiteralPath $t -Force } } }
function HsSave($R) { if ($Json) { try { $jd = Split-Path $Json; if ($jd) { [void][IO.Directory]::CreateDirectory($jd) }; [IO.File]::WriteAllText($Json, ($R | ConvertTo-Json -Depth 6), $HsU8) } catch { Write-Host "Итог для окна не записался: $($_.Exception.Message)" -ForegroundColor Yellow } } }
if ($HsLib) { return }

# ---------- Оценка ----------
# -Quick и -Full вместе — быстрая (без долгих замеров); ни одного — тоже быстрая
if ($Quick) { $Full = [switch]$false }; # -Json — полный путь: .NET пишет от своей текущей папки, не от папки PowerShell
if ($Json) { $Json = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Json) }
$kind = $(if ($Full) { 'full' } else { 'quick' }); $sw = [Diagnostics.Stopwatch]::StartNew(); $Fk = HsFake
$R = [pscustomobject][ordered]@{ schema = 1; t = (Get-Date).ToString('s'); kind = $kind; why = $Why; sec = $null; total = $null; weak = ''; areas = @(); refused = '' }
Step -Safe
$lk = PctLock 'health'; if (-not $lk) { Step 'Проверяю, не идёт ли оценка'; Step -Fail 'оценка уже идёт'; $R.refused = 'busy'; HsSave $R; return }
try {
  if ($Full) { $g = HsGate $Fk
    if ($g) { Step 'Проверяю, можно ли полную'; $m = $(if ($g -eq 'game') { 'идёт игра или фильм на весь экран — полную проверку не запускаю, чтобы не мешать' } else { 'батарея меньше 30 % без зарядки — полная проверка разрядит её; подключи зарядку' })
      Step -Fail $m; Write-Host "Полная проверка отложена: $m." -ForegroundColor Yellow; $R.refused = $g; HsSave $R; return } }
  $pl = @('Смотрю диск', 'Смотрю память', 'Смотрю включение', 'Смотрю сеть', 'Смотрю защиту и сбои за неделю'); if ($Full) { $pl = @('Слушаю фон 15 секунд') + $pl + @('Замеряю запись на диск', 'Нагружаю процессор') }
  Step -Plan $pl
  $F = [pscustomobject][ordered]@{ disk = $null; mem = $null; boot = $null; bg = $null; cpu = $null; net = $null; guard = $null; rel = $null; bat = $null }
  # Шаг — замер и сразу итог его областей (худшая: балл и что тянет вниз), как в макете
  function Done([string[]]$Key) { $a = @(HsSort @(HsAreas $F | Where-Object { $_.key -in $Key }))[0]; if ($null -eq $a.score) { Step -Done 'не знаю' } elseif ($a.down) { Step -Warn "$($a.score) · $($a.down)" } else { Step -Done "$($a.score)" } }
  if ($Full) { Step 'Слушаю фон 15 секунд' -Hint 'Ничего не запускай — меряю покой'; $F.bg = $(if ($Fk) { $Fk.bg } else { HsBgF }); Done 'bg' }
  # Пинг — фоном, пока смотрю диск, память и включение (3 пинга без пауз, ≈ 0,6 с вместо 2,4)
  $pj = $null; if (-not $Fk) { $pj = PctPingStart }
  Step 'Смотрю диск' -Hint 'Место и исправность'; $F.disk = $(if ($Fk) { $Fk.disk } else { HsDiskF }); if ($F.disk) { $F.disk | Add-Member -Force NoteProperty write $null; $F.disk | Add-Member -Force NoteProperty writeNote '' }; Done 'disk'
  Step 'Смотрю память'; $F.mem = $(if ($Fk) { $Fk.mem } else { HsMemF }); Done 'mem'
  Step 'Смотрю включение' -Hint 'Журнал Windows'; $F.boot = $(if ($Fk) { $Fk.boot } else { HsBootF }); Done 'boot'
  Step 'Смотрю сеть' -Hint 'Отклик ya.ru, до 4 с'; $F.net = $(if ($Fk) { $Fk.net } else { HsNetF $pj }); Done 'net'
  Step 'Смотрю защиту и сбои за неделю'; $F.guard = $(if ($Fk) { $Fk.guard } else { HsGuardF }); $F.rel = $(if ($Fk) { $Fk.rel } else { HsRelF }); $F.bat = $(if ($Fk) { $Fk.bat } else { HsBatF }); Done 'guard', 'rel'
  if ($Full) {
    Step 'Замеряю запись на диск' -Hint 'Файл 256 МБ, сразу удалю'
    if ($F.disk) { $v = $null; $nt = ''; if ($Fk) { $v = ([IO.File]::ReadAllText($env:PCT_HEALTH_FAKE) | ConvertFrom-Json).disk.write } elseif (-not "$env:TEMP".StartsWith("$env:SystemDrive\", 'OrdinalIgnoreCase')) { $nt = 'временная папка не на диске Windows — не мерил' } elseif ($F.disk.freeGB -lt 5) { $nt = 'мало места для теста' } else { $v = HsWrite; if ($null -eq $v) { $nt = 'не знаю' } }
      $F.disk | Add-Member -Force NoteProperty write $v; $F.disk | Add-Member -Force NoteProperty writeNote $nt }
    Done 'disk'
    Step 'Нагружаю процессор' -Hint 'Одинаковая работа на всех ядрах, до 15 с'; $F.cpu = $(if ($Fk) { $Fk.cpu } else { HsCpuF }); if ($F.cpu) { if (-not $Fk) { $F.cpu.base = HsCpuBase }; $F.cpu | Add-Member -Force NoteProperty busy $(if ($F.bg) { $F.bg.cpu } else { $null }) }; Done 'cpu' }
  $A = @(HsSort (HsAreas $F)); $R.areas = $A; $R.total = HsTotal $A; $R.sec = [math]::Round($sw.Elapsed.TotalSeconds, 1)
  # Слабое место — только «требует внимания» (< 80): 85 у 8 ГБ памяти — норма, не слабость
  $w = @($A | Where-Object { -not $_.advice -and $null -ne $_.score })[0]; if ($w -and $w.score -lt 80) { $R.weak = $w.key }
  if (-not (HsHistAdd $R)) { Write-Host 'Историю оценок записать не удалось.' -ForegroundColor Yellow }; HsSave $R; if ($Arg -and -not (HsLast $R)) { Write-Host 'Итог для окна записать не удалось.' -ForegroundColor Yellow }
  Write-Host "`nЗДОРОВЬЕ КОМПЬЮТЕРА — $(if ($Full) { 'полная' } else { 'быстрая' }) проверка, $(HsN $R.sec 'N1') с" -ForegroundColor Cyan
  foreach ($x in $A) { Write-Host ("  {0,-11} {1,4}  {2}{3}" -f $x.name, $(if ($null -eq $x.score) { '—' } else { $x.score }), $x.line, $(if ($x.down) { "  ← $($x.down)" } else { '' })) -ForegroundColor $(if ($null -eq $x.score -or $x.advice) { 'DarkGray' } elseif ($x.score -ge 80) { 'Green' } elseif ($x.score -ge 50) { 'Yellow' } else { 'Red' }) }
  Write-Host "Общий балл: $(if ($null -eq $R.total) { 'не знаю' } else { "$($R.total) из 100" })$(if ($R.weak) { " — слабое место: $(@($A | Where-Object { $_.key -eq $R.weak })[0].name.ToLower())" })" -ForegroundColor White
} finally { PctUnlock $lk }
