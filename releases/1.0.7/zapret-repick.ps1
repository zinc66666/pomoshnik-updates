# Подбор рабочей стратегии zapret. -Auto: без окна, итог уведомлением (запускает PCT-Sites-Watch). Файлы zapret не меняет.
param([switch]$Auto)
$ErrorActionPreference = 'SilentlyContinue'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""; return }
. "$PSScriptRoot\pct-core.ps1"
$Hd = PctDir 'helpers'; $saved = "$Hd\zapret-cmd.txt"; $logf = "$(PctDir 'reports')\zapret-repick.log"
$cfg = Get-Content $saved -Encoding UTF8
$Z = if ($cfg -and (Test-Path -LiteralPath $cfg[0])) { Split-Path (Split-Path $cfg[0]) } else { Get-ChildItem ([Environment]::GetFolderPath('Desktop')) -Recurse -Depth 3 -Filter 'winws.exe' | Select-Object -First 1 | ForEach-Object { Split-Path (Split-Path $_.FullName) } }
$urls = [ordered]@{ 'YouTube' = 'https://www.youtube.com'; 'YT-видео' = 'https://redirector.googlevideo.com/report_mapping'; 'YT-картинки' = 'https://i.ytimg.com/generate_204'
  'Discord' = 'https://discord.com'; 'Discord-чат' = 'https://gateway.discord.gg'; 'Discord-файлы' = 'https://cdn.discordapp.com' }
$log = New-Object Collections.Generic.List[string]
function Say($t, $c = 'Gray') { $log.Add($t); if (-not $Auto) { Write-Host $t -ForegroundColor $c } }
function Test-Sites { $ok = 0; $ms = 0; $miss = @()
  foreach ($k in $urls.Keys) { $r = & curl.exe -s -o NUL -w '%{http_code} %{time_total}' --max-time 6 $urls[$k] 2>$null
    if ($r -and $r -notmatch '^000') { $ok++; $ms += [double]$r.Split(' ')[1] * 1000 } else { $miss += $k } }
  [pscustomobject]@{ Ok = $ok; Ms = [math]::Round($ms); Miss = ($miss -join ', ') } }
function Norm($c) { (($c -replace '^\s*"[^"]+"\s*|^\s*\S+\s*', '') -replace '--wf-iface=\S+\s*', '').Trim() }
function Stop-Z { Get-Process winws | Stop-Process -Force; Start-Sleep 2 }
function Finish($title, $msg, $good) {
  Say "`n$msg" $(if ($good) { 'Green' } else { 'Yellow' })
  Add-Content -LiteralPath $logf (("=== {0:yyyy-MM-dd HH:mm} {1}" -f (Get-Date), $(if ($Auto) { 'авто' } else { 'вручную' })) + "`r`n" + ($log -join "`r`n")) -Encoding UTF8
  if ($Auto) { . "$(PctDir 'guard')\notify.ps1"; Send-Notify $title $msg }
  else { Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null } }
if (-not $Auto) { $Host.UI.RawUI.WindowTitle = 'Подбор способа обхода блокировок — не закрывай окно'
  Write-Host "`nПОДБОР СПОСОБА ОБХОДА БЛОКИРОВОК`n" -ForegroundColor Cyan
  Write-Host 'Займёт до 10 минут. YouTube и Discord в это время могут прерываться.'; Write-Host "Окно не закрывай.`n" }
if (-not (Test-Path -LiteralPath $Z)) { Finish 'Обход блокировок' "Папка zapret не найдена. Нажми «Позвать помощь»." $false; return }
if (Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -match 'Wintun|TAP|TUN|Happ|sing|xray' }) {
  Finish 'Обход блокировок' 'Сейчас включён VPN-туннель (TUN) — проверка будет неверной. Выключи его в Happ и запусти ещё раз.' $false; return }
if (-not (Get-Process winws)) { Say 'Обход был выключен — включаю...'; & "$Hd\start-zapret.ps1"; Start-Sleep 5 }
$now = Test-Sites; Say ("Сейчас открывается {0} из 6{1}" -f $now.Ok, $(if ($now.Miss) { " (нет: $($now.Miss))" }))
if ($now.Ok -eq 6) {
  if ($Auto) { Finish 'Обход блокировок' 'YouTube и Discord снова открываются — менять ничего не пришлось.' $true; return }
  Write-Host "`nВсё и так работает. Всё равно подобрать заново? Напиши д и Enter. Просто Enter — не надо." -ForegroundColor Cyan
  if ((Read-Host) -notmatch '^\s*[дДyY]') { Finish 'Обход блокировок' 'Всё работает, ничего не менял.' $true; return } }
if (Test-Path $saved) { Copy-Item $saved "$saved.bak-$(Get-Date -f yyyyMMdd-HHmm)" -Force }
Stop-Z; $base = Test-Sites; Say "Без обхода: $($base.Ok) из 6"
$bats = @(Get-ChildItem $Z -Filter '*.bat' | Where-Object Name -notmatch '^service'); $n = 0; $res = @()
foreach ($b in $bats) { $n++
  Say ("Проверяю способ {0} из {1}: {2}" -f $n, $bats.Count, $b.BaseName)
  Stop-Z
  Start-Process cmd.exe -ArgumentList "/c `"`"$($b.FullName)`" < NUL`"" -WorkingDirectory $Z -WindowStyle Hidden
  $t = 0; while (-not (Get-Process winws) -and $t -lt 20) { Start-Sleep 1; $t++ }
  if (-not (Get-Process winws)) { Say '   не запустился' 'DarkGray'; continue }
  Start-Sleep 3; $s = Test-Sites; $p = Get-CimInstance Win32_Process -Filter "Name='winws.exe'" | Select-Object -First 1
  Say ("   открывается {0} из 6" -f $s.Ok) $(if ($s.Ok -eq 6) { 'Green' } else { 'DarkGray' })
  $res += [pscustomobject]@{ Name = $b.BaseName; Ok = $s.Ok; Ms = $s.Ms; Cmd = $p.CommandLine; Exe = $p.ExecutablePath }
  if ($s.Ok -eq 6) { break } }
Stop-Z
$best = $res | Where-Object { $_.Cmd -and $_.Exe } | Sort-Object @{ e = 'Ok'; Descending = $true }, Ms | Select-Object -First 1
if ($best -and $best.Ok -gt $base.Ok) {
  [IO.File]::WriteAllLines($saved, [string[]]@($best.Exe, (Norm $best.Cmd)), (New-Object Text.UTF8Encoding $true))
  & "$Hd\start-zapret.ps1"; Start-Sleep 5; $f = Test-Sites
  Finish $(if ($f.Ok -eq 6) { 'Обход блокировок починен' } else { 'Обход блокировок починен частично' }) ("Выбран способ «{0}»: открывается {1} из 6{2}. Он будет включаться сам." -f $best.Name, $f.Ok, $(if ($f.Miss) { " (нет: $($f.Miss))" })) ($f.Ok -eq 6)
} else { & "$Hd\start-zapret.ps1"
  Finish 'Обход блокировок не починился' 'Ни один способ не помог — нужна новая версия zapret. Нажми «Позвать помощь».' $false }