# Запуск инструмента Помощника без окна PowerShell: весь вывод (с цветами) и вопросы идут в файл, окно Помощника показывает их вживую.
# Строки журнала: L|цвет|текст — вывод; P|цвет|вопрос — ждём ответ в <id>.ans; A|цвет|ответ; E|цвет|секунды — готово.
param([Parameter(Mandatory)][string]$Script, [Parameter(Mandatory)][string]$Id)
$ErrorActionPreference = 'SilentlyContinue'
$dir = 'C:\PC-Tweaks-Laptop\run'; New-Item -ItemType Directory -Force $dir | Out-Null
$global:RunLog = "$dir\$Id.log"; $global:RunAns = "$dir\$Id.ans"; $global:RunLast = ''
$global:RunEnc = New-Object Text.UTF8Encoding $false
function global:Emit($kind, $color, $text) { $t = "$text" -replace "[`r`n]+", ' '; if ($kind -eq 'L') { $global:RunLast = $t }
  for ($i = 0; $i -lt 5; $i++) { try { [IO.File]::AppendAllText($global:RunLog, "$kind|$color|$t`n", $global:RunEnc); return } catch { Start-Sleep -Milliseconds 40 } } }
function global:Write-Host { param([Parameter(Position = 0, ValueFromRemainingArguments = $true)]$Object, $ForegroundColor = 'Gray', $BackgroundColor, [switch]$NoNewline, $Separator = ' ')
  $t = (@($Object) | ForEach-Object { "$_" }) -join $Separator; foreach ($ln in ($t -split "`r?`n")) { if ($ln -match 'Нажмите Enter,? чтобы закрыть|Enter — закрыть') { $global:RunLast = $ln; continue }; Emit 'L' $ForegroundColor $ln } }
function global:Read-Host { param([Parameter(Position = 0)]$Prompt, [switch]$AsSecureString)
  if (("$Prompt $global:RunLast") -match 'Enter,? чтобы закрыть|Enter — закрыть|Enter - закрыть') { return '' }
  Remove-Item -LiteralPath $global:RunAns -Force; Emit 'P' 'Cyan' "$Prompt"
  $sw = [Diagnostics.Stopwatch]::StartNew(); while (-not (Test-Path -LiteralPath $global:RunAns) -and $sw.Elapsed.TotalMinutes -lt 30) { Start-Sleep -Milliseconds 200 }
  Start-Sleep -Milliseconds 60; $a = "$(Get-Content -LiteralPath $global:RunAns -Raw -Encoding UTF8)".Trim(); Remove-Item -LiteralPath $global:RunAns -Force; Emit 'A' 'White' $a; $a }
function global:Clear-Host {}
$sw = [Diagnostics.Stopwatch]::StartNew()
try { & $Script *>&1 | ForEach-Object { if ($_ -isnot [Management.Automation.ErrorRecord] -and "$_".Trim()) { Emit 'L' 'Gray' "$_" } } }
catch { Emit 'L' 'Red' "Ошибка: $($_.Exception.Message)" }
Emit 'E' 'Gray' ([int]$sw.Elapsed.TotalSeconds)
