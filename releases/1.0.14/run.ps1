# Запуск инструмента Помощника без окна PowerShell: весь вывод (с цветами) и вопросы идут в файл, окно Помощника показывает их вживую.
# Строки журнала: L|цвет|текст — вывод; P|цвет|вопрос — ждём ответ в <id>.ans; A|цвет|ответ; E|цвет|секунды — готово (Red — инструмент прервался из-за ошибки, Gray — без ошибки);
# S|plan|шаг|шаг… — шаги впереди (○); S|now|шаг|подсказка — начал шаг (⟳); S|done|итог, S|warn|итог, S|fail|итог — закрыл текущий шаг (✓, ✓ с замечанием, ✗). Пишет функция Step.
param([Parameter(Mandatory)][string]$Script, [Parameter(Mandatory)][string]$Id, [int]$Owner = 0)
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
$dir = PctDir 'run'; New-Item -ItemType Directory -Force $dir | Out-Null
$global:RunLog = "$dir\$Id.log"; $global:RunAns = "$dir\$Id.ans"; $global:RunLast = ''; $global:RunBuf = ''; $global:RunBufColor = 'Gray'; $global:RunOwner = $Owner; $global:RunSw = [Diagnostics.Stopwatch]::StartNew()
$global:RunEnc = New-Object Text.UTF8Encoding $false
function global:Emit($kind, $color, $text) { $t = "$text" -replace "[`r`n]+", ' '; if ($kind -eq 'L') { $global:RunLast = $t }
  for ($i = 0; $i -lt 5; $i++) { try { [IO.File]::AppendAllText($global:RunLog, "$kind|$color|$t`n", $global:RunEnc); return } catch { Start-Sleep -Milliseconds 40 } } }
# Журнал ошибок инструментов: reports\run-errors.log (UTF-8, одна строка), больше 512 КБ → run-errors.old.log. Сбой записи не мешает работе
function global:RunErr($text) { try { $d = PctDir 'reports'; [void][IO.Directory]::CreateDirectory($d); $f = "$d\run-errors.log"
    if (([IO.FileInfo]$f).Exists -and ([IO.FileInfo]$f).Length -gt 512KB) { $o = "$d\run-errors.old.log"; if (Test-Path -LiteralPath $o) { [IO.File]::Delete($o) }; [IO.File]::Move($f, $o) }
    $t = "$text" -replace "[`r`n]+", ' '; [IO.File]::AppendAllText($f, "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $(Split-Path $Script -Leaf) [$Id] $t`n", $global:RunEnc) } catch {} }
function global:RunErrRec($r) { $i = $r.InvocationInfo; $w = ''; if ($i -and $i.ScriptName) { $w = " @ $(Split-Path $i.ScriptName -Leaf):$($i.ScriptLineNumber)" }; RunErr "$($r.Exception.Message)$w" }
function global:EmitText($color, $t) { foreach ($ln in ($t -split "`r?`n")) { if ($ln -match 'Нажмите Enter,? чтобы закрыть|Enter — закрыть') { $global:RunLast = $ln; continue }; Emit 'L' $color $ln } }
# Накопленное Write-Host -NoNewline выводим строкой
function global:RunFlush { if ($global:RunBuf -ne '') { $b = $global:RunBuf; $global:RunBuf = ''; EmitText $global:RunBufColor $b } }
function global:Write-Host { param([Parameter(Position = 0, ValueFromRemainingArguments = $true)]$Object, $ForegroundColor = 'Gray', $BackgroundColor, [switch]$NoNewline, $Separator = ' ')
  $t = (@($Object) | ForEach-Object { "$_" }) -join $Separator
  if ($global:RunBuf -eq '') { $global:RunBufColor = $ForegroundColor }
  if ($NoNewline) { $global:RunBuf += $t; return }
  $t = $global:RunBuf + $t; $c = $global:RunBufColor; $global:RunBuf = ''; EmitText $c $t }
function global:Read-Host { param([Parameter(Position = 0)]$Prompt, [switch]$AsSecureString)
  $close = 'Enter,? чтобы закрыть|Enter — закрыть|Enter - закрыть'
  if (("$Prompt $global:RunBuf $global:RunLast") -match $close) { if ($global:RunBuf -match $close) { $global:RunBuf = '' } else { RunFlush }; return '' }
  RunFlush; Remove-Item -LiteralPath $global:RunAns -Force -ErrorAction SilentlyContinue; Emit 'P' 'Cyan' "$Prompt"
  # Окно Помощника (-Owner) пропало — ответа не будет, выходим
  $sw = [Diagnostics.Stopwatch]::StartNew(); $ck = 0
  while (-not (Test-Path -LiteralPath $global:RunAns) -and $sw.Elapsed.TotalMinutes -lt 30) { Start-Sleep -Milliseconds 200
    if ($global:RunOwner -gt 0 -and $sw.Elapsed.TotalSeconds -ge $ck + 1) { $ck = [int]$sw.Elapsed.TotalSeconds
      if (-not (Get-Process -Id $global:RunOwner -ErrorAction SilentlyContinue)) { RunErr 'окно закрылось, вопрос без ответа'; Emit 'E' 'Gray' ([int]$global:RunSw.Elapsed.TotalSeconds); [Environment]::Exit(1) } } }
  Start-Sleep -Milliseconds 60; $a = "$(Get-Content -LiteralPath $global:RunAns -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)".Trim(); Remove-Item -LiteralPath $global:RunAns -Force -ErrorAction SilentlyContinue; Emit 'A' 'White' $a; $a }
function global:Clear-Host {}
# Шаг для окна: Step 'текст' [-Hint 'подсказка'] · Step -Done|-Warn|-Fail 'итог' · Step -Plan 'шаг','шаг'. Знак | в тексте меняем на /
function global:Step { param([Parameter(Position = 0)]$Text, $Hint, $Done, $Warn, $Fail, [string[]]$Plan) RunFlush; $c = { "$args" -replace '\|', '/' }
  if ($Plan) { Emit 'S' 'plan' (($Plan | ForEach-Object { & $c $_ }) -join '|') } elseif ($PSBoundParameters.ContainsKey('Fail')) { Emit 'S' 'fail' (& $c $Fail) }
  elseif ($PSBoundParameters.ContainsKey('Warn')) { Emit 'S' 'warn' (& $c $Warn) } elseif ($PSBoundParameters.ContainsKey('Done')) { Emit 'S' 'done' (& $c $Done) } else { Emit 'S' 'now' "$(& $c $Text)|$(& $c $Hint)" } }
# Continue: ошибки инструментов без своего $ErrorActionPreference попадают в поток и в run-errors.log (в окне их нет)
$ErrorActionPreference = 'Continue'
try { & $Script *>&1 | ForEach-Object { if ($_ -is [Management.Automation.ErrorRecord]) { RunErrRec $_ } elseif ("$_".Trim()) { Emit 'L' 'Gray' "$_" } } }
catch { $global:RunFail = $true; RunFlush; RunErrRec $_; Emit 'L' 'Red' 'Действие прервалось из-за ошибки. Я записал подробности для помощи.' }
RunFlush; Emit 'E' $(if ($global:RunFail) { 'Red' } else { 'Gray' }) ([int]$global:RunSw.Elapsed.TotalSeconds)
