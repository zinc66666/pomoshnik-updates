$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
# Сторож автозапуска: копия выпуска в helpers\ (задачи — на неё, U1b); старая установка — только guard\
$ga = "$(PctDir 'helpers')\guard-autoruns.ps1"; if (-not (Test-Path -LiteralPath $ga)) { $ga = "$(PctDir 'guard')\guard-autoruns.ps1" }
$Host.UI.RawUI.WindowTitle = 'Проверка безопасности'
function Ok($t) { Write-Host "  [OK]  $t" -ForegroundColor Green }
function Bad($t) { Write-Host "  [!!]  $t" -ForegroundColor Red }
function Info($t) { Write-Host "        $t" -ForegroundColor Gray }
function Warn($t) { Write-Host "  [..]  $t" -ForegroundColor Yellow }
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
Step -Safe
Step -Plan 'Проверяю антивирус', 'Проверяю брандмауэр', 'Проверяю контроль учётных записей', 'Проверяю автозапуск', 'Проверяю прокси и файл hosts', 'Ищу подозрительные соединения'
Write-Host "`nПРОВЕРКА БЕЗОПАСНОСТИ  $(Get-Date -Format 'dd.MM.yyyy HH:mm')`n" -ForegroundColor Cyan
Step 'Проверяю антивирус'
$av = Get-CimInstance -Namespace root/SecurityCenter2 AntiVirusProduct
$on = @($av | Where-Object { ($_.productState -band 0xF000) -eq 0x1000 })
$avOld = 0; if ($on.Count) { foreach ($a in $on) { if ($a.productState -band 0x10) { $avOld++; Bad "Антивирус $($a.displayName): базы УСТАРЕЛИ — обнови" } else { Ok "Антивирус работает: $($a.displayName)" } } } else { Bad 'Антивирус НЕ работает' }
if (-not $on.Count) { Step -Fail 'антивирус не работает' -Do 'Открой «Безопасность Windows» и включи защиту' } elseif ($avOld) { Step -Warn 'базы антивируса устарели' } else { Step -Done 'работает' }
Step 'Проверяю брандмауэр'
# Запрос не прошёл (служба брандмауэра не отвечает) — не знаю, включён ли: не «включён»
$fw = $null; try { $fw = @(Get-NetFirewallProfile -ErrorAction Stop) } catch {}
if (-not $fw) { Warn 'Не удалось проверить брандмауэр: Windows не ответил. Открой «Безопасность Windows» → «Брандмауэр и защита сети».'; Step -Warn 'не удалось проверить' }
elseif (@($fw | Where-Object { -not $_.Enabled }).Count) { Bad ('Брандмауэр выключен: ' + (($fw | Where-Object { -not $_.Enabled }).Name -join ', ')); Step -Fail 'брандмауэр выключен' -Do 'Открой «Безопасность Windows» → «Брандмауэр и защита сети» и включи его' } else { Ok 'Брандмауэр включён'; Step -Done 'включён' }
Step 'Проверяю контроль учётных записей'
if ((Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System').EnableLUA -eq 1) { Ok 'Контроль учётных записей (UAC) включён'; Step -Done 'включён' } else { Bad 'UAC выключен'; Step -Fail 'выключен' -Do 'Включи контроль учётных записей в настройках Windows' }
Step 'Проверяю автозапуск'
# Сторож автозапуска есть не у всех (ставится отдельно): нет его — не говорю «без изменений»
$r = if (Test-Path -LiteralPath $ga) { & $ga -Report }
if (-not $r) { Info 'Автозапуск не проверен: сторож автозапуска не установлен'; $fin = { Step -Warn 'не проверен: нет сторожа автозапуска' } } elseif ($r.New.Count) { Bad "Новое в автозапуске ($($r.New.Count)):"; $r.New | ForEach-Object { Info $_ }; $fin = { Step -Fail "новое в автозапуске: $($r.New.Count)" -Do 'Посмотри список ниже' } } else { Ok 'Автозапуск без изменений'; $fin = { Step -Done 'без изменений' } }
if ($r.Gone.Count) { Info "Пропало из автозапуска: $($r.Gone.Count) (обычно это удалённые программы)" }
& $fin
Step 'Проверяю прокси и файл hosts'
$p = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
if ($p.ProxyEnable -eq 1 -or $p.AutoConfigURL) { Bad "Включён прокси: $($p.ProxyServer) $($p.AutoConfigURL)  (если это не твой VPN — опасно)" } else { Ok 'Прокси не подменён' }
$h = Get-Content "$env:windir\System32\drivers\etc\hosts" | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' }
if ($h) { Bad 'Файл hosts изменён:'; $h | ForEach-Object { Info $_ } } else { Ok 'Файл hosts чистый' }
$px = [bool]($p.ProxyEnable -eq 1 -or $p.AutoConfigURL)
if ($px -and $h) { Step -Fail 'включён прокси, файл hosts изменён' -Do 'Если это не твой VPN — позови помощь' } elseif ($px) { Step -Fail 'включён прокси' -Do 'Если это не твой VPN — позови помощь' } elseif ($h) { Step -Fail 'файл hosts изменён' -Do 'Позови помощь' } else { Step -Done 'прокси и hosts в порядке' }
Step 'Ищу подозрительные соединения'
$c2 = '176.12.71.122','69.197.153.74','69.30.238.130'
if (Get-NetTCPConnection | Where-Object { $c2 -contains $_.RemoteAddress }) { Bad 'ЕСТЬ связь с серверами старого стилера!'; Step -Fail 'есть связь с серверами старого стилера' -Do 'Сразу позови помощь' } else { Ok 'Связи с серверами старого стилера нет'; Step -Done 'подозрительных нет' }
$al = PctData 'alerts.log' 'guard'; if (Test-Path $al) { Write-Host "`n  Последние предупреждения:" -ForegroundColor Yellow; Get-Content $al -Encoding UTF8 -Tail 5 | ForEach-Object { Info $_ } }
# «(д/н)» — окно покажет кнопки Да/Нет («Да» отвечает «д»); «1» — для прямого запуска, как раньше
# Окно берёт в карточку вопроса две последние строки журнала: вопрос — ровно две строки, без служебных строк перед ним
if ($r.New.Count) { Write-Host "`nВсе новые записи автозапуска — твои программы?" -ForegroundColor Yellow; Write-Host 'Тогда я буду считать их нормой (д/н).' -ForegroundColor Yellow
  if ((Read-Host) -match '^\s*[дДyY1]') { & $ga -Rebaseline | ForEach-Object { Write-Host $_ } } }
else { Write-Host "`nНажми Enter, чтобы закрыть." -ForegroundColor DarkGray; Read-Host | Out-Null }