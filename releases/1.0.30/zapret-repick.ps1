# Подбор рабочей стратегии zapret. -Auto: без окна, итог уведомлением (запускает PCT-Sites-Watch). Файлы zapret не меняет.
param([switch]$Auto)
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками, при -Auto — в run\bg-sites-watch.json (PctBg)
if (-not (Test-Path function:Step)) { if ($Auto) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan) { $script:bgOf = @($Plan).Count; $script:bgN = 0 }; if ($t) { $script:bgN++; PctBg 'sites-watch' $t -Hint $Hint -N $script:bgN -Of $script:bgOf } } } else { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } } }
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""; return }
Step -Safe
# Одно изменение обхода за раз (PctLock): занято — ручной подбор говорит, что делать, -Auto выходит тихо. Ничего не меняет
$lk = PctLock 'zapret'; if (-not $lk) { Add-Content -LiteralPath "$(PctDir 'reports')\zapret-repick.log" ("=== {0:yyyy-MM-dd HH:mm} {1}`r`nобход уже подбирается — пропуск" -f (Get-Date), $(if ($Auto) { 'авто' } else { 'вручную' })) -Encoding UTF8
  if (-not $Auto) { $do = 'Подожди: ход виден в разделе «Сторожа». Если через 10 минут не открывается — нажми ещё раз.'; Step 'Начинаю подбор'; Step -Fail 'сторож уже подбирает обход' -Do $do; Write-Host "`nСторож уже подбирает обход. $do"; Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null }; return }
# Сеть — по одному (PctNetLock): энергосбережение сетевой карты рвёт сеть, а подбор в это время проверяет сайты. Занято — ждёт, строка в журнал и в окно
$nk = PctNetLock { Add-Content -LiteralPath "$(PctDir 'reports')\zapret-repick.log" ("=== {0:yyyy-MM-dd HH:mm} {1}`r`nсеть занята (энергосбережение) — жду" -f (Get-Date), $(if ($Auto) { 'авто' } else { 'вручную' })) -Encoding UTF8
  if (-not $Auto) { Write-Host 'Сейчас меняется энергосбережение сетевой карты. Жду, пока оно закончится, и начну подбор.' -ForegroundColor Yellow } }
if (-not $nk) { if (-not $Auto) { Write-Host 'Сеть занята слишком долго. Нажми «Подобрать обход» ещё раз позже.' -ForegroundColor Yellow; Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null }; PctUnlock $lk; return }
try {
Step -Plan 'Ищу программу обхода', 'Проверяю, нет ли VPN-туннеля', 'Смотрю, что открывается сейчас', 'Останавливаю обход и считаю без него', 'Пробую способы обхода', 'Включаю выбранный способ'
Step 'Ищу программу обхода'
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
  if ($Auto) { . (PctNotifyPath); Send-Notify $title $msg }
  else { PctUnlock $nk; PctUnlock $lk; Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null } }
if (-not $Auto) { $Host.UI.RawUI.WindowTitle = 'Подбор способа обхода блокировок — не закрывай окно'
  Write-Host "`nПОДБОР СПОСОБА ОБХОДА БЛОКИРОВОК`n" -ForegroundColor Cyan
  Write-Host 'Займёт до 10 минут. YouTube и Discord в это время могут прерываться.'; Write-Host "Окно не закрывай.`n" }
if (-not (Test-Path -LiteralPath $Z)) { Step -Fail 'папки zapret нет' -Do 'Нажми «Позвать помощь».'; Finish 'Обход блокировок' "Папка zapret не найдена. Нажми «Позвать помощь»." $false; return }
Step -Done 'нашёл'; Step 'Проверяю, нет ли VPN-туннеля'
if (Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -match 'Wintun|TAP|TUN|Happ|sing|xray' }) {
  Step -Fail 'включён VPN-туннель' -Do 'Выключи туннель (TUN) в Happ и запусти подбор ещё раз.'; Finish 'Обход блокировок' 'Сейчас включён VPN-туннель (TUN) — проверка будет неверной. Выключи его в Happ и запусти ещё раз.' $false; return }
Step -Done 'нет'; Step 'Смотрю, что открывается сейчас'
if (-not (Get-Process winws)) { Step -Unsafe; Say 'Обход был выключен — включаю...'; & "$Hd\start-zapret.ps1"; Start-Sleep 5 }
$now = Test-Sites; Say ("Сейчас открывается {0} из 6{1}" -f $now.Ok, $(if ($now.Miss) { " (нет: $($now.Miss))" }))
Step -Done "открывается $($now.Ok) из 6"
if ($now.Ok -eq 6) {
  if ($Auto) { Finish 'Обход блокировок' 'YouTube и Discord снова открываются — менять ничего не пришлось.' $true; return }
  Write-Host "`nВсё и так работает. Всё равно подобрать заново? Напиши д и Enter. Просто Enter — не надо." -ForegroundColor Cyan
  if ((Read-Host) -notmatch '^\s*[дДyY]') { Finish 'Обход блокировок' 'Всё работает, ничего не менял.' $true; return } }
Step -Unsafe; Step 'Останавливаю обход и считаю без него'
if (Test-Path $saved) { Copy-Item $saved "$saved.bak-$(Get-Date -f yyyyMMdd-HHmm)" -Force }
Stop-Z; $base = Test-Sites; Say "Без обхода: $($base.Ok) из 6"; Step -Done "без обхода $($base.Ok) из 6"
$bats = @(Get-ChildItem $Z -Filter '*.bat' | Where-Object Name -notmatch '^service'); $n = 0; $res = @()
Step "Пробую способы обхода (всего $($bats.Count))" -Hint 'Самый долгий шаг — до 10 минут'
foreach ($b in $bats) { $n++
  Say ("Проверяю способ {0} из {1}: {2}" -f $n, $bats.Count, $b.BaseName)
  if ($Auto) { PctBg 'sites-watch' "Пробую способы обхода (всего $($bats.Count))" -Hint "способ $n из $($bats.Count)" -N $script:bgN -Of $script:bgOf }
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
  Step -Done "выбран «$($best.Name)»"; Step 'Включаю выбранный способ'
  [IO.File]::WriteAllLines($saved, [string[]]@($best.Exe, (Norm $best.Cmd)), (New-Object Text.UTF8Encoding $true))
  & "$Hd\start-zapret.ps1"; Start-Sleep 5; $f = Test-Sites
  if ($f.Ok -eq 6) { Step -Done 'открывается 6 из 6' } else { Step -Warn "открывается $($f.Ok) из 6" }
  Finish $(if ($f.Ok -eq 6) { 'Обход блокировок починен' } else { 'Обход блокировок починен частично' }) ("Выбран способ «{0}»: открывается {1} из 6{2}. Он будет включаться сам." -f $best.Name, $f.Ok, $(if ($f.Miss) { " (нет: $($f.Miss))" })) ($f.Ok -eq 6)
} else { Step -Fail 'ни один способ не помог' -Do 'Нажми «Позвать помощь»: нужна новая версия zapret.'; & "$Hd\start-zapret.ps1"
  Finish 'Обход блокировок не починился' 'Ни один способ не помог — нужна новая версия zapret. Нажми «Позвать помощь».' $false }
} finally { PctUnlock $nk; PctUnlock $lk }