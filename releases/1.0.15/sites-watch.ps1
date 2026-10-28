$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
$Hd = PctDir 'helpers'; $logf = "$(PctDir 'reports')\sites-watch.log"; $st = "$Hd\sites-watch-last-fix.txt"
function Log($t) { Add-Content -LiteralPath $logf ("{0:yyyy-MM-dd HH:mm} {1}" -f (Get-Date), $t) -Encoding UTF8
  $all = Get-Content -LiteralPath $logf -Encoding UTF8; if ($all.Count -gt 400) { $all | Select-Object -Last 300 | Set-Content -LiteralPath $logf -Encoding UTF8 } }
function Up($u) { $r = & curl.exe -s -o NUL -w '%{http_code}' --max-time 8 $u 2>$null; [bool]($r -and $r -ne '000') }
function Broken { foreach ($x in @(@('YouTube', 'https://www.youtube.com'), @('YouTube-видео', 'https://redirector.googlevideo.com/report_mapping'), @('Discord', 'https://discord.com'), @('Discord-чат', 'https://gateway.discord.gg'))) { if (-not (Up $x[1])) { $x[0] } } }
if (Test-Path "$Hd\smart-proxy-on.txt") { & "$Hd\smart-proxy.ps1" -Apply }
if (-not ((Up 'https://ya.ru') -or (Up 'https://vk.com'))) { Log 'нет интернета — пропуск'; return }
if (Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -match 'Wintun|TAP|TUN|Happ|sing|xray' }) { Log 'включён VPN-туннель — пропуск'; return }
if (-not (Get-Process winws)) { & "$Hd\start-zapret.ps1"; Start-Sleep 6; Log 'zapret был выключен — запущен' }
$b = @(Broken); if (-not $b) { Log 'всё открывается'; return }
Log "не открываются: $($b -join ', ') — перепроверка через 90 с"; Start-Sleep 90
$b = @(Broken); if (-not $b) { Log 'был кратковременный сбой, всё открывается'; return }
$last = Get-Content -LiteralPath $st -TotalCount 1
if ($last -and ((Get-Date) - [datetime]$last).TotalHours -lt 6) {
  . "$(PctDir 'guard')\notify.ps1"; Send-Notify 'YouTube или Discord не открываются' 'Автоподбор уже был недавно и не помог. Открой «Помощник» на рабочем столе → «Позвать помощь».'
  Log "не открываются: $($b -join ', ') — автоподбор был < 6 ч назад, только уведомление"; return }
Set-Content -LiteralPath $st (Get-Date -Format s)
Log "не открываются: $($b -join ', ') — запускаю автоподбор"
. "$(PctDir 'guard')\notify.ps1"; Send-Notify 'Чиню обход блокировок' 'YouTube или Discord перестали открываться. Подбираю новый способ сам — до 10 минут.'
& "$Hd\zapret-repick.ps1" -Auto
Log ('автоподбор закончен, сейчас не открываются: ' + $(if ($r = @(Broken)) { $r -join ', ' } else { 'ничего' }))