# CS8: запускатель окна — ярлык «Помощник» ведёт сюда. Есть Pomoshnik.exe (программа Windows) — открываю его; нет exe, не программа или exe вышел с ошибкой (код ≠ 0) в первые 10 с — окно на PowerShell (helper-app.ps1), как раньше.
# -Fix: ярлык «Помощник» на рабочем столе ведёт на helper-app.ps1 этой папки — переписать на этот файл (окно делает при запуске). -Undo: обратно на helper-app.ps1 (откат версии делает updater.ps1). Другие ярлыки не трогаю.
# Журнал — reports\open-helper.log. PCT_DESKTOP=<папка> — рабочий стол для проверок (с повышением PCT_* нет). Пример отката вручную: powershell -NoProfile -ExecutionPolicy Bypass -File open-helper.ps1 -Undo
param([switch]$Fix, [switch]$Undo)
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
function OhLog($t) { try { $d = PctDir 'reports'; [void][IO.Directory]::CreateDirectory($d); [IO.File]::AppendAllText("$d\open-helper.log", "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $t`n", (New-Object Text.UTF8Encoding $false)) } catch { $null = $_ } }
# Ярлык «Помощник.lnk»: в аргументах путь $From целиком (до и после — край, пробел или кавычка) → $To. Цель, значок, имя, папка — те же
function OhLink([string]$From, [string]$To) { $dt = $(if ($env:PCT_DESKTOP) { $env:PCT_DESKTOP } else { [Environment]::GetFolderPath('Desktop') }); $f = Join-Path $dt 'Помощник.lnk'
  if (-not [IO.File]::Exists($f) -or -not [IO.File]::Exists($To)) { return }
  try { $sc = (New-Object -ComObject WScript.Shell).CreateShortcut($f); $a = "$($sc.Arguments)"; $rx = '(?i)(?<=^|[\s"])' + [regex]::Escape($From) + '(?=$|[\s"])'
    if ($a -notmatch $rx) { return }
    $sc.Arguments = [regex]::Replace($a, $rx, $To.Replace('$', '$$')); $sc.Save(); OhLog "ярлык ${f}: $(Split-Path $From -Leaf) -> $(Split-Path $To -Leaf)" }
  catch { OhLog "ярлык $f не переписан: $($_.Exception.Message)" } }
if ($Fix) { OhLink "$PSScriptRoot\helper-app.ps1" "$PSScriptRoot\open-helper.ps1"; return }
if ($Undo) { OhLink "$PSScriptRoot\open-helper.ps1" "$PSScriptRoot\helper-app.ps1"; return }
# exe — программа Windows: заголовок MZ, по смещению из 0x3C — PE\0\0 (как IsPE в updater.ps1, только первые 4 КБ)
function OhPE($f) { try { $s = [IO.File]::OpenRead($f); try { $b = New-Object byte[] 4096; $n = $s.Read($b, 0, 4096) } finally { $s.Dispose() } } catch { return $false }
  if ($n -lt 64 -or $b[0] -ne 0x4D -or $b[1] -ne 0x5A) { return $false }; $o = [BitConverter]::ToInt32($b, 0x3C); $o -gt 0 -and $o + 4 -le $n -and $b[$o] -eq 0x50 -and $b[$o + 1] -eq 0x45 -and $b[$o + 2] -eq 0 -and $b[$o + 3] -eq 0 }
$exe = "$PSScriptRoot\Pomoshnik.exe"; $why = 'нет Pomoshnik.exe'
if ([IO.File]::Exists($exe)) { if (-not (OhPE $exe)) { $why = 'Pomoshnik.exe не программа Windows' } else {
    # второй запуск exe выводит открытое окно вперёд и выходит с кодом 0; сбой запуска окна — код 1 и строка в helper-app-error.txt (App.cs)
    try { $p = [Diagnostics.Process]::Start($exe); if (-not $p.WaitForExit(10000) -or $p.ExitCode -eq 0) { return }; $why = "Pomoshnik.exe вышел с кодом $($p.ExitCode)" }
    catch { $why = "Pomoshnik.exe не запустился: $($_.Exception.Message)" } } }
OhLog "$why — открываю окно на PowerShell"
& "$PSScriptRoot\helper-app.ps1"
