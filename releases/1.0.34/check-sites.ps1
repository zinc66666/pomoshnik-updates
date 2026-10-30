$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
$Host.UI.RawUI.WindowTitle = 'Проверка сайтов'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Host "`nПРОВЕРКА САЙТОВ (около 30 секунд)`n" -ForegroundColor Cyan
$sk = PctSocks; $z = [bool](Get-Process winws); $h = [bool](Get-Process happd, Happ)
Write-Host ('Обход блокировок (zapret): ' + $(if ($z) { 'работает' } else { 'ВЫКЛЮЧЕН' })) -ForegroundColor $(if ($z) { 'Green' } else { 'Red' })
Write-Host ('Программа Happ: ' + $(if ($h) { 'открыта (включён ли VPN — смотри в самой Happ)' } else { 'закрыта' }) + "`n")
$sites = [ordered]@{ 'Яндекс' = 'https://ya.ru'; 'ВКонтакте' = 'https://vk.com'; 'Google' = 'https://www.google.com'
  'YouTube' = 'https://www.youtube.com'; 'Discord' = 'https://discord.com'; 'Telegram (веб)' = 'https://web.telegram.org'
  'Instagram' = 'https://www.instagram.com'; 'X / Twitter' = 'https://x.com'; 'ChatGPT' = 'https://chatgpt.com' }
$bad = @()
foreach ($k in $sites.Keys) {
  $sw = [Diagnostics.Stopwatch]::StartNew(); $ok = $false
  try { $r = [Net.WebRequest]::Create($sites[$k]); $r.Timeout = 8000; $r.AllowAutoRedirect = $false; $r.UserAgent = 'Mozilla/5.0'; $resp = $r.GetResponse(); $resp.Close(); $ok = $true }
  catch { $e = $_.Exception; while ($e -and -not ($e -is [Net.WebException])) { $e = $e.InnerException }; if ($e -and $e.Response) { $ok = $true } }
  if ($ok) { Write-Host ("  {0,-16} открывается ({1} мс)" -f $k, $sw.ElapsedMilliseconds) -ForegroundColor Green }
  else { Write-Host ("  {0,-16} НЕ открывается" -f $k) -ForegroundColor Red; $bad += $k } }
$tgp = & curl.exe -s -o NUL -w '%{http_code}' --max-time 10 --socks5-hostname $sk https://web.telegram.org 2>$null
if ($tgp -and $tgp -ne '000') { Write-Host ('  {0,-16} работает через прокси Happ' -f 'Telegram (прил.)') -ForegroundColor Green } else { Write-Host ('  {0,-16} НЕТ: Happ не подключён' -f 'Telegram (прил.)') -ForegroundColor Red; Write-Host '  Открой Happ и нажми большую кнопку подключения (режим «Прокси»).' -ForegroundColor Yellow }
Write-Host ''
if ($bad -contains 'Яндекс' -and $bad -contains 'ВКонтакте') { Write-Host 'Не работает даже Яндекс — интернета нет. Нажми ярлык «2. Починить интернет».' -ForegroundColor Yellow }
elseif ($bad -contains 'YouTube' -or $bad -contains 'Discord') { Write-Host 'YouTube или Discord не открываются — нажми в Помощнике «Не работает YouTube или Discord».' -ForegroundColor Yellow }
if (@($bad | Where-Object { $_ -in 'Instagram','X / Twitter','ChatGPT','Telegram (веб)' }).Count) { Write-Host 'Instagram, X и Telegram-веб в России открываются только через VPN — включи Happ, когда они нужны.' -ForegroundColor Yellow }
if (-not $bad) { Write-Host 'Всё открывается.' -ForegroundColor Green }
$viaHapp = @($bad | Where-Object { $_ -notin 'Яндекс', 'ВКонтакте', 'Google', 'YouTube', 'Discord' })
if ($viaHapp -and (Get-NetTCPConnection -State Listen -LocalPort (PctSocksPort) -ErrorAction SilentlyContinue)) { Write-Host "`nПроверяю их через Happ:" -ForegroundColor Cyan
  foreach ($k in $viaHapp) { $r = & curl.exe -s -o NUL -w '%{http_code}' --max-time 10 --socks5-hostname $sk $sites[$k] 2>$null
    if ($r -and $r -ne '000') { Write-Host ("  {0,-16} открывается через Happ — в браузере откроется сам" -f $k) -ForegroundColor Green } else { Write-Host ("  {0,-16} не открывается и через Happ" -f $k) -ForegroundColor Red } } }
if (($bad -contains 'YouTube' -or $bad -contains 'Discord') -and -not ($bad -contains 'Яндекс' -and $bad -contains 'ВКонтакте')) {
  Write-Host "`nМогу сам подобрать новый способ обхода блокировок (до 10 минут)." -ForegroundColor Cyan
  Write-Host 'Подобрать сейчас? Напиши д и нажми Enter. Просто Enter — не надо.'
  if ((Read-Host) -match '^\s*[дДyY]') { Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$(PctDir 'helpers')\zapret-repick.ps1`""; return } }
Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null