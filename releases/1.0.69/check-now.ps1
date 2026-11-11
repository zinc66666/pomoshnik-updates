$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
# Сторож автозапуска: копия выпуска в helpers\ (задачи — на неё, U1b); старая установка — только guard\
$ga = "$(PctDir 'helpers')\guard-autoruns.ps1"; if (-not (Test-Path -LiteralPath $ga)) { $ga = "$(PctDir 'guard')\guard-autoruns.ps1" }
$Host.UI.RawUI.WindowTitle = 'Проверка безопасности'
function Ok($t) { Write-Host "  [OK]  $t" -ForegroundColor Green }
function Bad($t) { Write-Host "  [!!]  $t" -ForegroundColor Red }
function Info($t) { Write-Host "        $t" -ForegroundColor Gray }
function Warn($t) { Write-Host "  [..]  $t" -ForegroundColor Yellow }
Write-Host "`nПРОВЕРКА БЕЗОПАСНОСТИ  $(Get-Date -Format 'dd.MM.yyyy HH:mm')`n" -ForegroundColor Cyan
$av = Get-CimInstance -Namespace root/SecurityCenter2 AntiVirusProduct
$on = @($av | Where-Object { ($_.productState -band 0xF000) -eq 0x1000 })
if ($on.Count) { foreach ($a in $on) { if ($a.productState -band 0x10) { Bad "Антивирус $($a.displayName): базы УСТАРЕЛИ — обновите" } else { Ok "Антивирус работает: $($a.displayName)" } } } else { Bad 'Антивирус НЕ работает' }
# Запрос не прошёл (служба брандмауэра не отвечает) — не знаю, включён ли: не «включён»
$fw = $null; try { $fw = @(Get-NetFirewallProfile -ErrorAction Stop) } catch {}
if (-not $fw) { Warn 'Не удалось проверить брандмауэр: Windows не ответил. Открой «Безопасность Windows» → «Брандмауэр и защита сети».' }
elseif (@($fw | Where-Object { -not $_.Enabled }).Count) { Bad ('Брандмауэр выключен: ' + (($fw | Where-Object { -not $_.Enabled }).Name -join ', ')) } else { Ok 'Брандмауэр включён' }
if ((Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System').EnableLUA -eq 1) { Ok 'Контроль учётных записей (UAC) включён' } else { Bad 'UAC выключен' }
# Сторож автозапуска есть не у всех (ставится отдельно): нет его — не говорю «без изменений»
$r = if (Test-Path -LiteralPath $ga) { & $ga -Report }
if (-not $r) { Info 'Автозапуск не проверен: сторож автозапуска не установлен' } elseif ($r.New.Count) { Bad "Новое в автозапуске ($($r.New.Count)):"; $r.New | ForEach-Object { Info $_ } } else { Ok 'Автозапуск без изменений' }
if ($r.Gone.Count) { Info "Пропало из автозапуска: $($r.Gone.Count) (обычно это удалённые программы)" }
$p = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
if ($p.ProxyEnable -eq 1 -or $p.AutoConfigURL) { Bad "Включён прокси: $($p.ProxyServer) $($p.AutoConfigURL)  (если это не ваш VPN — опасно)" } else { Ok 'Прокси не подменён' }
$h = Get-Content "$env:windir\System32\drivers\etc\hosts" | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' }
if ($h) { Bad 'Файл hosts изменён:'; $h | ForEach-Object { Info $_ } } else { Ok 'Файл hosts чистый' }
$c2 = '176.12.71.122','69.197.153.74','69.30.238.130'
if (Get-NetTCPConnection | Where-Object { $c2 -contains $_.RemoteAddress }) { Bad 'ЕСТЬ связь с серверами старого стилера!' } else { Ok 'Связи с серверами старого стилера нет' }
$al = PctData 'alerts.log' 'guard'; if (Test-Path $al) { Write-Host "`n  Последние предупреждения:" -ForegroundColor Yellow; Get-Content $al -Encoding UTF8 -Tail 5 | ForEach-Object { Info $_ } }
# «(д/н)» — окно покажет кнопки Да/Нет («Да» отвечает «д»); «1» — для прямого запуска, как раньше
if ($r.New.Count) { Write-Host "`nВсе новые записи автозапуска — твои программы? Тогда я буду считать их нормой (д/н)." -ForegroundColor Yellow
  if ((Read-Host) -match '^\s*[дДyY1]') { & $ga -Rebaseline | ForEach-Object { Write-Host $_ } } }
else { Write-Host "`nНажмите Enter, чтобы закрыть." -ForegroundColor DarkGray; Read-Host | Out-Null }