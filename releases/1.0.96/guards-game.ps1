# «Ждать конца игры» (GUARDS-GAME): -Arg on — плановые сторожа ждут, пока игра или фильм на весь экран (PctGame в pct-core.ps1); -Arg off — снова работают сразу.
# Настройка — файл reports\guards-game.on: пишет её учётная запись без повышения, читают сторожа от неё и с повышением. Проверка — окно на весь экран на ~1 с и PctFull.
# Стенд: PCT_GAME_FAKE — окно не показываю, полный экран — по файлу подмены (PctFull)
param([string]$Arg)
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
$Host.UI.RawUI.WindowTitle = 'Ждать конца игры'
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
$on = "$(PctRepDir)\guards-game.on"; $want = $Arg -ne 'off'; $Tool = 'guards-game'; $Title = 'Ждать конца игры'
# Окно на весь экран поверх всех на ~1 с: видит ли Windows полный экран. Окно — цвета Ночь, текст Побелка (DESIGN.md §2)
function Probe { if ($env:PCT_GAME_FAKE) { return (PctFull) }
  Add-Type -AssemblyName System.Windows.Forms, System.Drawing; $f = New-Object Windows.Forms.Form; $seen = $false
  try { $f.FormBorderStyle = 'None'; $f.WindowState = 'Maximized'; $f.TopMost = $true; $f.ShowInTaskbar = $false; $f.BackColor = [Drawing.Color]::FromArgb(10, 22, 34)
    $l = New-Object Windows.Forms.Label; $l.Dock = 'Fill'; $l.TextAlign = 'MiddleCenter'; $l.ForeColor = [Drawing.Color]::FromArgb(239, 231, 214); $l.Font = New-Object Drawing.Font('Segoe UI', 20)
    $l.Text = 'Проверяю: пока это окно на весь экран, сторожа ждут. Сейчас закроется.'; $f.Controls.Add($l); $f.Show(); $f.Activate()
    for ($i = 0; $i -lt 25 -and -not $seen; $i++) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100; if ($i -ge 4) { $seen = PctFull } } }
  finally { $f.Close(); $f.Dispose() }
  $seen }
function Save([bool]$v) { try { if ($v) { [IO.File]::WriteAllText($on, '', (New-Object Text.UTF8Encoding $false)) } else { [IO.File]::Delete($on) }; $true } catch { $false } }
[void][IO.Directory]::CreateDirectory((PctRepDir)); $was = [IO.File]::Exists($on)
if ($want) { Step -Plan 'Запоминаю, как было', 'Учу сторожей ждать полный экран', 'Проверяю'; Step -Safe
  Step 'Запоминаю, как было'; Step -Done $(if ($was) { 'сторожа уже ждут' } else { 'сторожа не ждут' })
  Step 'Учу сторожей ждать полный экран'; Step -Unsafe
  if (-not (Save $true)) { Step -Fail 'не получилось сохранить' -Do 'Попробуй ещё раз или позови помощь.'; Write-Host 'Не получилось сохранить настройку. Сторожа работают как раньше.' -ForegroundColor Red; return }
  Step -Done 'готово'
  Step 'Проверяю' -Hint 'Запускаю окно на весь экран'; $ok = Probe
  if ($ok) { Step -Done 'сторож ждёт ✓' } else { Step -Warn 'не увидел полный экран' }
  $rc = PctReceipt $Tool $Title; PctRcDo $rc 'Сторожа в игре' $(if ($was) { 'ждут конца → ждут конца' } else { 'работают → ждут конца' })
  $note = $(if ($ok) { '' } else { 'Проверка не увидела окно на весь экран. Настройка сохранена — сторожа подождут, как только Windows покажет игру на весь экран.' })
  [void](PctReceiptEnd $rc 'Сторожа ждут конца игры' $null 'Чтобы сторожа снова работали сразу, нажми «Не ждать» в «Дозоре за сутки».' $note)
  Write-Host "`nСторожа ждут конца игры.$(if (-not $ok) { ' Проверка не увидела полный экран.' })" -ForegroundColor Green; return }
Step -Plan 'Запоминаю, как было', 'Возвращаю: сторожа не ждут'; Step -Safe
Step 'Запоминаю, как было'; Step -Done $(if ($was) { 'сторожа ждут конца игры' } else { 'сторожа уже не ждут' })
Step 'Возвращаю: сторожа не ждут'; Step -Unsafe
if (-not (Save $false)) { Step -Fail 'не получилось сохранить' -Do 'Попробуй ещё раз или позови помощь.'; Write-Host 'Не получилось сохранить настройку. Сторожа по-прежнему ждут конца игры.' -ForegroundColor Red; return }
Step -Done 'готово'
$rc = PctReceipt $Tool $Title; PctRcDo $rc 'Сторожа в игре' $(if ($was) { 'ждут конца → работают' } else { 'работают → работают' })
[void](PctReceiptEnd $rc 'Сторожа работают сразу, даже в игре' $null 'Чтобы сторожа снова ждали, нажми «Ждать конца игры» в «Дозоре за сутки».' '')
Write-Host "`nСторожа работают сразу, даже в игре." -ForegroundColor Green
