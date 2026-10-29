$ErrorActionPreference = 'SilentlyContinue'
$Host.UI.RawUI.WindowTitle = 'Автозагрузка — всё'
try { $Host.UI.RawUI.BufferSize = New-Object Management.Automation.Host.Size(150, 3000); $Host.UI.RawUI.WindowSize = New-Object Management.Automation.Host.Size(150, 45) } catch {}
. "$PSScriptRoot\pct-core.ps1"
$J = "$(PctDir 'helpers')\startup-journal.csv"   # что отключали и как было — для возврата
# Нельзя отключать: планшет, тачпад, звук, видео, Wi-Fi, удалённая помощь, сторожа.
$Keep = 'XP-?Pen|PenTablet|TabletDriver|Wacom|Realtek|Rtk|Synaptics|ELAN|Precision|Intel|igfx|AMD|Radeon|NVIDIA|Honor|Huawei|AnyDesk|PCT-|Everything|winws|zapret|Happ'
function ExeOf($cmd) { if ($cmd -match '^\s*"([^"]+)"') { $m = $Matches[1] } elseif ($cmd -match '^\s*(.+?\.(exe|cmd|bat|vbs|ps1))(\s|$)') { $m = $Matches[1] } else { $m = ($cmd -split ' ')[0] }; FindExe ([Environment]::ExpandEnvironmentVariables($m)) }
# Команда без папки (conhost.exe, rundll32) — ищу, как Windows: System32, Windows, затем PATH; последним — SysWOW64. Не нашёл — имя как есть
function FindExe($m) { if (-not $m -or $m -match '[\\/]') { return $m }; $ns = @($m); if ($m -notmatch '\.\w{2,4}$') { $ns = "$m.exe", $m }
  foreach ($d in @("$env:windir\System32", $env:windir) + @($env:PATH -split ';') + "$env:windir\SysWOW64") { foreach ($n in $ns) { $p = "$("$d".Trim().TrimEnd('\'))\$n"; if ($d -and [IO.File]::Exists($p)) { return $p } } }; $m }
$PubCache = @{}
function Pub($f) { if ($PubCache.ContainsKey("$f")) { return $PubCache["$f"] }; $r = PubRaw $f; $PubCache["$f"] = $r; $r }
function PubRaw($f) { if ($f -and $f -notmatch '[\\/]') { 'не нашёл по имени' } elseif ($f -and (Test-Path -LiteralPath $f)) { $s = Get-AuthenticodeSignature -LiteralPath $f; if ($s.Status -eq 'Valid') { ($s.SignerCertificate.Subject -replace '^CN="?([^",]+).*$', '$1') } else { 'БЕЗ ПОДПИСИ' } } elseif ($f) { 'файл не найден' } else { '' } }
$approved = @{ 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32' }
$folders = @{ "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup" = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
  "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp" = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' }
function Collect {
  $L = New-Object Collections.Generic.List[object]
  # Все значения ключа: фильтр «^PS» по свойствам Get-ItemProperty прятал и записи с именем на «PS»
  foreach ($k in $approved.Keys) { $p = Get-Item -LiteralPath $k; foreach ($vn in @(if ($p) { $p.GetValueNames() })) { $id = $(if ($vn) { $vn } else { '(default)' })
    $b = (Get-ItemProperty $approved[$k]).($id); $on = -not ($b -and ($b[0] -band 1))
    $f = ExeOf "$($p.GetValue($vn))"; $L.Add([pscustomobject]@{ Kind = 'Реестр'; Name = $id; On = $on; File = $f; Pub = (Pub $f); Key = $approved[$k]; Id = $id }) } }
  foreach ($d in $folders.Keys) { Get-ChildItem -LiteralPath $d -File | Where-Object Name -ne 'desktop.ini' | ForEach-Object {
    $b = (Get-ItemProperty $folders[$d]).($_.Name); $on = -not ($b -and ($b[0] -band 1)); $f = $_.FullName
    if ($_.Extension -eq '.lnk') { $f = (New-Object -ComObject WScript.Shell).CreateShortcut($_.FullName).TargetPath }
    $L.Add([pscustomobject]@{ Kind = 'Папка'; Name = $_.BaseName; On = $on; File = $f; Pub = (Pub $f); Key = $folders[$d]; Id = $_.Name }) } }
  # Задачи отключённых учётных записей (например, WsiAccount) никогда не запускаются, а менять их Windows не даёт — не показываем.
  $dead = @(Get-CimInstance Win32_UserAccount -Filter 'LocalAccount=True AND Disabled=True' | ForEach-Object Name)
  Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' -and $dead -notcontains $_.Principal.UserId } | ForEach-Object {
    $f = ExeOf "$($_.Actions[0].Execute)"; $L.Add([pscustomobject]@{ Kind = 'Задача'; Name = $_.TaskName; On = ($_.State -ne 'Disabled'); File = $f; Pub = (Pub $f); Key = $_.TaskPath; Id = $_.TaskName }) }
  # Журнала ещё нет (ничего не отключали) — отключённых мной служб нет
  $off = @($(if (Test-Path -LiteralPath $J) { Import-Csv $J -Delimiter ';' -Encoding UTF8 }) | Where-Object { $_.'Тип' -eq 'Служба' } | ForEach-Object { $_.'Имя' })
  Get-CimInstance Win32_Service | Where-Object { ($_.StartMode -eq 'Auto' -or $off -contains $_.Name) } | Where-Object { $_.PathName -and $_.PathName -notmatch '\\Windows\\(System32|SysWOW64)\\(svchost|lsass|services|spoolsv|SearchIndexer|dllhost|wbem)' } | ForEach-Object {
    $f = ExeOf $_.PathName; $pb = Pub $f
    if ($pb -notmatch '^Microsoft') { $L.Add([pscustomobject]@{ Kind = 'Служба'; Name = $_.DisplayName; On = ($_.StartMode -eq 'Auto'); File = $f; Pub = $pb; Key = $_.StartMode; Id = $_.Name }) } }
  $L | Sort-Object Kind, Name }
function Jot($it, $act) { if (-not (Test-Path $J)) { 'Время;Действие;Тип;Имя;Было' | Set-Content $J -Encoding UTF8 }; "{0:yyyy-MM-dd HH:mm};{1};{2};{3};{4}" -f (Get-Date), $act, $it.Kind, $it.Id, $it.Key | Add-Content $J -Encoding UTF8 }
function Toggle($it) {
  $to = -not $it.On
  switch ($it.Kind) {
    { $_ -in 'Реестр', 'Папка' } { if (-not (Test-Path $it.Key)) { New-Item $it.Key -Force | Out-Null }
      $v = [byte[]](0,0,0,0,0,0,0,0,0,0,0,0); $v[0] = $(if ($to) { 2 } else { 3 }); Set-ItemProperty -Path $it.Key -Name $it.Id -Value $v -Type Binary }
    'Задача' { if ($to) { Enable-ScheduledTask -TaskPath $it.Key -TaskName $it.Id | Out-Null } else { Disable-ScheduledTask -TaskPath $it.Key -TaskName $it.Id | Out-Null } }
    'Служба' { Set-Service -Name $it.Id -StartupType $(if ($to) { 'Automatic' } else { 'Manual' }) } }
  $now = switch ($it.Kind) {
    { $_ -in 'Реестр', 'Папка' } { $b = (Get-ItemProperty $it.Key).($it.Id); -not ($b -and ($b[0] -band 1)) }
    'Задача' { (Get-ScheduledTask -TaskPath $it.Key -TaskName $it.Id).State -ne 'Disabled' }
    'Служба' { (Get-CimInstance Win32_Service -Filter "Name='$($it.Id)'").StartMode -eq 'Auto' } }
  if ($now -eq $to) { Jot $it $(if ($to) { 'вкл' } else { 'выкл' }); $true } else { $false } }
function Say($n, $it, $ok) { if ($ok) { Write-Host ("  {0}{1} — {2}" -f $n, $it.Name, $(if ($it.On) { 'выключено' } else { 'включено' })) -ForegroundColor Green }
  else { Write-Host ("  {0}{1} — НЕ получилось: Windows не дала доступ. Ничего не изменено." -f $n, $it.Name) -ForegroundColor Red } }

# Совет по пункту: 2 — рекомендую отключить, 1 — можно отключить, 0 — оставить.
function Advice($it) {
  $s = "$($it.Name) $($it.File) $($it.Pub)"
  if ($s -match $Keep) { return 0, 'нужно для ноутбука — не трогать' }
  if ($s -match 'Windhawk') { return 0, 'оформление Windows этой сборки' }
  if ($it.Pub -eq 'не нашёл по имени') { return 0, 'не нашёл файл по имени — не знаю, что это' }
  if ($it.Pub -eq 'файл не найден') { return 2, 'программы уже нет — запись лишняя' }
  if ($s -match 'SoftLanding|GameModeX|booster|Driver ?Booster|iTop|Nahimic|Overwolf|Mail\.ru|Amigo|Avast|AVG|CCleaner|IObit|SystemCare|Wise ?Care|McAfee|Baidu|360 ?Total|Razer ?Cortex') { return 2, 'реклама или лишний «ускоритель»' }
  if ($it.Pub -eq 'БЕЗ ПОДПИСИ') { return 1, 'без подписи: не знаешь, что это, — отключи' }
  if ($s -match 'Update|Updater|Обновлен|обновлен|сервиса обновлений') { return 1, 'обновления: обновится, когда откроешь программу' }
  if ($s -match 'Steam|Discord|Telegram|uTorrent|qBittorrent|Epic|EA ?app|Origin|Battle\.net|Spotify|Музык|Music|OneDrive|Skype|Zoom|Viber|WhatsApp|Teams|Ubisoft|GOG|Riot|Opera|Chrome|Yandex|Яндекс|Browser') { return 1, 'откроешь сама, когда понадобится' }
  return 0, 'оставить, если не знаешь, что это' }

while ($true) {
  Clear-Host
  Write-Host "АВТОЗАГРУЗКА — ВСЁ, что запускается само (кроме частей самой Windows)`n" -ForegroundColor Cyan
  $items = @(Collect); $i = 0; $rec = @()
  foreach ($it in $items) { $i++; $adv = Advice $it
    $nm = $(if ($it.Name.Length -gt 34) { $it.Name.Substring(0, 33) + '…' } else { $it.Name })
    $pb = $(if ($it.Pub.Length -gt 24) { $it.Pub.Substring(0, 23) + '…' } else { $it.Pub })
    $tip = $(if (-not $it.On) { 'отключено' } elseif ($adv[0] -eq 2) { 'РЕКОМЕНДУЮ ОТКЛЮЧИТЬ: ' + $adv[1] } elseif ($adv[0] -eq 1) { 'можно отключить: ' + $adv[1] } else { 'оставить: ' + $adv[1] })
    if ($it.On -and $adv[0] -eq 2) { $rec += $it }
    $c = $(if (-not $it.On) { 'DarkGray' } elseif ($adv[0] -eq 2) { 'Yellow' } elseif ($adv[0] -eq 1) { 'White' } else { 'DarkGray' })
    Write-Host ("{0,3}. [{1}] {2,-6} {3,-34} {4,-24} {5}" -f $i, $(if ($it.On) { 'ВКЛ ' } else { 'выкл' }), $it.Kind, $nm, $pb, $tip) -ForegroundColor $c }
  Write-Host "`nВКЛ — запускается сама. Отключённая «Служба» не ломается: она стартует, когда программа её позовёт."
  Write-Host 'Жёлтым — рекомендую отключить. Белым — можно, если не нужно в фоне. Серым — оставить.' -ForegroundColor Yellow
  Write-Host "`nНомер (или несколько через пробел) — ВКЛЮЧИТЬ/ВЫКЛЮЧИТЬ." -ForegroundColor Green
  if ($rec) { Write-Host "Буква р — отключить всё, что рекомендую ($($rec.Count) шт.)." -ForegroundColor Green }
  Write-Host 'Просто Enter — выйти.' -ForegroundColor Green
  $a = Read-Host '>'
  if (-not $a.Trim()) { break }
  if ($a.Trim() -match '^[рРpP]$') { foreach ($it in $rec) { Say '' $it (Toggle $it) }; Start-Sleep 3; continue }
  foreach ($n in ($a -split '[ ,;]+' | Where-Object { $_ -match '^\d+$' })) {
    # «0» — не пункт: $items[-1] был бы последним
    $it = $(if ([int]$n -ge 1) { $items[[int]$n - 1] }); if (-not $it) { continue }
    if (($it.Name + ' ' + $it.File + ' ' + $it.Pub) -match $Keep) { Write-Host "  $n. $($it.Name) — это нужно для ноутбука, не трогаю." -ForegroundColor Yellow; Start-Sleep 2; continue }
    Say "$n. " $it (Toggle $it) }
  Start-Sleep 3 }
Write-Host "`nИзменения вступят в силу после перезагрузки. Журнал: $J"; Start-Sleep 3