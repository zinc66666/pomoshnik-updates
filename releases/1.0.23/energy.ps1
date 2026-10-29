# «Энергосбережение»: смотрю тип устройства и схему питания, спрашиваю про каждую экономию, которая тормозит, меняю выбранное, замер до и после. Перед изменением — бэкап.
# -Undo — «Вернуть как было» из бэкапа. PCT_ENERGY_FAKE=<файл JSON> — подмена устройства и системы для проверки (pct-core.ps1): схемы — только копии, устройства и сеть — в файле
param([switch]$Undo)
$ErrorActionPreference = 'SilentlyContinue'
$Host.UI.RawUI.WindowTitle = 'Энергосбережение'
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
. "$PSScriptRoot\pct-core.ps1"
$ru = [Globalization.CultureInfo]'ru-RU'
function Jr($t) { try { $d = PctDir 'reports'; [void][IO.Directory]::CreateDirectory($d); [IO.File]::AppendAllText("$d\energy.log", "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $t`n", (New-Object Text.UTF8Encoding $false)) } catch {} }
function Enter { Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null }
function Yes($q) { $a = "$(Read-Host "$q (д/н)")".Trim(); Jr "вопрос: $q — ответ: $a"; $a -match '^(?i)(д|да|y|yes|l)' }
# Вопрос: заголовок и что делает — одна строка, совет — вторая, потом (д/н). Окно показывает две последние строки
function Ask2($head, $what, $rec, $q) { Write-Host "`n$head — $what" -ForegroundColor White; Write-Host $rec; Yes $q }
function P2([double]$x) { $x.ToString('0.00', $ru) }
$Fake = [bool]$env:PCT_ENERGY_FAKE
$BalG = '381b4222-f694-41f0-9685-ff5bb260df2e'; $HpG = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'; $BestG = 'ded574b5-45a0-4f42-8737-46345c09c238'
if ($Fake) { $f = PctEnFake; if ($f.balanced) { $BalG = "$($f.balanced)" }; if ($f.hp) { $HpG = "$($f.hp)" } }

# Значение настройки словами
function Tm([long]$s) { if (-not $s) { 'никогда' } elseif ($s -lt 60) { "$s с" } elseif ($s % 3600 -eq 0) { "$($s / 3600) ч" } else { "$([math]::Round($s / 60)) мин" } }
function Vt($k, [long]$v) { if ($k -eq 'usb') { $(if ($v) { 'вкл' } else { 'выкл' }) } elseif ($k -eq 'aspm') { $(if ($v -eq 0) { 'выкл' } elseif ($v -eq 1) { 'умеренная' } else { 'максимальная' }) }
  elseif ($k -eq 'wifi') { $(if ($v -eq 0) { 'максимальная производительность' } else { "экономия $v из 3" }) } elseif ($k -eq 'cpumin') { "$v %" } else { Tm $v } }
function Ovn($g) { switch ($g) { $BestG { 'лучшая производительность' } '3af9b8d9-7c97-431d-ad78-34a8bfea439f' { 'высокая производительность' } '961cc777-2547-4f9d-8174-7d86181b8a7a' { 'лучшая энергоэффективность' } default { 'сбалансированный' } } }
$KN = @{ usb = 'Приостановка USB'; aspm = 'Экономия PCI Express'; disk = 'Отключение диска'; wifi = 'Wi-Fi'; sleep = 'Сон'; video = 'Отключение экрана' }
# Фирменные программы питания: только сказать. Службы и процессы — по именам из их установщиков
function Vendors { if ($Fake) { return @((PctEnFake).vendors) }
  $m = [ordered]@{ 'Lenovo Vantage' = @('LenovoVantage*', 'ImControllerService'); 'Armoury Crate' = @('ArmouryCrate*'); 'MSI Center' = @('MSI.CentralServer', 'MSI_Center*', 'MSI Center*'); 'Dell Power Manager' = @('Dell.PowerManager*', 'DellPowerManager*', 'DPMService') }
  foreach ($k in $m.Keys) { if ((Get-Service -Name $m[$k] -ErrorAction SilentlyContinue) -or (Get-Process -Name $m[$k] -ErrorAction SilentlyContinue)) { $k } } }
function HasWifi { if ($Fake) { return [bool](PctEnFake).wifi }; [bool](Get-NetAdapter -Physical | Where-Object { $_.NdisPhysicalMedium -eq 9 }) }
# Замер: доля времени процессора на прерывания и DPC (срочные задачи устройств), 5 раз по 1 с → медиана и разброс. Задержку USB после простоя без сторонних программ не измерить
function Lat { $s = { Get-CimInstance Win32_PerfRawData_PerfOS_Processor -Filter "Name='_Total'" }; $a = & $s; $v = @()
  for ($i = 0; $i -lt 5; $i++) { Start-Sleep 1; $b = & $s; $dt = [double]($b.Timestamp_Sys100NS - $a.Timestamp_Sys100NS); if ($a -and $dt -gt 0) { $v += 100 * (($b.PercentDPCTime - $a.PercentDPCTime) + ($b.PercentInterruptTime - $a.PercentInterruptTime)) / $dt }; $a = $b }
  $v = @($v | Sort-Object); if (-not $v) { return }; [pscustomobject]@{ M = $v[[int][math]::Floor($v.Count / 2)]; Sp = $v[-1] - $v[0] } }

# Сеть рвётся — ждём, пока подбор обхода (zapret-repick) закончит проверку сайтов; $nk освобождает finally
function NetWait { $script:nk = PctNetLock { Jr 'жду: идёт подбор обхода, сеть занята'; Write-Host 'Идёт подбор обхода блокировок — он проверяет сайты. Жду, пока он закончится, чтобы не оборвать ему сеть.' -ForegroundColor Yellow }
  if (-not $script:nk) { Jr 'сеть занята дольше 15 минут — не менял'; Step -Fail 'сеть занята подбором обхода' -Do 'Подожди, пока закончится подбор обхода, и нажми «Энергосбережение» ещё раз.'; Write-Host 'Подбор обхода идёт слишком долго. Подожди и нажми «Энергосбережение» ещё раз.' -ForegroundColor Yellow; return $false }; $true }
function DoUndo { Step -Plan 'Читаю, что было', 'Возвращаю как было'; Step 'Читаю, что было'; $b = PctEnBackup
  if (-not $b) { Step -Done 'возвращать нечего'; Write-Host 'Помощник не менял энергосбережение — возвращать нечего.' -ForegroundColor Green; return }
  $n = @($b.values).Count + @($b.devices).Count + @($b.nics).Count + [int][bool]$b.copy + [int][bool]$b.overlay; Step -Done "изменений: $n"
  if (@($b.nics).Count -and -not (NetWait)) { return }
  Step 'Возвращаю как было' -Hint $(if (@($b.nics).Count) { 'Интернет пропадёт на несколько секунд' } else { 'Ничего не трогай' }); Step -Unsafe
  $r = PctEnUndo; Jr "откат: вернул $($r.Ok), не вернул: $($r.Bad -join '; ')"
  if ($r.Bad) { Step -Warn "вернул $($r.Ok), не вернул $($r.Bad.Count)"; Write-Host "Не вернул: $($r.Bad -join '; ')." -ForegroundColor Yellow
    if ($r.Bad -match 'зарядка') { Write-Host 'Подключи зарядку и нажми «Энергосбережение» ещё раз.' -ForegroundColor Yellow }; if ($b.export) { Write-Host "Схема до изменений сохранена в файле: $($b.export)" -ForegroundColor DarkGray } }
  else { Step -Done "вернул всё: $($r.Ok)"; Write-Host 'Вернул всё как было.' -ForegroundColor Green } }

Write-Host "`nЭНЕРГОСБЕРЕЖЕНИЕ`n" -ForegroundColor Cyan
Step -Safe
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $Fake -and -not $admin) { Step 'Проверяю права'; Step -Fail 'нет разрешения Windows' -Do 'Запусти «Энергосбережение» из Помощника и нажми «Да» в окне Windows.'; Write-Host 'Нужно разрешение Windows. Запусти «Энергосбережение» из Помощника.' -ForegroundColor Yellow; Enter; return }
$lk = PctLock 'energy'; if (-not $lk) { Step 'Проверяю, не идёт ли настройка'; Step -Fail 'настройка уже идёт' -Do 'Дождись, пока она закончится.'; Write-Host 'Настройка питания уже идёт. Дождись, пока она закончится.' -ForegroundColor Yellow; Enter; return }
try {
  Jr "начал: $(if ($Undo) { 'вернуть как было' } else { 'настройка' })$(if ($Fake) { ", подмена $env:PCT_ENERGY_FAKE" })"
  if ($Undo) { DoUndo; return }
  $D = PctEnDevice; $dev = $(if ($D.Laptop) { 'ноутбук' } else { 'компьютер' })
  $bk = PctEnBackup
  # Шагов мало: под списком помещается вопрос с кнопками и при 150 %
  Step -Plan (@("Смотрю, что за $dev") + @(if ($bk) { 'Спрашиваю, вернуть ли как было' }) + @('Замеряю задержки до', 'Спрашиваю, что поменять', 'Сохраняю, как было, и меняю', 'Замеряю задержки после'))
  # ---------- Смотрю ----------
  Step "Смотрю, что за $dev" -Hint 'Ничего не меняю'
  $act = PctEnActive; $sch = @(PctEnSchemes); $actN = "$(@($sch | Where-Object { $_.G -eq $act })[0].N)"; if (-not $actN) { $actN = $act }
  $ours = [bool]($bk -and $bk.copy -and $bk.copy -eq $act); $bi = $act -in (PctEnBuiltIn); $vend = @(Vendors); $wifi = HasWifi
  Write-Host "Это $dev$(if ($D.MS) { ' с современным ждущим режимом (Modern Standby)' }).$(if ($D.Laptop) { $(if ($D.AC) { ' Сейчас от сети.' } else { ' Сейчас от батареи.' }) })" -ForegroundColor White
  Write-Host "Схема питания: «$actN»$(if (-not $bi -and -not $ours) { ' — своя, её не меняю' })."
  $keys = @('usb', 'aspm', 'disk') + @(if ($wifi) { 'wifi' }) + @('sleep', 'video'); $cur = @{}
  foreach ($k in $keys) { $c = PctEnGet $act $k; if (-not $c) { continue }; $cur[$k] = $c
    Write-Host "  $($KN[$k]): $(if ($D.Laptop) { "от сети — $(Vt $k $c.AC), от батареи — $(Vt $k $c.DC)" } else { Vt $k $c.AC })" -ForegroundColor DarkGray }
  if ($vend) { Write-Host "Нашёл фирменные программы: $($vend -join ', '). Они сами меняют режим питания поверх Windows. Если после настройки снова тормозит — проверь режим в этой программе." -ForegroundColor Yellow }
  Jr "тип: $dev, MS=$($D.MS), от сети=$($D.AC), схема $act ($actN), фирменные: $($vend -join ', ')"
  $t = "$dev$(if ($D.MS) { ' · Modern Standby' })"; if ($vend) { Step -Warn "$t · есть $($vend -join ', ')" } else { Step -Done $t }
  # Уже менял — сначала предложить вернуть
  if ($bk) { Step 'Спрашиваю, вернуть ли как было' -Hint 'Ответь на вопрос ниже'
    if (Ask2 "Помощник уже менял энергосбережение ($(([datetime]$bk.created).ToString('d MMMM, HH:mm', $ru)))" 'могу вернуть всё как было.' 'Если нет — продолжу, а «Вернуть как было» потом всё равно вернёт к самому началу.' 'Вернуть всё как было?') { Step -Done 'вернуть'; DoUndo; return }
    Step -Done 'продолжаю настройку' }
  # ---------- Замер до ----------
  Step 'Замеряю задержки до' -Hint 'Не трогай мышь 5 секунд'
  Write-Host 'Замеряю, сколько времени процессор тратит на срочные задачи устройств: от них зависят рывки мыши и треск звука. Задержку USB после простоя без сторонних программ точно не измерить.' -ForegroundColor DarkGray
  $l0 = Lat; Step -Done $(if ($l0) { "срочные задачи устройств — $(P2 $l0.M) %" } else { 'замер не получился' })
  # ---------- Спрашиваю: заголовок и суть — одна строка, совет — вторая (окно показывает две последние) ----------
  Step 'Спрашиваю, что поменять' -Hint 'Ответь на вопросы ниже'
  $max = $false
  if ($D.Laptop) { $max = Ask2 'От батареи' 'всё ниже меняю только от сети. С максимумом и от батареи ноутбук быстрее, но заряд уходит быстрее и корпус теплее.' "$(if ($D.MS) { 'С современным ждущим режимом он ещё и хуже засыпает. ' })Не нужно: рекомендую «Обычно»." 'Включить максимум и от батареи?' }
  $srcs = @('AC') + @(if ($max) { 'DC' }); $sw = $(if ($max) { 'от сети и от батареи' } else { 'от сети' })
  # Схема или режим питания. Основа копии — «Высокая производительность», нет — «Сбалансированная»; нет и её — копии не будет (проверяю до вопросов)
  $hp = $false; $ov = $false; $base = ''
  if (-not $D.Laptop -and -not $D.MS) {
    if ($ours) { Write-Host "`nСхема «Помощник: быстрее» уже включена." -ForegroundColor DarkGray }
    else { $base = "$(@(@($HpG, $BalG) | Where-Object { PctEnHas $_ })[0])"; Jr "основа копии: $(if ($base) { $base } else { 'нет ни «Высокой производительности», ни «Сбалансированной»' })"
      if ($base -eq $HpG) { $hp = Ask2 'Схема «Помощник: быстрее»' 'включу копию «Высокой производительности»: ядра процессора не будут «засыпать». Минимум процессора — 5 %, как в «Сбалансированной», без лишнего нагрева.' "$(if (-not $bi) { "Твоя схема «$actN» останется. " })Рекомендую." 'Включить схему «Помощник: быстрее»?' }
      elseif ($base -and -not $bi) { $hp = Ask2 'Схема «Помощник: быстрее»' 'в этой Windows нет «Высокой производительности». Сделаю копию «Сбалансированной» и запишу в неё настройки ниже.' "Твоя схема «$actN» останется. Рекомендую." 'Включить схему «Помощник: быстрее»?' } } }
  elseif ($act -eq $BalG) { $o = PctEnOverlay
    if ($o -eq $BestG) { Write-Host "`nРежим питания уже «Лучшая производительность»." -ForegroundColor DarkGray }
    elseif (-not $D.AC) { Write-Host "`nРежим питания «Лучшая производительность» поставлю, когда ноутбук будет от сети: подключи зарядку и запусти ещё раз." -ForegroundColor Yellow }
    else { $ov = Ask2 'Режим питания «Лучшая производительность»' "сейчас «$(Ovn $o)». От сети $dev перестанет сбавлять скорость ради экономии." 'Рекомендую.' 'Поставить «Лучшая производительность» от сети?' } }
  else { Write-Host "`nРежим питания «Лучшая производительность» работает только со сбалансированной схемой. У тебя «$actN» — режим не трогаю." -ForegroundColor DarkGray }
  # Куда писать настройки: копия «Высокой производительности», схема Windows или своя копия Помощника. Чужую схему не меняю
  $canT = $hp -or $bi -or $ours
  if (-not $canT) { $pc = -not $D.Laptop -and -not $D.MS; $why = $(if ($pc -and -not $base) { ' Копию сделать нельзя: в этой Windows нет ни «Высокой производительности», ни «Сбалансированной».' } elseif ($pc) { ' Чтобы их поменять, включи схему «Помощник: быстрее».' })
    Write-Host "`nСхема «$actN» — твоя, её не меняю. Приостановку USB, PCI Express, диск, Wi-Fi и сон не спрашиваю.$why" -ForegroundColor Yellow; Jr "настройки схемы не спрашиваю: схема своя.$why" }
  $Q = [ordered]@{
    usb = @('Выборочная приостановка USB', 'Windows усыпляет USB-порты, и мышь, клавиатура или звук иногда отвечают с задержкой.', 'Выключить приостановку USB?')
    aspm = @('Экономия PCI Express', 'видеокарта, сеть и быстрый диск засыпают между запросами, выход из сна — задержка.', 'Выключить экономию PCI Express?')
    disk = @('Отключение диска', 'после простоя жёсткий диск останавливается и потом несколько секунд раскручивается.', 'Не отключать диск?')
    wifi = @('Экономия Wi-Fi', 'Wi-Fi засыпает между передачами, и пинг в играх и звонках скачет.', 'Выключить экономию Wi-Fi?') }
  $pick = @{}
  foreach ($k in @($Q.Keys)) { $c = $cur[$k]; if (-not $canT -or -not $c) { continue }
    if (-not $hp -and -not @($srcs | Where-Object { $c.$_ -ne 0 }).Count) { Write-Host "`n$($Q[$k][0]) — уже $(Vt $k 0) $sw. Не меняю." -ForegroundColor DarkGray; continue }
    if (Ask2 $Q[$k][0] "$($Q[$k][1]) Сейчас от сети: $(Vt $k $c.AC)$(if ($D.Laptop) { ", от батареи: $(Vt $k $c.DC)" })." "Рекомендую$(if ($k -eq 'disk') { ' «никогда»' } else { ' выключить' })$(if ($D.Laptop) { " $sw" })." $Q[$k][2]) { $pick[$k] = $true } }
  # Устройства: галочка «Разрешить отключение этого устройства для экономии энергии»
  $devs = @(PctEnDevices | Where-Object { $_.On }); $pdev = $false
  if ($devs) { $cn = { param($x) @($devs | Where-Object { $_.K -eq $x }).Count }
    $dr = $(if ($D.MS) { 'По ситуации: от батареи и во сне заряд уйдёт быстрее.' } elseif ($D.Laptop) { 'По ситуации: действует и от батареи.' } else { 'Рекомендую запретить.' })
    $pdev = Ask2 'Отключение устройств для экономии' 'после него мышь или сеть иногда не просыпаются, пока их не переподключишь.' "Разрешено у: USB-концентраторов — $(& $cn 'hub'), мыши и клавиатуры — $(& $cn 'input'), сетевых карт — $(& $cn 'net'). $dr" 'Запретить Windows отключать эти устройства?' }
  # Энергосбережение проводной сетевой карты
  $nics = @(PctEnNics | Where-Object { $_.V -ne '0' }); $pnic = $false
  if ($nics) { Jr "сетевая карта: $(@($nics | ForEach-Object { "$($_.A) $($_.N)=$($_.V)" }) -join ', ')"; $nr = $(if ($D.Laptop) { 'По ситуации: действует и от батареи.' } else { 'Рекомендую выключить.' })
    $pnic = Ask2 'Энергосбережение сетевой карты' 'в паузах карта сбавляет питание, из-за этого бывают обрывы и задержки.' "Интернет пропадёт на несколько секунд. $nr" 'Выключить энергосбережение сетевой карты?' }
  # Сон и экран: не скорость — совет «оставить»
  $psl = $false; $s = $cur['sleep']; $v = $cur['video']
  if ($canT -and $s -and $v -and ($hp -or $s.AC -or $v.AC)) { $psl = Ask2 'Сон и отключение экрана' "сейчас от сети: сон — $(Vt 'sleep' $s.AC), экран — $(Vt 'video' $v.AC). Быстрее $dev от этого не станет, а без сна тратит электричество и изнашивается." 'Не нужно: рекомендую оставить.' 'Выключить сон и отключение экрана от сети?' }
  Write-Host "`nМинимум процессора 100 % и схему «Максимальная производительность» не включаю: процессор всё время на полной частоте — греется и шумит, а в обычной работе быстрее не станет. Windows и так поднимает частоту за доли секунды." -ForegroundColor DarkGray
  $nCh = [int]$hp + [int]$ov + $pick.Count + [int]$pdev + [int]$pnic + [int]$psl
  if (-not $nCh) { Step -Done 'ничего не меняю'; Write-Host "`nНичего не поменял." -ForegroundColor Green; return }
  Step -Done "поменять: $nCh"
  # ---------- Сохраняю и меняю: бэкап, схема, устройства, сеть ----------
  if ($pnic -and -not (NetWait)) { return }
  Step 'Сохраняю, как было, и меняю' -Hint $(if ($pnic) { 'Интернет пропадёт на несколько секунд' } else { 'Пара секунд' })
  $b = PctEnBackupStart $act $actN; Jr "бэкап: $(PctEnBackupPath), схема в файле: $($b.export)"
  if ($b.export) { Write-Host "Схема до изменений: $($b.export)" -ForegroundColor DarkGray } else { Write-Host 'Файл схемы не записался — старые значения всё равно сохранены.' -ForegroundColor Yellow }
  Step -Unsafe
  $ch = New-Object Collections.ArrayList; $bad = New-Object Collections.ArrayList
  $T = $(if ($bi -or $ours) { $act } else { '' })
  if ($hp) { $g = $(if ($b.copy -and ($sch.G -contains $b.copy)) { $b.copy } else { PctEnCopy $base 'Помощник: быстрее' })
    if ($g) { $b.copy = $g; PctEnBackupSave $b; Jr "копия схемы: $g из $base"; $T = $g
      # Копия = основа + минимум процессора 5 % + наши настройки как в прежней схеме; выбранное ниже перепишет Put
      foreach ($k in $keys) { $c = $cur[$k]; if ($c) { [void](PctEnSet $g $k 'AC' $c.AC); [void](PctEnSet $g $k 'DC' $c.DC) } }
      foreach ($sr in 'AC', 'DC') { if (-not (PctEnSet $g 'cpumin' $sr 5) -or (PctEnGet $g 'cpumin').$sr -ne 5) { [void]$bad.Add('минимум процессора в копии') } } }
    else { [void]$bad.Add('копия схемы не создалась'); Jr "копия схемы из $base не создалась" } }
  # Новое значение в схему $T и перечитать; в схему Windows — со старым значением в бэкапе
  function Put($k, [long]$nv, $ss) { foreach ($sr in $ss) { $old = $cur[$k].$sr; if ($old -eq $nv) { continue }
      if ($T -ne $b.copy) { PctEnRemember $b 'values' ([pscustomobject]@{ scheme = $T; key = $k; src = $sr; old = $old }) @('scheme', 'key', 'src') }
      if ((PctEnSet $T $k $sr $nv) -and (PctEnGet $T $k).$sr -eq $nv) { [void]$ch.Add("$($KN[$k])$(if ($D.Laptop) { $(if ($sr -eq 'AC') { ' от сети' } else { ' от батареи' }) }): $(Vt $k $old) → $(Vt $k $nv)") } else { [void]$bad.Add($KN[$k]); Jr "не записалось: $k $sr = $nv в $T" } } }
  if ($T) { foreach ($k in @($pick.Keys)) { Put $k 0 $srcs }; if ($psl) { Put 'sleep' 0 @('AC'); Put 'video' 0 @('AC') }
    if ($T -eq $b.copy -and $T -ne $act) { if ((PctEnSetActive $T) -and (PctEnActive) -eq $T) { [void]$ch.Insert(0, "Схема: «$actN» → «Помощник: быстрее» (копия «$(if ($base -eq $BalG) { 'Сбалансированной' } else { 'Высокой производительности' })», минимум процессора 5 %)") } else { [void]$bad.Add('копия схемы не включилась') } }
    elseif ($ch.Count) { [void](PctEnSetActive $T) } }
  elseif ($pick.Count -or $psl) { [void]$bad.Add('настройки схемы: схема не моя') }
  if ($ov) { if (-not $b.overlay) { $b.overlay = PctEnOverlay; PctEnBackupSave $b }; $o0 = PctEnOverlay
    if (PctEnOverlaySet $BestG) { [void]$ch.Add("Режим питания от сети: $(Ovn $o0) → лучшая производительность") } else { [void]$bad.Add('режим питания') } }
  if ($pdev) { $okd = @(); foreach ($dv in $devs) { PctEnRemember $b 'devices' ([pscustomobject]@{ id = $dv.Id; name = $dv.N; old = $true }) @('id')
      if (PctEnDeviceSet $dv.Id $false) { $okd += $dv.Id; Jr "устройство: запретил отключение — $($dv.N)" } else { [void]$bad.Add("устройство $($dv.N)") } }
    # Перечитываю: Windows может вернуть разрешение. В итоге — что стало на самом деле
    $rd = @(PctEnDevices); $on = @($rd | Where-Object { $_.On } | ForEach-Object { $_.Id }); $off = @($rd | Where-Object { -not $_.On } | ForEach-Object { $_.Id })
    $st = @($devs | Where-Object { $okd -contains $_.Id -and $on -contains $_.Id }); $nd = @($devs | Where-Object { $off -contains $_.Id }).Count
    foreach ($dv in $st) { Jr "устройство: Windows вернула разрешение отключать — $($dv.N)" }
    foreach ($dv in @($devs | Where-Object { $okd -contains $_.Id -and $on -notcontains $_.Id -and $off -notcontains $_.Id })) { [void]$bad.Add("устройство $($dv.N): не перечитал"); Jr "устройство: не перечитал — $($dv.N)" }
    if ($nd) { [void]$ch.Add("Отключение для экономии: разрешено у $($devs.Count) → запрещено у $nd") }
    if ($st.Count) { $c = $st.Count; [void]$bad.Add("отключение для экономии: Windows вернула для $c $(if ($c % 10 -eq 1 -and $c % 100 -ne 11) { 'устройства' } else { 'устройств' })") } }
  if ($pnic) { $okn = @(); foreach ($n in $nics) { PctEnRemember $b 'nics' ([pscustomobject]@{ adapter = $n.A; kw = $n.Kw; name = $n.N; old = $n.V }) @('adapter', 'kw')
      if (PctEnNicSet $n.A $n.Kw '0') { $okn += $n; Jr "сеть: $($n.A) $($n.Kw) $($n.V) → 0" } else { [void]$bad.Add("сетевая карта: $($n.N)") } }
    # Карта перезапускается — жду, пока сеть вернётся (до 20 с)
    if (-not $Fake) { $w = [Diagnostics.Stopwatch]::StartNew(); while ($w.Elapsed.TotalSeconds -lt 20 -and @(Get-NetAdapter -Physical | Where-Object { $_.NdisPhysicalMedium -eq 14 -and $_.Status -ne 'Up' -and $_.MediaConnectionState -ne 'Disconnected' }).Count) { Start-Sleep -Milliseconds 500 } }
    # Перечитываю карту: в итоге — что стало на самом деле
    $now = @(PctEnNics); foreach ($n in $okn) { $x = @($now | Where-Object { $_.A -eq $n.A -and $_.Kw -eq $n.Kw })
      if ($x.Count -and $x[0].V -eq '0') { [void]$ch.Add("$($n.N): вкл → выкл") } elseif ($x.Count) { [void]$bad.Add("сетевая карта: $($n.N) — Windows вернула"); Jr "сеть: Windows вернула $($n.A) $($n.Kw) = $($x[0].V)" }
      else { [void]$bad.Add("сетевая карта: $($n.N) — не перечитал"); Jr "сеть: не перечитал $($n.A) $($n.Kw)" } } }
  foreach ($x in $ch) { Jr "изменил: $x" }
  if ($bad.Count) { Step -Warn "поменял: $($ch.Count), не вышло: $($bad.Count)" } else { Step -Done "поменял: $($ch.Count)" }
  # ---------- Замер после, было → стало ----------
  Step 'Замеряю задержки после' -Hint 'Не трогай мышь 5 секунд'; $l1 = Lat
  Write-Host "`nБЫЛО → СТАЛО" -ForegroundColor Cyan; foreach ($x in $ch) { Write-Host "  $x" -ForegroundColor White }
  if ($bad.Count) { Write-Host "Не вышло: $($bad -join ', ')." -ForegroundColor Yellow }
  $lt = 'замер не получился'
  if ($l0 -and $l1) { $df = $l1.M - $l0.M; $sp = [math]::Max($l0.Sp, $l1.Sp); $lt = "срочные задачи устройств: $(P2 $l0.M) → $(P2 $l1.M) %"
    Write-Host "Срочные задачи устройств: было $(P2 $l0.M) % времени процессора → стало $(P2 $l1.M) %." -ForegroundColor White
    if ([math]::Abs($df) -le $sp) { Write-Host "Разница меньше, чем разброс между отдельными замерами ($(P2 $sp) %), — по этому замеру ускорения не видно. Главное другое: мышь, звук и сеть больше не будут «засыпать» и просыпаться с задержкой." }
    elseif ($df -lt 0) { Write-Host 'Стало меньше — устройства реже отвлекают процессор.' -ForegroundColor Green } else { Write-Host 'Стало чуть больше: устройства не засыпают и работают постоянно. Это нормально.' } }
  if ($max -and $ov) { Write-Host 'Режим «Лучшая производительность» для батареи поставь сам: Параметры → Система → Питание → Режим питания → От батареи.' -ForegroundColor DarkGray }
  Write-Host "`nВернуть как было: нажми «Энергосбережение» ещё раз и ответь «да» на первый вопрос." -ForegroundColor DarkGray
  Jr "готово: изменений $($ch.Count), не вышло: $($bad -join ', '); $lt"
  $sum = "поменял: $($ch.Count) · срочные задачи устройств: $(if ($l0 -and $l1) { "$(P2 $l0.M) → $(P2 $l1.M) %" } else { "замер не получился" })"
  if ($bad.Count) { Step -Warn "$sum · не вышло: $($bad.Count)" } else { Step -Done $sum }
} finally { PctUnlock $script:nk; PctUnlock $lk; Enter }
