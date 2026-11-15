# «Что отправляет Windows» (PRIV-2): строки с правами — отчёты о сбоях, сбор данных о работе Windows, проверка совместимости, определение места, датчики. -Arg <строка>.off | <строка>.on | undo
# До изменения — журнал (pct-core.ps1, с правами, запечатан): реестр — старое значение или «значения не было», служба — тип запуска, задача — включена ли. Итог — по чтению обратно; чек.
# <строка>.on, а эту строку выключил Помощник (пункты в открытом журнале) — точный возврат. undo — вернуть всё из открытых журналов с правами (журналы без прав возвращает окно, Send.cs).
# Источники ключей — Microsoft Learn (progress\PRIV-2-REPORT). Стенд: PCT_PRIV_ROOT=Software\PomoshnikTest\<стенд> (реестр — HKCU\<стенд>\HKLM\…) и PCT_UNDO_FAKE (службы и задачи) — только вместе; PCT_PRIV_SPOIL=3 — сбой после первого изменения
param([string]$Arg)
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
$Host.UI.RawUI.WindowTitle = 'Что отправляет Windows'
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
function Enter { Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null }
$Tool = 'privsend'; $Title = 'Что отправляет Windows'
# Стенд: оба значения или ни одного. Иначе не трогаю ничего — ни стенд, ни настоящую систему
$St = "$env:PCT_PRIV_ROOT".Trim().TrimEnd('\'); $Fk = "$env:PCT_UNDO_FAKE"; $Stand = [bool]($St -or $Fk)
$StandOk = $St -match '^Software\\PomoshnikTest\\[A-Za-z0-9_-]+$' -and $Fk -and [IO.File]::Exists($Fk)
$Spoil = $(if ($Stand) { "$env:PCT_PRIV_SPOIL" } else { '' })
$Svcs = 'SYSTEM\CurrentControlSet\Services'
$Rows = [ordered]@{
  wer = @{ N = 'Отчёты о сбоях'; Acc = 'отчёты о сбоях'; Kind = 'reg'; Key = 'SOFTWARE\Microsoft\Windows\Windows Error Reporting'; Pol = 'SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting|Disabled'; Boot = $false }
  diag = @{ N = 'Сбор данных о работе Windows'; Acc = 'сбор данных о работе Windows'; Kind = 'service'; Svc = 'DiagTrack'; Def = 2; Boot = $true }
  compat = @{ N = 'Проверка совместимости программ'; Acc = 'проверку совместимости программ'; Kind = 'task'; Boot = $false
    Tasks = @('\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser', '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp', '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator') }
  location = @{ N = 'Определение места'; Acc = 'определение места'; Kind = 'service'; Svc = 'lfsvc'; Def = 3; Pol = 'SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors|DisableLocation'; Boot = $true }
  sensors = @{ N = 'Датчики'; Acc = 'датчики'; Kind = 'service'; Svc = 'SensorService'; Def = 3; Pol = 'SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors|DisableSensors'; Boot = $true } }

# Путь реестра для pct-core (PctRegKey): настоящий HKLM или ключ стенда в HKCU
function Rk([string]$Path, [switch]$User) { if ($Stand) { "HKCU\$St\$(if ($User) { 'HKCU' } else { 'HKLM' })\$Path" } elseif ($User) { "HKCU\$Path" } else { "HKLM\$Path" } }
function Dw([string]$Key, [string]$Name) { $k = PctRegKey $Key; if (-not $k) { return $null }; $v = $k.GetValue($Name); $k.Close(); if ($v -is [int]) { $v } else { $null } }
# Правило: 1 — выключено правилом; у отчётов о сбоях 0 — включено правилом. HKLM и HKCU (у места и датчиков есть правило пользователя)
function PolOf($R) { if (-not $R.Pol) { return $null }; $p, $n = $R.Pol -split '\|'
  foreach ($k in @((Rk $p), (Rk $p -User))) { $v = Dw $k $n; if ($v -eq 1) { return 'pol-off' }; if ($v -eq 0 -and $R.Kind -eq 'reg') { return 'pol-on' } }; $null }
function SvcStart([string]$Name) { if ($Stand) { $s = (PctUndoFake).services.$Name; if ($null -eq $s) { return $null }; return [int]$s.start }
  $k = PctRegKey "HKLM\$Svcs\$Name"; if (-not $k) { return $null }; $v = $k.GetValue('Start'); $k.Close(); $v }
# Задачи этой строки, которые есть: путь → включена
function TaskMap($R) { $m = [ordered]@{}; $f = $(if ($Stand) { PctUndoFake }); $s = $null; if (-not $Stand) { try { $s = New-Object -ComObject Schedule.Service; $s.Connect() } catch { return $m } }
  foreach ($p in $R.Tasks) { if ($Stand) { $t = $f.tasks.$p; if ($null -ne $t) { $m[$p] = [bool]$t.enabled } } else { $i = $p.LastIndexOf('\'); try { foreach ($t in @($s.GetFolder($p.Substring(0, $i)).GetTasks(1))) { if ($t.Path -eq $p) { $m[$p] = [bool]$t.Enabled } } } catch { PctUndoLog "privsend: папка задач не читается — $p" } } }; $m }
# Состояние: on · off · none (нет в Windows) · pol-on / pol-off
function State($R) { $pol = PolOf $R
  switch ($R.Kind) {
    'reg' { if ($pol) { return $pol }; if ((Dw (Rk $R.Key) 'Disabled') -eq 1) { 'off' } else { 'on' } }
    'service' { $s = SvcStart $R.Svc; if ($null -eq $s) { return 'none' }; if ($pol) { return $pol }; if ([int]$s -eq 4) { 'off' } else { 'on' } }
    'task' { $m = TaskMap $R; if (-not $m.Count) { return 'none' }; if (@($m.Values | Where-Object { $_ }).Count) { 'on' } else { 'off' } } } }

# Одно изменение: пункт в журнал (старое значение) → запись. $true — записал. Не записал — пункт закрыт: возвращать нечего
function Apply($J, $R, [bool]$On) { $items = @()
  switch ($R.Kind) {
    'reg' { $items += , @(@{ kind = 'reg'; key = (Rk $R.Key); name = 'Disabled' }, $(if ($On) { 0 } else { 1 })) }
    'service' { $items += , @(@{ kind = 'service'; name = $R.Svc }, $(if ($On) { $R.Def } else { 4 })) }
    'task' { foreach ($p in @((TaskMap $R).Keys)) { $items += , @(@{ kind = 'task'; path = $p }, $On) } } }
  $done = 0
  foreach ($x in $items) { $it = PctUndoAdd $J $x[0] $R.N; $ok = $false
    try { $ok = SetOne $x[0] $x[1] } catch { PctUndoLog "privsend: $($R.N) — $($_.Exception.Message)" }
    if (-not $ok) { $it.state = 'undone'; if (-not @($J.items | Where-Object { $_.state -ne 'undone' }).Count) { $J.closed = (Get-Date).ToString('s') }; PctUndoSave $J; return $done }
    $done++; if ($Spoil -eq '3' -and $done -lt $items.Count) { PctUndoLog 'privsend: стенд, сбой после первого изменения'; return $done } }
  $done }
function SetOne($X, $V) { $f = PctUndoFake
  switch ($X.kind) {
    'reg' { $k = PctRegKey $X.key -Create; if (-not $k) { return $false }; $k.SetValue($X.name, [int]$V, [Microsoft.Win32.RegistryValueKind]::DWord); $k.Close(); return (Dw $X.key $X.name) -eq [int]$V }
    'service' { if ($Stand) { $s = $f.services.($X.name); if (-not $s -or $s.stuck) { return $false }; $s.start = [int]$V; $s.delayed = $false; PctUndoFakeSave $f; return $true }
      $m = @{ 2 = 'auto'; 3 = 'demand'; 4 = 'disabled' }[[int]$V]; $null = sc.exe config $X.name start= $m 2>&1; return -not $LASTEXITCODE -and (SvcStart $X.name) -eq [int]$V }
    'task' { if ($Stand) { $t = $f.tasks.($X.path); if (-not $t -or $t.stuck) { return $false }; $t.enabled = [bool]$V; PctUndoFakeSave $f; return $true }
      $s = New-Object -ComObject Schedule.Service; $s.Connect(); $i = $X.path.LastIndexOf('\'); $t = $s.GetFolder($X.path.Substring(0, $i)).GetTask($X.path.Substring($i + 1)); $t.Enabled = [bool]$V; return [bool]$t.Enabled -eq [bool]$V } } }
# Открытые журналы с правами этого инструмента — от нового к старому (пункты в каждом PctUndoPending даёт с последнего): возврат идёт строго назад
function Opened { $r = @(); $fs = @(); try { $fs = @([IO.Directory]::GetFiles((PctDir 'reports'), "undo-$Tool-*.json") | Sort-Object -Descending) } catch { PctUndoLog "privsend: журналы не прочитал: $($_.Exception.Message)" }
  foreach ($f in $fs) { $j = PctUndoLoad ([IO.Path]::GetFileName($f)); if ($j -is [string] -or $j.closed -or -not $j.admin) { continue }; $r += $j }; $r }
function Low($s) { if ($s) { $s.Substring(0, 1).ToLower() + $s.Substring(1) } }

Write-Host "`nЧТО ОТПРАВЛЯЕТ WINDOWS`n" -ForegroundColor Cyan
Step -Safe
if ($Stand -and -not $StandOk) { Step 'Проверяю стенд'; Step -Fail 'стенд задан не полностью' -Do 'Нужны оба: PCT_PRIV_ROOT и PCT_UNDO_FAKE.'; PctUndoLog "privsend: отказ, стенд не полный ($St)"; Write-Host 'Стенд задан не полностью — ничего не трогаю.' -ForegroundColor Yellow; Enter; return }
$what, $dir = "$Arg" -split '\.', 2; $undo = $Arg -eq 'undo'; $R = $Rows[$what]
if (-not $undo -and (-not $R -or $dir -notin 'on', 'off')) { Step 'Читаю задание'; Step -Fail 'не знаю, что менять' -Do 'Нажми выключатель на вкладке «Что отправляет Windows».'; Write-Host 'Не знаю, что менять.' -ForegroundColor Yellow; Enter; return }
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $Stand -and -not $admin) { Step 'Проверяю права'; Step -Fail 'нет разрешения Windows' -Do 'Нажми выключатель ещё раз и выбери «Да» в окне Windows.'; Write-Host 'Нужно разрешение Windows.' -ForegroundColor Yellow; Enter; return }
$lk = PctLock $Tool 10; if (-not $lk) { Step 'Проверяю, не идёт ли другое изменение'; Step -Fail 'идёт другое изменение' -Do 'Дождись, пока оно закончится, и нажми ещё раз.'; Write-Host 'Сейчас идёт другое изменение. Дождись его конца.' -ForegroundColor Yellow; Enter; return }
try {
  PctUndoLog "privsend: начал $Arg$(if ($Stand) { ' (стенд)' })"
  # ---------- Вернуть как было: все открытые журналы с правами ----------
  if ($undo) {
    $js = @(Opened); $p = @(foreach ($j in $js) { PctUndoPending $j }); Step -Plan (@('Читаю, что было') + @($(if ($p.Count) { 'Возвращаю как было' })))
    Step 'Читаю, что было'; if (-not $p.Count) { Step -Done 'уже возвращено'; Write-Host 'Возвращать нечего.' -ForegroundColor Green; return }
    Step -Done "изменений: $($p.Count)"; Step -Unsafe; Step 'Возвращаю как было' -Hint 'Ничего не трогай'
    $of = ''; try { foreach ($f in [IO.Directory]::GetFiles("$(PctDir 'reports')\receipts", "*-$Tool*.json")) { $x = [IO.File]::ReadAllText($f) | ConvertFrom-Json; if ("$($x.undo.journal)" -eq $js[0].file) { $of = [IO.Path]::GetFileName($f) } } } catch { PctUndoLog "privsend: чеки не прочитал: $($_.Exception.Message)" }
    $rc = PctReceipt $Tool $Title @() 'undo' $of; $bad = New-Object Collections.ArrayList; $seen = @{}; $okN = 0
    foreach ($j in $js) { foreach ($x in @(PctUndoPending $j)) { if (PctUndoOne $j $x) { $okN++; if (-not $seen[$x.text]) { $seen[$x.text] = 1; PctRcDo $rc $x.text 'как было' } } elseif ($bad -notcontains $x.text) { [void]$bad.Add($x.text) } } }
    if ($bad.Count) { Step -Warn "вернул $okN из $($p.Count)" } else { Step -Done 'как было' }
    $note = $(if ($bad.Count) { "Не вернул: $(@($bad | ForEach-Object { Low $_ }) -join ', '). Нажми «Вернуть как было» ещё раз." } else { '' })
    [void](PctReceiptEnd $rc $(if ($bad.Count) { "Вернул не всё: $okN из $($p.Count)" } else { 'Вернул как было' }) $null 'Это возврат. Чтобы поменять снова, нажми выключатель на вкладке «Что отправляет Windows».' $note)
    PctUndoLog "privsend: вернул $okN из $($p.Count)$(if ($bad.Count) { ", не вышло: $($bad -join ', ')" })"
    if ($bad.Count) { Write-Host "`n$note" -ForegroundColor Yellow } else { Write-Host "`nВернул всё как было." -ForegroundColor Green }; return }
  # ---------- Одна строка ----------
  $on = $dir -eq 'on'; $verb = $(if ($on) { 'Включаю' } else { 'Выключаю' })
  Step -Plan 'Смотрю, как сейчас', "$verb $($R.Acc)", 'Проверяю'
  Step 'Смотрю, как сейчас' -Hint 'Ничего не меняю'; $s0 = State $R
  if ($s0 -eq 'none') { Step -Done 'этого нет в Windows'; Write-Host 'Этого нет в твоей Windows — менять нечего.' -ForegroundColor Green; return }
  if ($s0 -like 'pol-*') { Step -Warn 'задано правилом'; Write-Host 'Так задано правилом на всём компьютере: отсюда не поменять.' -ForegroundColor Yellow; return }
  if (($s0 -eq 'on') -eq $on) { Step -Done "уже $(if ($on) { 'включено' } else { 'выключено' })"; Write-Host "Уже $(if ($on) { 'включено' } else { 'выключено' }): $($R.Acc)." -ForegroundColor Green; return }
  Step -Done $(if ($on) { 'выключено' } else { 'включено' }); Step -Unsafe
  # Включить то, что выключил Помощник, — точный возврат из журнала: старое значение, а не «как обычно»
  $back = @(); if ($on) { foreach ($j in @(Opened)) { foreach ($x in @(PctUndoPending $j)) { if ($x.text -eq $R.N) { $back += , @($j, $x) } } } }
  Step "$verb $($R.Acc)" -Hint $(if ($back.Count) { 'Возвращаю, как было до Помощника' } else { 'Сначала запоминаю, как было' })
  if ($back.Count) { $rc = PctReceipt $Tool $Title @() 'undo'; $okN = 0; foreach ($b in $back) { if (PctUndoOne $b[0] $b[1]) { $okN++ } }
    $s1 = State $R; $good = $s1 -eq 'on' -and $okN -eq $back.Count
    if ($good) { Step -Done 'как было' } else { Step -Fail "вернул $okN из $($back.Count)" -Do 'Нажми «Вернуть как было» ещё раз или позови помощь.' }
    PctRcDo $rc $R.N $(if ($good) { 'как было' } else { "вернул $okN из $($back.Count)" })
    [void](PctReceiptEnd $rc $(if ($good) { 'Вернул как было' } else { 'Вернул не всё' }) $null 'Это возврат. Чтобы поменять снова, нажми тот же выключатель.' $(if ($R.Boot -and $okN) { 'Сработает после перезагрузки.' } else { '' }))
    PctUndoLog "privsend: $Arg — точный возврат $okN из $($back.Count)"; return }
  $j = PctUndoNew $Tool $Title -Admin; $done = Apply $j $R $on; $s1 = State $R; $want = $(if ($on) { 'on' } else { 'off' })
  Step 'Проверяю' -Hint 'Читаю обратно'
  $head = "$(if ($on) { 'Включил' } else { 'Выключил' }) $($R.Acc)"
  if ($s1 -eq $want) { Step -Done $(if ($R.Boot) { 'сработает после перезагрузки' } else { 'готово' }); $rc = PctReceipt $Tool $Title
    PctRcDo $rc $R.N "$(if ($on) { 'выключено → включено' } else { 'включено → выключено' })"
    [void](PctReceiptEnd $rc $head $j '' $(if ($R.Boot) { 'Сработает после перезагрузки.' } else { '' })); PctUndoLog "privsend: $Arg — готово"
    Write-Host "`n$head.$(if ($R.Boot) { ' Сработает после перезагрузки.' })" -ForegroundColor Green; return }
  PctUndoLog "privsend: $Arg — записал $done, прочитал обратно $s1"
  if (-not $done) { Step -Fail 'Windows не дала поменять' -Do 'Попробуй ещё раз или позови помощь.'; Write-Host 'Не получилось: Windows оставила как было.' -ForegroundColor Yellow; return }
  Step -Fail 'поменял не всё' -Do 'Нажми «Вернуть как было» — верну то, что успел поменять.'; $rc = PctReceipt $Tool $Title; PctRcDo $rc $R.N 'поменял не всё'
  [void](PctReceiptEnd $rc 'Не вышло: поменял не всё' $j '' 'Верни кнопкой ниже или позови помощь.'); Write-Host 'Поменял не всё. Нажми «Вернуть как было».' -ForegroundColor Yellow
} finally { PctUnlock $lk; Enter }
