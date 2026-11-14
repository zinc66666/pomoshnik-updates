# «Удобство и фон» (TWEAKS-SAFE-2): строки «Работает в фоне» с правами — раздача обновлений, Edge в фоне, обновление карт. -Arg <строки через ->.off | <строки>.on | undo
# Ключи — правила HKLM из Microsoft Learn (progress\TWEAKS-SAFE-2-REPORT): DODownloadMode=0 (только HTTP, без раздачи), BackgroundModeEnabled=0 и StartupBoostEnabled=0 (Edge), AutoDownloadAndUpdateMapData=0 (карты).
# .off: до изменения — журнал (pct-core.ps1, с правами, запечатан) по каждому значению, которое ещё не 0; уже 0 — не трогаю и в журнал не пишу. Итог — по чтению обратно; чек.
# .on: только точный возврат того, что записал Помощник (открытые журналы с правами); чужие правила не трогаю. undo — вернуть всё из открытых журналов с правами (журналы без прав возвращает окно, Tweaks.cs).
# .on и undo (TWEAKS-FIX): возвращаю пункт, только если сейчас стоит записанное Помощником (DWORD 0); человек поменял сам — не трогаю, пункт закрываю, пишу «ты уже поменял это сам».
# Стенд: PCT_PRIV_ROOT=Software\PomoshnikTest\<стенд> — реестр HKCU\<стенд>\HKLM\…; PCT_PRIV_SPOIL=1 — Windows вернула старое значение
param([string]$Arg)
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
$Host.UI.RawUI.WindowTitle = 'Удобство и фон'
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
function Enter { Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null }
$Tool = 'tweaks'; $Title = 'Удобство и фон'
# Стенд: только свой ключ в HKCU. Иначе не трогаю ничего — ни стенд, ни настоящую систему
$St = "$env:PCT_PRIV_ROOT".Trim().TrimEnd('\'); $Stand = [bool]$St; $StandOk = $St -match '^Software\\PomoshnikTest\\[A-Za-z0-9_-]+$'
$Spoil = $(if ($Stand) { "$env:PCT_PRIV_SPOIL" } else { '' })
$Rows = [ordered]@{
  do = @{ N = 'Раздача обновлений'; Acc = 'раздачу обновлений'; Key = 'SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'; Vals = @('DODownloadMode'); Soon = 'Сработает после перезагрузки.' }
  edge = @{ N = 'Edge в фоне'; Acc = 'Edge в фоне'; Key = 'SOFTWARE\Policies\Microsoft\Edge'; Vals = @('BackgroundModeEnabled', 'StartupBoostEnabled'); Soon = 'Сработает после перезапуска Edge.' }
  maps = @{ N = 'Обновление карт'; Acc = 'обновление карт'; Key = 'SOFTWARE\Policies\Microsoft\Windows\Maps'; Vals = @('AutoDownloadAndUpdateMapData'); Soon = '' } }

# Путь реестра для pct-core (PctRegKey): настоящий HKLM или ключ стенда в HKCU
function Rk([string]$Path) { if ($Stand) { "HKCU\$St\HKLM\$Path" } else { "HKLM\$Path" } }
# DWORD или $null (нет значения, другой тип)
function Dw([string]$Key, [string]$Name) { $k = PctRegKey $Key; if (-not $k) { return $null }
  try { if ($k.GetValueNames() -notcontains $Name -or "$($k.GetValueKind($Name))" -ne 'DWord') { return $null }; [int]$k.GetValue($Name) } finally { $k.Close() } }
# Выключено: все значения строки — DWORD 0
function IsOff($R) { foreach ($n in $R.Vals) { if ((Dw (Rk $R.Key) $n) -ne 0) { return $false } }; $true }
# Пункт вернулся: значения не было — его нет; было — ровно старое
function IsBack($X) { $k = PctRegKey $X.key; $has = $k -and $k.GetValueNames() -contains $X.name; $v = $(if ($has) { "$($k.GetValue($X.name, $null, 'DoNotExpandEnvironmentNames'))" }); if ($k) { $k.Close() }
  if (-not $X.existed) { return -not $has }; $has -and $v -eq "$($X.old)" }
# Выключить строку: пункт в журнал (старое значение) → DWORD 0 → чтение обратно. Не записалось — пункт закрыт: возвращать нечего. → сколько записал
function Off($J, $R) { $done = 0
  foreach ($n in $R.Vals) { $key = Rk $R.Key; if ((Dw $key $n) -eq 0) { continue }
    $it = PctUndoAdd $J @{ kind = 'reg'; key = $key; name = $n } $R.N; $ok = $false
    try { $k = PctRegKey $key -Create; if ($k) { $k.SetValue($n, 0, [Microsoft.Win32.RegistryValueKind]::DWord); $k.Close() }
      if ($Spoil -eq '1') { PctUndoLog 'tweaks-bg: стенд, Windows вернула старое'; [void](PctUndoItem $it) }
      $ok = (Dw $key $n) -eq 0 } catch { PctUndoLog "tweaks-bg: $($R.N) — $($_.Exception.Message)" }
    if ($ok) { $done++ } else { $it.state = 'undone'; if (-not @($J.items | Where-Object { $_.state -ne 'undone' }).Count) { $J.closed = (Get-Date).ToString('s') }; PctUndoSave $J } }
  $done }
# Открытые журналы с правами этого инструмента — от нового к старому (пункты в каждом PctUndoPending даёт с последнего): возврат идёт строго назад
function Opened { $r = @(); $fs = @(); try { $fs = @([IO.Directory]::GetFiles((PctDir 'reports'), "undo-$Tool-*.json") | Sort-Object -Descending) } catch { PctUndoLog "tweaks-bg: журналы не прочитал: $($_.Exception.Message)" }
  foreach ($f in $fs) { $j = PctUndoLoad ([IO.Path]::GetFileName($f)); if ($j -is [string] -or $j.closed -or -not $j.admin) { continue }; $r += $j }; $r }
# Чек, в котором этот журнал (для «of» у чека возврата)
function RcOf([string]$Journal) { try { foreach ($f in [IO.Directory]::GetFiles("$(PctDir 'reports')\receipts", "*-$Tool*.json")) { $x = [IO.File]::ReadAllText($f) | ConvertFrom-Json; if ("$($x.undo.journal)" -eq $Journal) { return [IO.Path]::GetFileName($f) } } } catch { PctUndoLog "tweaks-bg: чеки не прочитал: $($_.Exception.Message)" }; '' }
function Low($s) { if ($s) { $s.Substring(0, 1).ToLower() + $s.Substring(1) } }
# Вернуть пункты (журнал, пункт) и проверить чтением. → сколько вернул
function Back($Pairs) { $ok = 0; foreach ($b in $Pairs) { if ((PctUndoOne $b[0] $b[1]) -and (IsBack $b[1])) { $ok++ } }; $ok }
# Пункт ещё Помощника: стоит записанный им DWORD 0 (как проверяет окно, Tweaks.cs Self)
function Mine($X) { (Dw $X.key $X.name) -eq 0 }
# Человек поменял сам: не трогаю, пункт закрываю — возвращать нечего (как незаписанный в Off)
function Drop($J, $X) { $X.state = 'undone'; if (-not @($J.items | Where-Object { $_.state -ne 'undone' }).Count) { $J.closed = (Get-Date).ToString('s') }; PctUndoSave $J; PctUndoLog "tweaks-bg: $($X.text) ($($X.name)) — поменяли мимо Помощника, не трогаю" }
# Пары (журнал, пункт) делю: свои — вернуть; поменянные человеком — закрыть. → названия строк, которые не трогал
function Split2([ref]$Pairs) { $mine = @(); $self = @(); foreach ($b in $Pairs.Value) { if (Mine $b[1]) { $mine += , $b } else { Drop $b[0] $b[1]; if ($self -notcontains $b[1].text) { $self += $b[1].text } } }; $Pairs.Value = $mine; , $self }

Write-Host "`nУДОБСТВО И ФОН`n" -ForegroundColor Cyan
Step -Safe
if ($Stand -and -not $StandOk) { Step 'Проверяю стенд'; Step -Fail 'стенд задан неверно' -Do 'Нужен PCT_PRIV_ROOT=Software\PomoshnikTest\<имя>.'; PctUndoLog "tweaks-bg: отказ, стенд не подходит ($St)"; Write-Host 'Стенд задан неверно — ничего не трогаю.' -ForegroundColor Yellow; Enter; return }
$names, $dir = "$Arg" -split '\.', 2; $undo = $Arg -eq 'undo'; $ks = @("$names" -split '-' | Where-Object { $_ } | Select-Object -Unique); $Rs = @(foreach ($x in $ks) { $Rows[$x] })
if (-not $undo -and ($dir -notin 'on', 'off' -or -not $ks.Count -or @($Rs | Where-Object { $_ }).Count -ne $ks.Count)) { Step 'Читаю задание'; Step -Fail 'не знаю, что менять' -Do 'Нажми выключатель в «Удобстве и фоне».'; Write-Host 'Не знаю, что менять.' -ForegroundColor Yellow; Enter; return }
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $Stand -and -not $admin) { Step 'Проверяю права'; Step -Fail 'нет разрешения Windows' -Do 'Нажми ещё раз и выбери «Да» в окне Windows.'; Write-Host 'Нужно разрешение Windows.' -ForegroundColor Yellow; Enter; return }
$lk = PctLock $Tool 10; if (-not $lk) { Step 'Проверяю, не идёт ли другое изменение'; Step -Fail 'идёт другое изменение' -Do 'Дождись, пока оно закончится, и нажми ещё раз.'; Write-Host 'Сейчас идёт другое изменение. Дождись его конца.' -ForegroundColor Yellow; Enter; return }
try {
  PctUndoLog "tweaks-bg: начал $Arg$(if ($Stand) { ' (стенд)' })"
  # ---------- Вернуть всё: открытые журналы с правами ----------
  if ($undo) {
    $js = @(Opened); $p = @(foreach ($j in $js) { foreach ($x in @(PctUndoPending $j)) { , @($j, $x) } }); Step -Plan (@('Читаю, что было') + @($(if ($p.Count) { 'Возвращаю как было' })))
    Step 'Читаю, что было'; if (-not $p.Count) { Step -Done 'уже возвращено'; Write-Host 'Возвращать нечего.' -ForegroundColor Green; return }
    $self = Split2 ([ref]$p); $sn = $(if ($self.Count) { "Не трогал: $(@($self | ForEach-Object { Low $_ }) -join ', ') — ты уже поменял это сам." } else { '' })
    if (-not $p.Count) { Step -Done 'ты уже поменял это сам — не трогаю'; PctUndoLog "tweaks-bg: undo — всё поменяли мимо Помощника"; Write-Host "`n$sn" -ForegroundColor Green; return }
    Step -Done "изменений: $($p.Count)"; Step -Unsafe; Step 'Возвращаю как было' -Hint 'Ничего не трогай'
    $rc = PctReceipt $Tool $Title @() 'undo' (RcOf $js[0].file); $bad = New-Object Collections.ArrayList; $seen = @{}; $okN = 0
    foreach ($b in $p) { if ((PctUndoOne $b[0] $b[1]) -and (IsBack $b[1])) { $okN++; if (-not $seen[$b[1].text]) { $seen[$b[1].text] = 1; PctRcDo $rc $b[1].text 'как было' } } elseif ($bad -notcontains $b[1].text) { [void]$bad.Add($b[1].text) } }
    if ($bad.Count) { Step -Warn "вернул $okN из $($p.Count)" } elseif ($self.Count) { Step -Done 'как было, кроме того, что ты поменял это сам' } else { Step -Done 'как было' }
    $note = (@($(if ($bad.Count) { "Не вернул: $(@($bad | ForEach-Object { Low $_ }) -join ', '). Нажми «вернуть всё» ещё раз." }), $sn) | Where-Object { $_ }) -join ' '
    [void](PctReceiptEnd $rc $(if ($bad.Count) { "Вернул не всё: $okN из $($p.Count)" } else { 'Вернул как было' }) $null 'Это возврат. Чтобы поменять снова, нажми выключатель в «Удобстве и фоне».' $note)
    PctUndoLog "tweaks-bg: вернул $okN из $($p.Count)$(if ($bad.Count) { ", не вышло: $($bad -join ', ')" })"
    if ($bad.Count) { Write-Host "`n$note" -ForegroundColor Yellow } else { Write-Host "`nВернул всё как было.$(if ($sn) { " $sn" })" -ForegroundColor Green }; return }
  $acc = @($Rs | ForEach-Object { $_.Acc }) -join ', '
  # ---------- Включить: только точный возврат того, что выключил Помощник ----------
  if ($dir -eq 'on') {
    Step -Plan 'Смотрю, как сейчас', "Возвращаю: $acc", 'Проверяю'
    Step 'Смотрю, как сейчас' -Hint 'Ничего не меняю'; $back = @(foreach ($j in @(Opened)) { foreach ($x in @(PctUndoPending $j)) { if (@($Rs | ForEach-Object { $_.N }) -contains $x.text) { , @($j, $x) } } })
    if (-not $back.Count) { Step -Done 'не Помощник выключал — не трогаю'; Write-Host 'Это выключил не Помощник — не трогаю.' -ForegroundColor Green; return }
    $j0 = $back[0][0].file; $self = Split2 ([ref]$back); $sn = $(if ($self.Count) { "Не трогал: $(@($self | ForEach-Object { Low $_ }) -join ', ') — ты уже поменял это сам." } else { '' })
    if (-not $back.Count) { Step -Done 'ты уже поменял это сам — не трогаю'; PctUndoLog "tweaks-bg: $Arg — поменяли мимо Помощника, не трогаю"; Write-Host 'Ты уже поменял это сам — не трогаю.' -ForegroundColor Green; return }
    Step -Done "изменений: $($back.Count)"; Step -Unsafe; Step "Возвращаю: $acc" -Hint 'Возвращаю, как было до Помощника'
    $rc = PctReceipt $Tool $Title @() 'undo' (RcOf $j0); $okN = Back $back
    Step 'Проверяю' -Hint 'Читаю обратно'; $good = $okN -eq $back.Count
    if ($good) { Step -Done 'как было' } else { Step -Fail "вернул $okN из $($back.Count)" -Do 'Нажми «вернуть всё» или позови помощь.' }
    foreach ($R in $Rs) { if (@($back | Where-Object { $_[1].text -eq $R.N }).Count) { PctRcDo $rc $R.N $(if ($good) { 'как было' } else { "вернул $okN из $($back.Count)" }) } elseif ($self -contains $R.N) { PctRcDo $rc $R.N 'не трогал: ты уже поменял это сам' } }
    [void](PctReceiptEnd $rc $(if ($good) { 'Вернул как было' } else { 'Вернул не всё' }) $null 'Это возврат. Чтобы поменять снова, нажми тот же выключатель.' $sn)
    PctUndoLog "tweaks-bg: $Arg — точный возврат $okN из $($back.Count)"; return }
  # ---------- Выключить ----------
  Step -Plan 'Смотрю, как сейчас', "Выключаю: $acc", 'Проверяю'
  Step 'Смотрю, как сейчас' -Hint 'Ничего не меняю'; $todo = @($Rs | Where-Object { -not (IsOff $_) })
  if (-not $todo.Count) { Step -Done 'уже выключено'; Write-Host "Уже выключено: $acc." -ForegroundColor Green; return }
  Step -Done "включено: $(@($todo | ForEach-Object { $_.Acc }) -join ', ')"; Step -Unsafe
  Step "Выключаю: $acc" -Hint 'Сначала запоминаю, как было'
  $j = PctUndoNew $Tool $Title -Admin; $done = 0; foreach ($R in $todo) { $done += Off $j $R }
  Step 'Проверяю' -Hint 'Читаю обратно'; $left = @($todo | Where-Object { -not (IsOff $_) })
  $soon = @($todo | ForEach-Object { $_.Soon } | Where-Object { $_ } | Select-Object -Unique) -join ' '
  $head = $(if ($todo.Count -eq 1) { "Выключил $($todo[0].Acc)" } else { "Выключил: $(@($todo | ForEach-Object { $_.Acc }) -join ', ')" })
  if (-not $left.Count) { Step -Done $(if ($soon) { Low ($soon.TrimEnd('.')) } else { 'готово' }); $rc = PctReceipt $Tool $Title
    foreach ($R in $todo) { PctRcDo $rc $R.N 'включено → выключено' }
    [void](PctReceiptEnd $rc $head $j '' $soon); PctUndoLog "tweaks-bg: $Arg — готово"; Write-Host "`n$head.$(if ($soon) { " $soon" })" -ForegroundColor Green; return }
  PctUndoLog "tweaks-bg: $Arg — записал $done, не выключено: $(@($left | ForEach-Object { $_.N }) -join ', ')"
  if (-not $done) { Step -Fail 'Windows не дала поменять' -Do 'Попробуй ещё раз или позови помощь.'; Write-Host 'Не получилось: Windows оставила как было.' -ForegroundColor Yellow; return }
  Step -Fail 'поменял не всё' -Do 'Нажми «вернуть всё» — верну то, что успел поменять.'; $rc = PctReceipt $Tool $Title; foreach ($R in $todo) { PctRcDo $rc $R.N $(if ($left -contains $R) { 'не вышло' } else { 'включено → выключено' }) }
  [void](PctReceiptEnd $rc 'Не вышло: поменял не всё' $j '' 'Верни кнопкой ниже или позови помощь.'); Write-Host 'Поменял не всё. Нажми «вернуть всё».' -ForegroundColor Yellow
} finally { PctUnlock $lk; Enter }
