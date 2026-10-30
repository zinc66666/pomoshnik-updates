# «Сайт не открывается»: проверяет сайт напрямую и через Happ; если помогает Happ — добавляет сайт в обход браузера.
$ErrorActionPreference = 'SilentlyContinue'
$Host.UI.RawUI.WindowTitle = 'Сайт не открывается'
. "$PSScriptRoot\pct-core.ps1"
$Hd = PctDir 'helpers'
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
function Code($u, $socks) { $a = @('-s', '-o', 'NUL', '-w', '%{http_code}', '--max-time', '12', '-A', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130 Safari/537.36')
  if ($socks) { $a += @('--socks5-hostname', (PctSocks)) }; $r = & curl.exe @a $u 2>$null; if (-not $r) { '000' } else { $r } }
Write-Host "`nСАЙТ НЕ ОТКРЫВАЕТСЯ`n" -ForegroundColor Cyan
Step -Safe
Step -Plan 'Жду адрес сайта', 'Проверяю интернет', 'Проверяю сайт напрямую и через Happ'
Step 'Жду адрес сайта' -Hint 'Напиши его ниже'
Write-Host 'Напиши адрес сайта (например: instagram.com) и нажми Enter.'
Write-Host 'Можно вставить ссылку из браузера: Ctrl+V.' -ForegroundColor DarkGray
$in = (Read-Host 'Сайт').Trim().ToLower()
$h = ($in -replace '^[a-z]+://', '' -replace '[/:?#].*$', '' -replace '^www\.', '')
if ($h -notmatch '^[a-z0-9.-]+\.[a-z]{2,}$') { Step -Fail 'не похоже на адрес сайта' -Do 'Нажми «Ещё раз» и напиши адрес, например instagram.com.'; Write-Host "`nНе похоже на адрес сайта. Пример: instagram.com" -ForegroundColor Yellow; Read-Host "`nEnter — закрыть" | Out-Null; return }
Step -Done $h; $u = "https://$h"; Write-Host "`nПроверяю $h ..."
Step 'Проверяю интернет'
$ya = Code 'https://ya.ru' $false
if ($ya -eq '000') { Step -Fail 'интернета нет' -Do 'Нажми «Интернет совсем не работает».'; Write-Host 'Интернета нет совсем. В Помощнике нажми «Интернет совсем не работает».' -ForegroundColor Red; Read-Host "`nEnter — закрыть" | Out-Null; return }
Step -Done 'есть'; Step "Проверяю $h напрямую и через Happ" -Hint 'До 25 секунд'
$d = Code $u $false; $happ = [bool](Get-NetTCPConnection -State Listen -LocalPort (PctSocksPort)); $p = if ($happ) { Code $u $true } else { '000' }
Write-Host ("  напрямую: {0}" -f $(if ($d -eq '000') { 'НЕ открывается' } elseif ($d -in '403', '451') { "сайт не пускает из России (код $d)" } else { 'открывается' }))
Write-Host ("  через Happ: {0}" -f $(if (-not $happ) { 'Happ не подключён' } elseif ($p -eq '000') { 'НЕ открывается' } elseif ($p -in '403', '451') { "не пускает (код $p)" } else { 'открывается' }))
$okD = $d -ne '000' -and $d -notin '403', '451'; $okP = $p -ne '000' -and $p -notin '403', '451'
if ($okD) { Step -Done 'открывается напрямую' } elseif ($okP) { Step -Done 'открывается через Happ' } elseif (-not $happ) { Step -Warn 'Happ не подключён' } else { Step -Warn 'не открывается' }
$ls = PctData 'proxy-sites.txt' 'helpers'; $inList = [bool](Get-Content -LiteralPath $ls -Encoding UTF8 | Where-Object { $_.Trim().ToLower() -eq $h -or $h.EndsWith('.' + $_.Trim().ToLower()) })
if ($okD) { Write-Host "`nСайт открывается напрямую — блокировки нет. В браузере нажми Ctrl+F5 (обновить страницу полностью)." -ForegroundColor Green
  Write-Host 'Если всё равно не грузится — закрой и открой браузер.' }
elseif ($okP) {
  Step -Unsafe; Step 'Включаю обход для этого сайта'
  if (-not $inList) { Add-Content -LiteralPath $ls $h -Encoding UTF8 }
  & "$Hd\smart-proxy.ps1" -On; Step -Done 'включён'
  Write-Host "`nГотово: $h теперь открывается в браузере через Happ сам." -ForegroundColor Green
  Write-Host 'Обнови страницу в браузере (Ctrl+F5). Если вкладка была открыта давно — закрой и открой её заново.' }
elseif (-not $happ) { Write-Host "`nHapp не подключён. Открой Happ, нажми большую кнопку подключения и запусти эту проверку ещё раз." -ForegroundColor Yellow }
else { Write-Host "`nСайт не открывается и через VPN. Скорее всего, он сейчас не работает сам или не пускает пользователей из России." -ForegroundColor Yellow }
Read-Host "`nEnter — закрыть" | Out-Null