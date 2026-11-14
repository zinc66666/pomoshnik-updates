# Лишние приложения (APPS-REMOVE): без параметров — список в консоли (только чтение); -Json <файл> — тот же список для окна (без прав и без консоли, ничего не меняет); -Arg <что>.<ключи> — запись из окна через run.ps1.
# -Arg: что — off (удалить), best (удалить только «лишнее», совет 2), on (вернуть из Store удалённое Помощником); ключи — K строк белого списка (PctAppsList, pct-core.ps1) через «-». Список проверяю сам: окну не верю.
# Удаляю только у текущего пользователя (PctAppxRemove: Remove-AppxPackage без -AllUsers, из образа Windows не убираю) — прав администратора не нужно, Store вернёт. С повышением — отказ: удалило бы у администратора.
# Журнал до удаления (PctUndoAdd, kind appx: pfn, full, ver, store, mb), чек «было → стало», возврат — PctAppxInstall (winget из Store; нет winget — страница Store). Размер — папка установки пакета, общие фреймворки не считаю.
# Стенд: PCT_APPS_FAKE=<json> (pct-core.ps1) и PCT_ROOT — журналы и чеки в стенде
param([string]$Json, [string]$Arg)
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
$Stand = [bool]"$env:PCT_APPS_FAKE".Trim()
function StandBad { $Stand -and (-not $env:PCT_ROOT -or -not (PctAppsFake)) }
# МБ папки установки (только сам пакет); нет папки или она пуста — -1 (числа не выдумываю)
function Mb([string]$Loc) { if (-not $Loc -or -not [IO.Directory]::Exists($Loc)) { return -1 }; $b = PctTreeBytes @($Loc); if ($b -le 0) { return -1 }; [int][math]::Max(1, [math]::Round($b / 1MB)) }
# Открытые журналы удаления, от нового к старому
function Opened { $r = @(); $fs = @(); $d = PctDir 'reports'; if ([IO.Directory]::Exists($d)) { try { $fs = @([IO.Directory]::GetFiles($d, 'undo-apps-*.json') | Sort-Object -Descending) } catch { PctUndoLog "apps-remove: журналы не прочитал: $($_.Exception.Message)" } }
  foreach ($f in $fs) { $j = PctUndoLoad ([IO.Path]::GetFileName($f)); if ($j -is [string] -or $j.closed) { continue }; $r += $j }; $r }
# Невозвращённые пункты журналов по приложению: (журнал, пункт)
function Hits($Js, [string]$Pfn) { foreach ($j in $Js) { foreach ($x in @(PctUndoPending $j)) { if ("$($x.kind)" -eq 'appx' -and "$($x.pfn)" -eq $Pfn) { , @($j, $x) } } } }
# Строки: установленное из белого списка (On) и удалённое Помощником (не установлено, есть в журнале). Не установлено и не удаляли — строки нет
function Collect { $have = @{}; foreach ($p in @(PctAppx)) { if (-not $p.Fw) { $have[$p.Pfn] = $p } }; $js = @(Opened)
  foreach ($a in @(PctAppsList)) { if ($a.Pfn -match (PctAppsNever)) { continue }; $p = $have[$a.Pfn]
    if ($p) { if (-not $p.NonRem) { [pscustomobject]@{ A = $a; On = $true; Pkg = $p; Mb = (Mb $p.Loc); Hit = @() } } }
    else { $h = @(Hits $js $a.Pfn); if ($h.Count) { [pscustomobject]@{ A = $a; On = $false; Pkg = $null; Mb = [int]$h[0][1].mb; Hit = $h } } } } }
function Drop($Jr, $X) { $X.state = 'undone'; if (-not @($Jr.items | Where-Object { $_.state -ne 'undone' }).Count) { $Jr.closed = (Get-Date).ToString('s') }; PctUndoSave $Jr }
function MbT([int]$m) { if ($m -lt 0) { '' } elseif ($m -ge 1000) { '{0:0.0} ГБ' -f ($m / 1024) -replace '\.', ',' } else { "$m МБ" } }

if ($Json) { $sw = [Diagnostics.Stopwatch]::StartNew(); $o = [ordered]@{ err = '' }
  if (StandBad) { PctUndoLog "apps-remove: отказ, стенд не подходит"; $o.err = 'stand' }
  else { $o.rows = @(foreach ($r in @(Collect)) { $a = $r.A
      [ordered]@{ k = $a.K; name = $a.N; sub = $a.Sub; what = $a.What; iff = $a.Iff; adv = [int]$a.Adv; grp = $a.Grp; ico = [int]$a.Ico; on = [bool]$r.On; mine = -not $r.On; mb = [int]$r.Mb; ver = $(if ($r.Pkg) { $r.Pkg.Ver } else { '' }) } }) }
  $o.ms = [int]$sw.ElapsedMilliseconds; [IO.File]::WriteAllText($Json, ($o | ConvertTo-Json -Depth 4 -Compress), (New-Object Text.UTF8Encoding $false)); return } # окно читает файл после выхода процесса

if ($Arg) {
  if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
  function Enter { Write-Host "`nEnter — закрыть."; Read-Host | Out-Null }
  function RcOf([string]$Journal) { try { foreach ($f in [IO.Directory]::GetFiles("$(PctDir 'reports')\receipts", '*-apps*.json')) { $x = [IO.File]::ReadAllText($f) | ConvertFrom-Json; if ("$($x.undo.journal)" -eq $Journal) { return [IO.Path]::GetFileName($f) } } } catch { PctUndoLog "apps-remove: чеки не прочитал: $($_.Exception.Message)" }; '' }
  Write-Host "`nЛИШНИЕ ПРИЛОЖЕНИЯ`n" -ForegroundColor Cyan; Step -Safe
  if (StandBad) { Step 'Проверяю стенд'; Step -Fail 'стенд задан неверно' -Do 'Нужны PCT_APPS_FAKE и PCT_ROOT.'; PctUndoLog 'apps-remove: отказ, стенд не подходит'; Enter; return }
  $op, $ks = "$Arg" -split '\.', 2; $ks = @("$ks" -split '-' | Where-Object { $_ -match '^[a-z0-9]{2,12}$' } | Select-Object -Unique)
  if ($op -notin 'off', 'best', 'on' -or -not $ks.Count) { Step 'Читаю задание'; Step -Fail 'не знаю, что менять' -Do 'Нажми кнопку в «Лишних приложениях».'; Enter; return }
  if (PctElevated) { Step 'Проверяю права'; Step -Fail 'запущено с правами — так приложения не удаляю' -Do 'Нажми кнопку в окне Помощника.'; Enter; return }
  $lk = PctLock 'apps' 10; if (-not $lk) { Step 'Проверяю, не идёт ли другое изменение'; Step -Fail 'идёт другое изменение' -Do 'Дождись, пока оно закончится, и нажми ещё раз.'; Enter; return }
  try {
    PctUndoLog "apps-remove: начал $Arg$(if ($Stand) { ' (стенд)' })"
    $known = @(PctAppsList | ForEach-Object { $_.K }); $odd = @($ks | Where-Object { $known -notcontains $_ }); if ($odd.Count) { PctUndoLog "apps-remove: не из белого списка — не трогаю: $($odd -join ', ')" }
    Step 'Смотрю, что установлено' -Hint 'Ничего не меняю'; $pick = @(Collect | Where-Object { $ks -contains $_.A.K })
    if ($op -ne 'on') {
      if ($op -eq 'best') { $pick = @($pick | Where-Object { $_.A.Adv -eq 2 }) }; $pick = @($pick | Where-Object { $_.On })
      if (-not $pick.Count) { Step -Done $(if ($odd.Count -and $odd.Count -eq $ks.Count) { 'не из моего списка — не трогаю' } else { 'уже удалено' }); return }
      Step -Done "установлено: $($pick.Count)"; Step -Plan @(@($pick | ForEach-Object { "Удаляю «$($_.A.N)»" }) + 'Проверяю'); Step -Unsafe
      $jr = PctUndoNew 'apps' 'Лишние приложения'; $done = @(); $bad = @(); $rc = PctReceipt 'apps' 'Лишние приложения' @('disk')
      foreach ($r in $pick) { $a = $r.A; Step "Удаляю «$($a.N)»" -Hint 'Сначала запоминаю, что было'
        $x = PctUndoAdd $jr @{ kind = 'appx'; pfn = $a.Pfn; full = $r.Pkg.Full; ver = $r.Pkg.Ver; store = $a.Store; mb = $r.Mb; old = 'installed' } $a.N
        try { PctAppxRemove $a.Pfn $r.Pkg.Full } catch { PctUndoLog "apps-remove: $($a.N) — $($_.Exception.Message)" }
        if (PctAppxHas $a.Pfn) { Drop $jr $x; $bad += $r; Step -Warn 'Windows не дала удалить'; PctRcDo $rc $a.N 'не вышло' } else { $done += $r; Step -Done 'удалено'; PctRcDo $rc $a.N 'установлено → удалено' } } # место — замером диска в чеке: файлы встроенного пакета Windows может оставить для других учётных записей
      Step 'Проверяю' -Hint 'Смотрю список приложений ещё раз'; PctUndoLog "apps-remove: $Arg — удалил $($done.Count) из $($pick.Count)"
      $head = $(if ($bad.Count -and $done.Count) { 'Не вышло: удалил не всё' } elseif ($bad.Count) { 'Не вышло: Windows не дала удалить' } elseif ($op -eq 'best') { "Сделал как советую: удалил $($done.Count)" } elseif ($done.Count -eq 1) { "Удалил «$($done[0].A.N)»" } else { "Удалил: $($done.Count)" })
      [void](PctReceiptEnd $rc $head $(if ($done.Count) { $jr } else { $null }) 'Ничего не удалено.' 'Вернуть — из Store: нужен интернет, займёт пару минут.')
      if (-not $bad.Count) { Step -Done 'приложений больше нет в списке'; Write-Host "`nГотово." -ForegroundColor Green; return }
      if (-not $done.Count) { Step -Fail 'Windows не дала удалить' -Do 'Попробуй ещё раз или позови помощь.'; return }
      Step -Fail "удалил $($done.Count) из $($pick.Count)" -Do 'Нажми «Удалить» ещё раз или позови помощь.'; return }
    # ---------- Вернуть: только удалённое Помощником (есть в журнале) ----------
    foreach ($r in @($pick | Where-Object { $_.On })) { foreach ($b in @(Hits @(Opened) $r.A.Pfn)) { Drop $b[0] $b[1] } } # уже стоит — возвращать нечего, пункт закрываю
    $back = @($pick | Where-Object { -not $_.On })
    if (-not $back.Count) { Step -Done $(if (@($pick | Where-Object { $_.On }).Count) { 'уже установлено' } else { 'не Помощник удалял — не трогаю' }); return }
    Step -Done "удалено Помощником: $($back.Count)"; Step -Plan @(@($back | ForEach-Object { "Качаю «$($_.A.N)» из Store" }) + 'Проверяю'); Step -Unsafe
    $rc = PctReceipt 'apps' 'Лишние приложения' @('disk') 'undo' (RcOf $back[0].Hit[0][0].file); $okN = 0; $net = 0; $page = 0; $bad = 0
    foreach ($r in $back) { $a = $r.A; Step "Качаю «$($a.N)» из Store" -Hint 'Нужен интернет. Займёт до пары минут'; $res = PctAppxInstall $a.Pfn
      if ($res -eq 'ok') { foreach ($b in $r.Hit) { [void](PctUndoOne $b[0] $b[1]) }; $okN++; Step -Done 'снова в списке приложений'; PctRcDo $rc $a.N 'удалено → снова есть' }
      elseif ($res -eq 'page') { $page++; Step -Warn 'открыл страницу в Store — нажми «Получить»'; PctRcDo $rc $a.N 'открыл страницу в Store' }
      elseif ($res -eq 'net') { $net++; Step -Warn 'нет интернета'; PctRcDo $rc $a.N 'не вышло: нет интернета' }
      else { $bad++; Step -Warn 'Store не дал скачать'; PctRcDo $rc $a.N 'не вышло' } }
    Step 'Проверяю' -Hint 'Смотрю список приложений ещё раз'; PctUndoLog "apps-remove: $Arg — вернул $okN из $($back.Count)$(if ($net) { ", нет интернета: $net" })$(if ($page) { ", страница Store: $page" })"
    $note = $(if ($net) { 'Нет интернета. Подключись и нажми «Вернуть» ещё раз.' } elseif ($page) { 'Store открыт: нажми там «Получить».' } elseif ($bad) { 'Store не дал скачать. Попробуй позже или позови помощь.' } else { '' })
    [void](PctReceiptEnd $rc $(if ($okN -eq $back.Count) { 'Вернул из Store' } elseif ($okN) { "Вернул не всё: $okN из $($back.Count)" } elseif ($net) { 'Не вернул: нет интернета' } elseif ($page) { 'Открыл Store' } else { 'Не вернул: Store не дал скачать' }) $null 'Это возврат. Чтобы удалить снова, нажми «Удалить».' $note)
    if ($okN -eq $back.Count) { Step -Done 'как было' } elseif ($net -and -not ($okN + $page + $bad)) { Step -Fail 'нет интернета' -Do 'Подключись к интернету и нажми «Вернуть» ещё раз.' } elseif ($page -and -not ($okN + $net + $bad)) { Step -Done 'открыл Store — нажми там «Получить»' } else { Step -Fail "вернул $okN из $($back.Count)" -Do $(if ($net) { 'Подключись к интернету и нажми «Вернуть» ещё раз.' } else { 'Попробуй позже или позови помощь.' }) }
  } finally { PctUnlock $lk; Enter }
  return }

# Консоль: только список
$Host.UI.RawUI.WindowTitle = 'Лишние приложения'
Write-Host "ЛИШНИЕ ПРИЛОЖЕНИЯ — пришли вместе с Windows (только смотрю)`n" -ForegroundColor Cyan
$all = @(Collect | Where-Object { $_.On }); if (-not $all.Count) { Write-Host 'Лишних приложений нет.' -ForegroundColor Green }
foreach ($r in $all) { Write-Host ("  {0,-16} {1,8}  {2}{3}" -f $r.A.N, (MbT $r.Mb), $r.A.Sub, $(if ($r.A.Adv -eq 2) { ' — лишнее' })) -ForegroundColor $(if ($r.A.Adv -eq 2) { 'Yellow' } else { 'Gray' }) }
Write-Host "`nУдалить и вернуть — в окне Помощника: «Файлы» → «Лишние приложения». Store, Блокнот, Фото, Калькулятор — не удаляю."; Read-Host 'Enter — закрыть' | Out-Null
