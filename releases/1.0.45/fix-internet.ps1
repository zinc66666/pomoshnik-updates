$Host.UI.RawUI.WindowTitle = 'Починить интернет'
. "$PSScriptRoot\pct-core.ps1"
Write-Host "`nПОЧИНКА ИНТЕРНЕТА (без потери настроек)`n" -ForegroundColor Cyan
# Сеть — по одному (PctNetLock): подбор обхода в это время проверяет сайты, энергосбережение меняет сетевую карту. Занято — строка и ожидание до 15 минут
$nk = PctNetLock { Write-Host 'Сейчас сеть занята: подбирается обход блокировок или меняется энергосбережение. Жду, пока закончится.' -ForegroundColor Yellow }
if (-not $nk) { Write-Host 'Сеть занята слишком долго. Нажми «Интернет совсем не работает» ещё раз позже.' -ForegroundColor Yellow; Write-Host "`nНажми Enter, чтобы закрыть."; Read-Host | Out-Null; return }
try {
Write-Host '1) Очистка кэша DNS...'; Clear-DnsClientCache; ipconfig /flushdns | Out-Null
Write-Host '2) Обновление адреса от роутера...'; ipconfig /release | Out-Null; ipconfig /renew | Out-Null
Write-Host '3) Перезапуск Wi-Fi адаптера...'
$a = Get-NetAdapter | Where-Object { $_.InterfaceDescription -match 'Wi-Fi|Wireless|802\.11' } | Select-Object -First 1
if ($a) { Restart-NetAdapter -Name $a.Name -Confirm:$false; Start-Sleep 8 }
Write-Host '4) Проверка...'
$ok = Test-Connection ya.ru -Count 2 -Quiet
if ($ok) { Write-Host "`nИнтернет работает." -ForegroundColor Green } else { Write-Host "`nИнтернета нет. Перезагрузите роутер (выключить из розетки на 30 секунд)." -ForegroundColor Red }
New-Item -ItemType Directory -Force (PctDir 'reports') | Out-Null; Add-Content "$(PctDir 'reports')\fix-internet.log" ("{0:yyyy-MM-dd HH:mm} интернет после починки: {1}" -f (Get-Date), $(if ($ok) { 'работает' } else { 'НЕТ' })) -Encoding UTF8
} finally { PctUnlock $nk }
Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null