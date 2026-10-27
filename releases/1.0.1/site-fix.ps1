# «Сайт не открывается»: проверяет сайт напрямую и через Happ; если помогает Happ — добавляет сайт в обход браузера.
$ErrorActionPreference = 'SilentlyContinue'
$Host.UI.RawUI.WindowTitle = 'Сайт не открывается'
$Hd = 'C:\PC-Tweaks-Laptop\helpers'
function Code($u, $socks) { $a = @('-s', '-o', 'NUL', '-w', '%{http_code}', '--max-time', '12', '-A', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130 Safari/537.36')
  if ($socks) { $a += @('--socks5-hostname', '127.0.0.1:10808') }; $r = & curl.exe @a $u 2>$null; if (-not $r) { '000' } else { $r } }
Write-Host "`nСАЙТ НЕ ОТКРЫВАЕТСЯ`n" -ForegroundColor Cyan
Write-Host 'Напиши адрес сайта (например: instagram.com) и нажми Enter.'
Write-Host 'Можно вставить ссылку из браузера: Ctrl+V.' -ForegroundColor DarkGray
$in = (Read-Host 'Сайт').Trim().ToLower()
$h = ($in -replace '^[a-z]+://', '' -replace '[/:?#].*$', '' -replace '^www\.', '')
if ($h -notmatch '^[a-z0-9.-]+\.[a-z]{2,}$') { Write-Host "`nНе похоже на адрес сайта. Пример: instagram.com" -ForegroundColor Yellow; Read-Host "`nEnter — закрыть" | Out-Null; return }
$u = "https://$h"; Write-Host "`nПроверяю $h ..."
$ya = Code 'https://ya.ru' $false
if ($ya -eq '000') { Write-Host 'Интернета нет совсем. В Помощнике нажми «Интернет совсем не работает».' -ForegroundColor Red; Read-Host "`nEnter — закрыть" | Out-Null; return }
$d = Code $u $false; $happ = [bool](Get-NetTCPConnection -State Listen -LocalPort 10808); $p = if ($happ) { Code $u $true } else { '000' }
Write-Host ("  напрямую: {0}" -f $(if ($d -eq '000') { 'НЕ открывается' } elseif ($d -in '403', '451') { "сайт не пускает из России (код $d)" } else { 'открывается' }))
Write-Host ("  через Happ: {0}" -f $(if (-not $happ) { 'Happ не подключён' } elseif ($p -eq '000') { 'НЕ открывается' } elseif ($p -in '403', '451') { "не пускает (код $p)" } else { 'открывается' }))
$okD = $d -ne '000' -and $d -notin '403', '451'; $okP = $p -ne '000' -and $p -notin '403', '451'
$inList = [bool](Get-Content "$Hd\proxy-sites.txt" -Encoding UTF8 | Where-Object { $_.Trim().ToLower() -eq $h -or $h.EndsWith('.' + $_.Trim().ToLower()) })
if ($okD) { Write-Host "`nСайт открывается напрямую — блокировки нет. В браузере нажми Ctrl+F5 (обновить страницу полностью)." -ForegroundColor Green
  Write-Host 'Если всё равно не грузится — закрой и открой браузер.' }
elseif ($okP) {
  if (-not $inList) { Add-Content -LiteralPath "$Hd\proxy-sites.txt" $h -Encoding UTF8 }
  & "$Hd\smart-proxy.ps1" -On
  Write-Host "`nГотово: $h теперь открывается в браузере через Happ сам." -ForegroundColor Green
  Write-Host 'Обнови страницу в браузере (Ctrl+F5). Если вкладка была открыта давно — закрой и открой её заново.' }
elseif (-not $happ) { Write-Host "`nHapp не подключён. Открой Happ, нажми большую кнопку подключения и запусти эту проверку ещё раз." -ForegroundColor Yellow }
else { Write-Host "`nСайт не открывается и через VPN. Скорее всего, он сейчас не работает сам или не пускает пользователей из России." -ForegroundColor Yellow }
Read-Host "`nEnter — закрыть" | Out-Null