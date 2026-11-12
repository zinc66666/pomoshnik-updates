# «Что тормозит сейчас»: 5 секунд наблюдения — кто грузит процессор, память, диск, и что с этим делать. Ничего не меняет.
$ErrorActionPreference = 'SilentlyContinue'
$Host.UI.RawUI.WindowTitle = 'Что тормозит сейчас'
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
Write-Host "`nЧТО ТОРМОЗИТ СЕЙЧАС`n" -ForegroundColor Cyan
Step -Safe
Step -Plan 'Проверяю зарядку', 'Смотрю 5 секунд, что грузит ноутбук', 'Готовлю советы'
Step 'Проверяю зарядку'
$bat = Get-CimInstance Win32_Battery | Select-Object -First 1; $onAC = (-not $bat) -or $bat.BatteryStatus -eq 2
Step -Done $(if ($onAC) { 'от зарядки' } else { "от батареи, $($bat.EstimatedChargeRemaining) %" })
Step 'Смотрю 5 секунд, что грузит ноутбук' -Hint 'Ничего не трогай'
Write-Host 'Смотрю 5 секунд — ничего не трогай...' -ForegroundColor DarkGray
$n = [Environment]::ProcessorCount
$p1 = @{}; Get-Process | ForEach-Object { $p1[$_.Id] = $_.TotalProcessorTime.TotalMilliseconds }
$cpu = @(); $dsk = @(); $frq = @()
for ($i = 0; $i -lt 5; $i++) { Start-Sleep 1
  $cpu += (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime
  $dsk += 100 - (Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'").PercentIdleTime
  $frq += (Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'").PercentofMaximumFrequency }
$top = Get-Process | ForEach-Object { if ($p1.ContainsKey($_.Id)) { [pscustomobject]@{ N = $_.ProcessName; C = ($_.TotalProcessorTime.TotalMilliseconds - $p1[$_.Id]) / 50 / $n; M = $_.WorkingSet64 } } } |
  Group-Object N | ForEach-Object { [pscustomobject]@{ N = $_.Name; C = ($_.Group | Measure-Object C -Sum).Sum; M = ($_.Group | Measure-Object M -Sum).Sum / 1MB; K = $_.Count } }
$os = Get-CimInstance Win32_OperatingSystem; $ram = [math]::Round(100 - 100 * $os.FreePhysicalMemory / $os.TotalVisibleMemorySize)
$c = [math]::Round(($cpu | Measure-Object -Average).Average); $d = [math]::Round(($dsk | Measure-Object -Average).Average); $f = [math]::Round(($frq | Measure-Object -Average).Average)
Step -Done "процессор $c %, память $ram %"
$names = @{ browser = 'Яндекс Браузер'; Discord = 'Discord'; Telegram = 'Telegram'; chrome = 'Chrome'; msedge = 'Edge'; explorer = 'Проводник'; svchost = 'службы Windows'; MsMpEng = 'антивирус'; TiWorker = 'установка обновлений Windows'; SearchIndexer = 'индексация поиска'; Happ = 'Happ'; AnyDesk = 'AnyDesk'; Steam = 'Steam'; steamwebhelper = 'Steam' }
function Nm($x) { if ($names.ContainsKey($x)) { "$($names[$x]) ($x)" } else { $x } }
Write-Host ''
Write-Host ("Процессор: {0}%   Память: {1}%   Диск: {2}%   Частота процессора: {3}% от максимума   {4}" -f $c, $ram, $d, $f, $(if ($onAC) { 'от зарядки' } else { 'от батареи' })) -ForegroundColor White
Write-Host "`nБольше всего грузят процессор:" -ForegroundColor Cyan
$top | Where-Object { $_.N -ne 'Idle' } | Sort-Object C -Descending | Select-Object -First 5 | ForEach-Object { Write-Host ("  {0,-40} {1,5:N1}%" -f (Nm $_.N), $_.C) }
Write-Host "`nБольше всего занимают памяти:" -ForegroundColor Cyan
$topM = $top | Sort-Object M -Descending | Select-Object -First 5
$topM | ForEach-Object { Write-Host ("  {0,-40} {1,6:N0} МБ" -f (Nm $_.N), $_.M) }
Step 'Готовлю советы'
Write-Host "`nЧТО ДЕЛАТЬ:" -ForegroundColor Yellow
$any = $false
$hog = $top | Where-Object { $_.N -notin 'Idle', 'System', 'powershell', 'WmiPrvSE' } | Sort-Object C -Descending | Select-Object -First 1
if ($hog.C -ge 25) { $any = $true; Write-Host ("  • Сильно грузит процессор: {0} ({1:N0}%). Если ты сейчас им не пользуешься — закрой его." -f (Nm $hog.N), $hog.C) }
if ($ram -ge 85) { $any = $true; Write-Host ("  • Память почти заполнена ({0}%). Больше всех занимает {1}. Закрой лишние вкладки браузера или программы." -f $ram, (Nm $topM[0].N)) }
if ($d -ge 80) { $any = $true; Write-Host '  • Диск сильно занят — идёт обновление, копирование или проверка. Подожди 5–10 минут.' }
if ($f -lt 60 -and $c -ge 30) { $any = $true; Write-Host '  • Процессор сбавил скорость: ноутбук греется или экономит батарею. Подключи зарядку и не ставь ноутбук на мягкое (одеяло, колени).' }
if ($bat -and -not $onAC -and $bat.EstimatedChargeRemaining -lt 20) { $any = $true; Write-Host '  • Батарея почти села — Windows замедляет ноутбук. Подключи зарядку.' }
if (-not $any) { Write-Host '  Сейчас ничего не тормозит. Если тормозит одна программа — закрой её и открой заново.' -ForegroundColor Green; Step -Done 'ничего не тормозит' } else { Step -Warn 'есть советы — в подробностях' }
Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null
