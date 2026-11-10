# Включить, выключить или поставить фоновую задачу-сторожа (вызывается из Помощника, вкладка «Сторожа»). Пишет журнал.
# Задачи нет, а она из $Defs — создаю (GUARDS-INSTALL): скрипт только из helpers установки (пишут только администраторы, U1b), задача — от вошедшего человека (-Sid из окна).
# Код выхода: 0 — готово, 2 — задачи нет и создавать её не умею, 3 — нет файла скрипта, 4 — Планировщик не принял задачу. PCT_TASKS_FAKE=<папка> — стенд: задачи — файлы task-<имя>.xml, Планировщик не трогается
param([string]$Task, [switch]$On, [string]$Sid)
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
$Fake = $env:PCT_TASKS_FAKE
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $Fake) { if (-not $Sid) { $Sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }; $ps = "$([Environment]::GetFolderPath('System'))\WindowsPowerShell\v1.0\powershell.exe"
  $p = Start-Process $ps -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Task `"$Task`" -Sid `"$Sid`"" + $(if ($On) { ' -On' } else { '' })); if ($p) { exit $p.ExitCode }; return }
New-Item -ItemType Directory -Force (PctDir 'reports') | Out-Null
function Log($s) { Add-Content "$(PctDir 'reports')\guards.log" ("{0:yyyy-MM-dd HH:mm} {1}" -f (Get-Date), $s) -Encoding UTF8 }
# Задачи, которые умею создать (образцы — задачи ноутбука 29.10): скрипт, аргументы, наивысшие права (H), предел работы, триггеры
$Defs = @{
  'PCT-Zapret'          = @{ F = 'start-zapret.ps1'; H = 1; Lim = 'PT2M'; Tr = @('logon PT15S') }
  'PCT-Sites-Watch'     = @{ F = 'sites-watch.ps1'; H = 1; Lim = 'PT25M'; Tr = @('logon PT4M', 'daily 10:00 PT3H PT12H') }
  'PCT-Happ-Connect'    = @{ F = 'happ-connect.ps1'; H = 0; Lim = 'PT5M'; Tr = @('logon PT20S') }
  'PCT-Guard-Autoruns'  = @{ F = 'guard-autoruns.ps1'; H = 0; Lim = 'PT10M'; Tr = @('logon PT10M', 'daily 14:00') }
  'PCT-Guard-Downloads' = @{ F = 'guard-downloads.ps1'; H = 0; Lim = 'PT10M'; Tr = @('every PT15M') }
  'PCT-Clean-Temp'      = @{ F = 'clean-temp.ps1'; H = 1; Lim = 'PT10M'; Tr = @('weekly 12:00') }
  'PCT-Health-Weekly'   = @{ F = 'system-health.ps1'; A = ' -Quiet'; H = 1; Lim = 'PT10M'; Tr = @('weekly 18:00') } }
# Вошедший человек: SID из окна → тот, кто за экраном → тот, кто запустил
function UserSid { if ($Sid -match '^S-1-5-21-\d+-\d+-\d+-\d+$') { return $Sid }
  try { $n = "$((Get-CimInstance Win32_ComputerSystem).UserName)"; if ($n) { return (New-Object Security.Principal.NTAccount $n).Translate([Security.Principal.SecurityIdentifier]).Value } } catch { $null = $_ }
  [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
# Задача: Администраторы и SYSTEM — полный доступ, человек — чтение и запуск (как задача по кнопке в установщике, U1b). PowerShell и conhost — полным путём
function Sddl($sid) { "D:P(A;;FA;;;BA)(A;;FA;;;SY)(A;;FRFX;;;$sid)" }
function TaskDoc($n, $d, $sid) { $e = { param($s) [Security.SecurityElement]::Escape("$s") }; $win = [Environment]::GetFolderPath('Windows'); $day = Get-Date -Format 'yyyy-MM-dd'
  $acc = (New-Object Security.Principal.SecurityIdentifier $sid).Translate([Security.Principal.NTAccount]).Value
  $tr = foreach ($t in $d.Tr) { $a = $t -split ' '; switch ($a[0]) {
      'logon' { "<LogonTrigger><Delay>$($a[1])</Delay><UserId>$(& $e $acc)</UserId></LogonTrigger>" }
      'daily' { "<CalendarTrigger>$(if ($a.Count -gt 2) { "<Repetition><Interval>$($a[2])</Interval><Duration>$($a[3])</Duration><StopAtDurationEnd>false</StopAtDurationEnd></Repetition>" })<StartBoundary>${day}T$($a[1]):00</StartBoundary><ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay></CalendarTrigger>" }
      'weekly' { "<CalendarTrigger><StartBoundary>${day}T$($a[1]):00</StartBoundary><ScheduleByWeek><DaysOfWeek><Sunday /></DaysOfWeek><WeeksInterval>1</WeeksInterval></ScheduleByWeek></CalendarTrigger>" }
      'every' { "<TimeTrigger><Repetition><Interval>$($a[1])</Interval><StopAtDurationEnd>false</StopAtDurationEnd></Repetition><StartBoundary>$((Get-Date).AddMinutes(1).ToString('yyyy-MM-ddTHH:mm:ss'))</StartBoundary></TimeTrigger>" } } }
  $swa = @($d.Tr | Where-Object { $_ -notlike 'logon *' }).Count -gt 0
  $ar = "--headless $win\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$(PctDir 'helpers')\$($d.F)`"$($d.A)"
  "<?xml version=`"1.0`" encoding=`"UTF-16`"?><Task version=`"1.3`" xmlns=`"http://schemas.microsoft.com/windows/2004/02/mit/task`"><RegistrationInfo><Description>$(& $e "PC-Tweaks: сторож, поставлен из окна Помощника ($n)")</Description><URI>\$n</URI><SecurityDescriptor>$(Sddl $sid)</SecurityDescriptor></RegistrationInfo>" +
  "<Triggers>$($tr -join '')</Triggers><Principals><Principal id=`"Author`"><UserId>$sid</UserId><LogonType>InteractiveToken</LogonType><RunLevel>$(if ($d.H) { 'HighestAvailable' } else { 'LeastPrivilege' })</RunLevel></Principal></Principals>" +
  "<Settings><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><ExecutionTimeLimit>$($d.Lim)</ExecutionTimeLimit><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><StartWhenAvailable>$("$swa".ToLower())</StartWhenAvailable><Enabled>true</Enabled></Settings>" +
  "<Actions Context=`"Author`"><Exec><Command>$(& $e "$win\System32\conhost.exe")</Command><Arguments>$(& $e $ar)</Arguments></Exec></Actions></Task>" }
# Планировщик или стенд: есть ли задача, включить/выключить, создать, состояние для журнала
function FakeF { "$Fake\task-$Task.xml" }
function Has { if ($Fake) { [IO.File]::Exists((FakeF)) } else { [bool](Get-ScheduledTask -TaskName $Task) } }
function SetOn($v) { if ($Fake) { [IO.File]::WriteAllText((FakeF), ([IO.File]::ReadAllText((FakeF)) -replace '<Enabled>(true|false)</Enabled></Settings>', "<Enabled>$("$v".ToLower())</Enabled></Settings>"), [Text.Encoding]::Unicode) }
  elseif ($v) { Enable-ScheduledTask -TaskName $Task | Out-Null } else { Disable-ScheduledTask -TaskName $Task | Out-Null } }
function NewTask($xml, $sid) { if ($Fake) { [IO.File]::WriteAllText((FakeF), $xml, [Text.Encoding]::Unicode) } else { $s = New-Object -ComObject Schedule.Service; $s.Connect(); [void]$s.GetFolder('\').RegisterTask($Task, $xml, 6, $null, $null, 3, (Sddl $sid)) } }
# Метка установщика (GUARDS-INSTALL-FIX): имя созданной задачи — в tasks <корень>\setup\installed.json, иначе «Удалить Помощника» её не уберёт.
# Пустой tasks — удаление взяло бы запасной список, поэтому сначала задачи обновления. Под повышением PCT_ROOT не беру: метку пишет администратор
function MarkAdd($n) { if (-not $Fake -and $env:PCT_ROOT) { Log "${n}: PCT_ROOT под повышением — метка установщика не тронута"; return }
  $f = "$(PctRoot)\setup\installed.json"
  try { $m = [IO.File]::ReadAllText($f) | ConvertFrom-Json -ErrorAction Stop; if ($m -isnot [Management.Automation.PSCustomObject]) { throw 'не объект' }
    $t = @($m.tasks | Where-Object { $_ } | ForEach-Object { "$_" }); if (-not $t.Count) { $t = @('PCT-Helper-Update', 'PCT-Helper-Update-Now') }
    if ($t -contains $n) { return }; $t += $n
    if ($m.PSObject.Properties['tasks']) { $m.tasks = $t } else { $m | Add-Member -NotePropertyName tasks -NotePropertyValue $t }
    [IO.File]::WriteAllText($f, ($m | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false)) }
  catch { Log "${n}: метка установщика $f не обновлена: $($_.Exception.Message)" } }
function State { if ($Fake) { if ([IO.File]::ReadAllText((FakeF)) -match '<Enabled>false</Enabled></Settings>') { 'Disabled' } else { 'Ready' } } else { (Get-ScheduledTask -TaskName $Task).State } }
if (-not (Has)) {
  if (-not $On) { return }
  $d = $Defs[$Task]; if (-not $d) { Log "$Task -> поставить: задачи нет, создавать её не умею"; exit 2 }
  $f = "$(PctDir 'helpers')\$($d.F)"; if (-not [IO.File]::Exists($f)) { Log "$Task -> поставить: нет файла $f — задача не создана"; exit 3 }
  try { $u = UserSid; NewTask (TaskDoc $Task $d $u) $u } catch { Log "$Task -> поставить: Планировщик не принял задачу: $($_.Exception.Message)"; exit 4 }
  if (-not (Has)) { Log "$Task -> поставить: задача не появилась"; exit 4 }
  Log "$Task -> поставить для $u (сейчас: $(State))"; MarkAdd $Task; exit 0 }
SetOn ([bool]$On)
Log ("{0} -> {1} (сейчас: {2})" -f $Task, $(if ($On) { 'включить' } else { 'выключить' }), (State))
