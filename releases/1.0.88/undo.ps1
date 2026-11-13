# «Вернуть как было» по журналу (RECEIPT, основа 9l): -Arg <undo-…json> из reports\. Пункты — с последнего; подряд идущие с одним текстом — один шаг ✓/⟳/○; после каждого журнал записан (pct-core.ps1).
# Итог — новый чек «Вернул как было» (kind undo, of — чек, который возвращаю). Журнал с правами (admin) окно запускает от администратора; с повышением при UAC — только запечатанный
param([string]$Arg)
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
$Host.UI.RawUI.WindowTitle = 'Вернуть как было'
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
function Enter { Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null }
function Low($s) { if ($s) { $s.Substring(0, 1).ToLower() + $s.Substring(1) } }

Write-Host "`nВЕРНУТЬ КАК БЫЛО`n" -ForegroundColor Cyan
Step -Safe
$j = PctUndoLoad $Arg
if ($j -is [string]) { Step 'Читаю, что было'; Step -Fail $j -Do 'Позови помощь — по журналу видно, что случилось.'; PctUndoLog "отказ: $Arg — $j"; Write-Host "Не могу вернуть: $j." -ForegroundColor Yellow; Enter; return }
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($j.admin -and -not $admin) { Step 'Проверяю права'; Step -Fail 'нет разрешения Windows' -Do 'Нажми «Вернуть как было» ещё раз и выбери «Да» в окне Windows.'; Write-Host 'Нужно разрешение Windows.' -ForegroundColor Yellow; Enter; return }
# Чек, который возвращаю (в нём этот журнал): его быстрые замеры — и в чеке возврата
$of = ''; $kinds = @(); try { foreach ($f in [IO.Directory]::GetFiles("$(PctDir 'reports')\receipts", '*.json')) { $x = [IO.File]::ReadAllText($f) | ConvertFrom-Json; if ("$($x.undo.journal)" -eq $Arg) { $of = [IO.Path]::GetFileName($f); $kinds = @($x.kinds | Where-Object { $_ -in 'disk', 'mem', 'procs', 'autorun', 'net' }); break } } } catch { PctUndoLog "чеки не прочитал: $($_.Exception.Message)" }
$lk = PctLock $j.tool; if (-not $lk) { Step 'Проверяю, не идёт ли другое действие'; Step -Fail "идёт «$($j.title)»" -Do 'Дождись, пока оно закончится, и нажми «Вернуть как было» ещё раз.'; Write-Host 'Сейчас идёт другое действие. Дождись его конца.' -ForegroundColor Yellow; Enter; return }
try {
  PctUndoLog "начал: $Arg ($($j.title))"
  $p = @(PctUndoPending $j)
  if (-not $p.Count) { Step 'Читаю, что было'; Step -Done 'уже возвращено'; Write-Host 'Это уже вернул — возвращать нечего.' -ForegroundColor Green; return }
  # Шаги: подряд идущие пункты с одним текстом — один шаг; после восьмого — «Остальное» одним шагом (экран хода не прокручивается)
  $g = New-Object Collections.ArrayList
  foreach ($x in $p) { if ($g.Count -and ($g[-1].T -eq $x.text -or $g.Count -ge 9)) { $g[-1].I += $x } elseif ($g.Count -eq 8) { [void]$g.Add([pscustomobject]@{ T = 'Остальное'; I = @($x) }) } else { [void]$g.Add([pscustomobject]@{ T = "$($x.text)"; I = @($x) }) } }
  $rc = PctReceipt $j.tool "$($j.title)" $kinds 'undo' $of
  Step -Plan @($g | ForEach-Object { "Возвращаю: $(Low $_.T)" })
  # Сеть рвётся — ждём, пока подбор обхода закончит проверку сайтов
  $nic = [bool]@($p | Where-Object { $_.kind -eq 'power-nic' }).Count; $nk = $null
  if ($nic) { $nk = PctNetLock { Write-Host 'Идёт подбор обхода блокировок. Жду, пока он закончится, чтобы не оборвать ему сеть.' -ForegroundColor Yellow }
    if (-not $nk) { Step "Возвращаю: $(Low $g[0].T)"; Step -Fail 'сеть занята подбором обхода' -Do 'Подожди и нажми «Вернуть как было» ещё раз.'; return } }
  Step -Unsafe; $bad = New-Object Collections.ArrayList; $all = 0; $okN = 0
  foreach ($x in $g) { $n = @($x.I | Where-Object { $_.kind -eq 'power-nic' }).Count
    Step "Возвращаю: $(Low $x.T)" -Hint $(if ($n) { 'Интернет пропадёт на несколько секунд' } elseif (@($x.I | Where-Object { $_.kind -eq 'appx' }).Count) { 'Качаю из Store: нужен интернет, займёт до пары минут' } else { 'Ничего не трогай' }); $ok = 0
    foreach ($i in $x.I) { $all++; if (PctUndoOne $j $i) { $ok++ } }; $okN += $ok
    if ($ok -lt $x.I.Count) { [void]$bad.Add($x.T); Step -Warn $(if ($ok) { "вернул $ok из $($x.I.Count)" } else { 'не вышло' }); if ($ok) { PctRcDo $rc $x.T "вернул $ok из $($x.I.Count)" } }
    else { Step -Done 'как было'; PctRcDo $rc $x.T 'как было' } }
  $zar = [bool]@($j.items | Where-Object { $_.kind -eq 'power-overlay' -and $_.state -ne 'undone' }).Count
  $note = $(if ($bad.Count) { "Не вернул: $(@($bad | ForEach-Object { Low $_ }) -join ', '). $(if ($zar) { 'Подключи зарядку и ' } else { '' })Нажми «Вернуть как было» ещё раз — верну оставшееся." } else { '' })
  $head = $(if ($bad.Count) { "Вернул не всё: $okN из $all" } else { 'Вернул как было' })
  [void](PctReceiptEnd $rc $head $null "Это возврат. Чтобы поменять снова, запусти «$($j.title)»." $note)
  PctUndoLog "готово: $Arg — вернул $okN из $all$(if ($bad.Count) { ", не вышло: $($bad -join ', ')" })"
  if ($bad.Count) { Write-Host "`n$note" -ForegroundColor Yellow } else { Write-Host "`nВернул всё как было." -ForegroundColor Green }
} finally { PctUnlock $nk; PctUnlock $lk; Enter }
