# «Фоновые приложения» (AP-1, правило автопилота): приложения из Microsoft Store в фоне — выключить или вернуть. -Arg off | on. Без прав администратора: только её HKCU.
# Значение: HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications, GlobalUserDisabled = DWORD 1 — фон выключен. Политику AppPrivacy (HKLM) не трогаю.
# off: уже 1 — ничего не меняю (ни журнала, ни чека). Иначе до записи — журнал возврата (pct-core.ps1) с прежним значением или «значения не было», запись, чтение обратно, чек.
# on: только точный возврат того, что записал Помощник (открытые журналы bg-apps); сейчас уже не 1 — человек поменял сам: не трогаю, пункт закрываю.
# Стенд: PCT_PRIV_ROOT=Software\PomoshnikTest\<стенд> — ключ HKCU\<стенд>\HKCU\… вместо настоящего (как tweaks-bg.ps1)
param([string]$Arg)
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
$Host.UI.RawUI.WindowTitle = 'Фоновые приложения'
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
function Enter { Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null }
$Tool = 'bg-apps'; $Title = 'Фоновые приложения'; $Txt = 'Приложения в фоне'; $Name = 'GlobalUserDisabled'
# Стенд: только свой ключ в HKCU. Задан неверно — не трогаю ничего
$St = "$env:PCT_PRIV_ROOT".Trim().TrimEnd('\'); $Stand = [bool]$St; $StandOk = $St -match '^Software\\PomoshnikTest\\[A-Za-z0-9_-]+$'
$Key = "HKCU\$(if ($Stand) { "$St\HKCU\" })Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
# DWORD или $null (нет значения, другой тип)
function Dw { $k = PctRegKey $Key; if (-not $k) { return $null }
  try { if ($k.GetValueNames() -notcontains $Name -or "$($k.GetValueKind($Name))" -ne 'DWord') { return $null }; [int]$k.GetValue($Name) } finally { $k.Close() } }
# Пункт вернулся: значения не было — его нет; было — ровно старое
function IsBack($X) { $k = PctRegKey $X.key; $has = $k -and $k.GetValueNames() -contains $X.name; $v = $(if ($has) { "$($k.GetValue($X.name, $null, 'DoNotExpandEnvironmentNames'))" }); if ($k) { $k.Close() }
  if (-not $X.existed) { return -not $has }; $has -and $v -eq "$($X.old)" }
function Close1($J) { if (-not @($J.items | Where-Object { $_.state -ne 'undone' }).Count) { $J.closed = (Get-Date).ToString('s') }; PctUndoSave $J }
# Открытые журналы этого инструмента — от нового к старому
function Opened { $r = @(); $fs = @(); try { $fs = @([IO.Directory]::GetFiles((PctDir 'reports'), "undo-$Tool-*.json") | Sort-Object -Descending) } catch { PctUndoLog "bg-apps: журналы не прочитал: $($_.Exception.Message)" }
  foreach ($f in $fs) { $j = PctUndoLoad ([IO.Path]::GetFileName($f)); if ($j -is [string] -or $j.closed) { continue }; $r += $j }; $r }
function RcOf([string]$Journal) { try { foreach ($f in [IO.Directory]::GetFiles("$(PctDir 'reports')\receipts", "*-$Tool*.json")) { $x = [IO.File]::ReadAllText($f) | ConvertFrom-Json; if ("$($x.undo.journal)" -eq $Journal) { return [IO.Path]::GetFileName($f) } } } catch { PctUndoLog "bg-apps: чеки не прочитал: $($_.Exception.Message)" }; '' }

Write-Host "`nФОНОВЫЕ ПРИЛОЖЕНИЯ`n" -ForegroundColor Cyan
Step -Safe
if ($Stand -and -not $StandOk) { Step 'Проверяю стенд'; Step -Fail 'стенд задан неверно' -Do 'Нужен PCT_PRIV_ROOT=Software\PomoshnikTest\<имя>.'; PctUndoLog "bg-apps: отказ, стенд не подходит ($St)"; Write-Host 'Стенд задан неверно — ничего не трогаю.' -ForegroundColor Yellow; Enter; return }
if ($Arg -notin 'on', 'off') { Step 'Читаю задание'; Step -Fail 'не знаю, что менять' -Do 'Запусти правило ещё раз.'; Write-Host 'Не знаю, что менять.' -ForegroundColor Yellow; Enter; return }
$lk = PctLock $Tool 10; if (-not $lk) { Step 'Проверяю, не идёт ли другое изменение'; Step -Fail 'идёт другое изменение' -Do 'Дождись, пока оно закончится.'; Write-Host 'Сейчас идёт другое изменение. Дождись его конца.' -ForegroundColor Yellow; Enter; return }
try {
  PctUndoLog "bg-apps: начал $Arg$(if ($Stand) { ' (стенд)' })"
  # ---------- Вернуть: только то, что записал Помощник ----------
  if ($Arg -eq 'on') {
    Step -Plan 'Смотрю, как сейчас', 'Возвращаю приложения в фоне', 'Проверяю'
    Step 'Смотрю, как сейчас' -Hint 'Ничего не меняю'; $back = @(foreach ($j in @(Opened)) { foreach ($x in @(PctUndoPending $j)) { if ("$($x.key)" -eq $Key -and "$($x.name)" -eq $Name) { , @($j, $x) } } })
    if (-not $back.Count) { Step -Done 'не Помощник выключал — не трогаю'; Write-Host 'Это выключил не Помощник — не трогаю.' -ForegroundColor Green; return }
    $j0 = $back[0][0].file
    # Сейчас уже не 1 — человек поменял сам: пункт закрываю, значение не трогаю
    if ((Dw) -ne 1) { foreach ($b in $back) { $b[1].state = 'undone'; Close1 $b[0] }; Step -Done 'ты уже поменял это сам — не трогаю'; PctUndoLog 'bg-apps: on — поменяли мимо Помощника, не трогаю'; Write-Host 'Ты уже поменял это сам — не трогаю.' -ForegroundColor Green; return }
    Step -Done 'выключено Помощником'; Step -Unsafe; Step 'Возвращаю приложения в фоне' -Hint 'Возвращаю, как было до Помощника'
    $rc = PctReceipt $Tool $Title @('mem') 'undo' (RcOf $j0); $ok = 0; foreach ($b in $back) { if ((PctUndoOne $b[0] $b[1]) -and (IsBack $b[1])) { $ok++ } }
    Step 'Проверяю' -Hint 'Читаю обратно'; $good = $ok -eq $back.Count
    if ($good) { Step -Done 'как было' } else { Step -Fail "вернул $ok из $($back.Count)" -Do 'Нажми «Вернуть как было» в чеке или позови помощь.' }
    PctRcDo $rc $Txt $(if ($good) { 'как было' } else { "вернул $ok из $($back.Count)" })
    [void](PctReceiptEnd $rc $(if ($good) { 'Вернул приложения в фоне' } else { 'Вернул не всё' }) $null 'Это возврат. Чтобы выключить снова, запусти правило ещё раз.')
    PctUndoLog "bg-apps: on — вернул $ok из $($back.Count)"; return }
  # ---------- Выключить ----------
  Step -Plan 'Смотрю, как сейчас', 'Выключаю приложения в фоне', 'Проверяю'
  Step 'Смотрю, как сейчас' -Hint 'Ничего не меняю'
  if ((Dw) -eq 1) { Step -Done 'уже выключено'; Write-Host 'Приложения в фоне уже выключены.' -ForegroundColor Green; return }
  Step -Done 'приложения работают в фоне'; Step -Unsafe; Step 'Выключаю приложения в фоне' -Hint 'Сначала запоминаю, как было'
  $rc = PctReceipt $Tool $Title @('mem'); $j = PctUndoNew $Tool $Title; $it = PctUndoAdd $j @{ kind = 'reg'; key = $Key; name = $Name } $Txt
  try { $k = PctRegKey $Key -Create; if ($k) { $k.SetValue($Name, 1, [Microsoft.Win32.RegistryValueKind]::DWord); $k.Close() } } catch { PctUndoLog "bg-apps: запись — $($_.Exception.Message)" }
  Step 'Проверяю' -Hint 'Читаю обратно'
  if ((Dw) -ne 1) { $it.state = 'undone'; Close1 $j; Step -Fail 'Windows не дала поменять' -Do 'Попробуй ещё раз или позови помощь.'; PctUndoLog 'bg-apps: off — не записалось'; Write-Host 'Не получилось: Windows оставила как было.' -ForegroundColor Yellow; return }
  Step -Done 'выключено'; PctRcDo $rc $Txt 'работают → выключены'
  [void](PctReceiptEnd $rc 'Выключил приложения в фоне' $j '' 'Приложения из Microsoft Store не будут работать, пока закрыты. Уведомления от них могут приходить позже.')
  PctUndoLog 'bg-apps: off — готово'; Write-Host "`nВыключил приложения в фоне." -ForegroundColor Green
} finally { PctUnlock $lk; Enter }
