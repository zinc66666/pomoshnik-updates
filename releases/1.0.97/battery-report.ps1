$ErrorActionPreference = 'SilentlyContinue'
$Host.UI.RawUI.WindowTitle = 'Отчёт о батарее'
Write-Host "`nБАТАРЕЯ`n" -ForegroundColor Cyan
$b = Get-CimInstance Win32_Battery | Select-Object -First 1
if (-not $b) { Write-Host 'Батарея не найдена.' -ForegroundColor Red; Read-Host 'Enter — закрыть' | Out-Null; return }
$fc = (Get-CimInstance -Namespace root\wmi BatteryFullChargedCapacity | Select-Object -First 1).FullChargedCapacity
$dc = (Get-CimInstance -Namespace root\wmi BatteryStaticData | Select-Object -First 1).DesignedCapacity
$cy = (Get-CimInstance -Namespace root\wmi BatteryCycleCount | Select-Object -First 1).CycleCount
# От сети — статусы 2, 3, 6–9 (как PctEnDevice)
$ac = $b.BatteryStatus -in 2, 3, 6, 7, 8, 9
Write-Host ("  Заряд сейчас:          {0}%  ({1})" -f $b.EstimatedChargeRemaining, $(if ($ac) { 'подключена зарядка' } else { 'работает от батареи' }))
if (-not $ac -and $b.EstimatedRunTime -and $b.EstimatedRunTime -lt 6000) { Write-Host ("  Хватит примерно на:    {0} ч {1} мин" -f [math]::Floor($b.EstimatedRunTime/60), ($b.EstimatedRunTime % 60)) }
if ($fc) { Write-Host ("  Ёмкость сейчас:        {0:N1} Вт·ч" -f ($fc/1000)) }
# Нынешней ёмкости Windows не сообщает — износ не знаю (не 100 %)
if ($dc -and -not $fc) { Write-Host ("  Заводская ёмкость:     {0:N1} Вт·ч  -> износ: не знаю, Windows не сообщает нынешнюю ёмкость" -f ($dc/1000)) -ForegroundColor DarkGray }
elseif ($dc) { $w = 100 - $fc*100/$dc; Write-Host ("  Заводская ёмкость:     {0:N1} Вт·ч  -> износ {1:N0}%" -f ($dc/1000), $w) -ForegroundColor $(if ($w -ge 40) { 'Red' } elseif ($w -ge 20) { 'Yellow' } else { 'Green' }) }
else { Write-Host '  Заводская ёмкость:     Windows не сообщает (в этой сборке)' -ForegroundColor DarkGray }
if ($cy) { Write-Host ("  Циклов зарядки:        {0}" -f $cy) -ForegroundColor $(if ($cy -ge 800) { 'Yellow' } else { 'Green' }) }
Write-Host ''
if ($cy -ge 800) { Write-Host "Батарея прошла много циклов (обычно их рассчитывают на 500–1000). Если ноутбук мало`nдержит без зарядки — замените аккумулятор в сервисе." -ForegroundColor Yellow }
Write-Host 'Чтобы батарея жила дольше: не держи ноутбук всё время на 0% и не оставляй на жаре.'
Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null