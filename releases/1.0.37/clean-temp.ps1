# Уборка %TEMP% и Windows\Temp: файлы старше 7 дней, пустые папки старше суток. Задача PCT-Clean-Temp — с наивысшими правами. -Dir — свои папки (проверки)
param([string[]]$Dir)
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
# С повышением TEMP и windir из окружения не беру (HKCU\Environment пишет любой её процесс): %TEMP% — из профиля по SID (HKLM), путь с %…% — не чищу
if (-not $Dir) { $Dir = if (PctElevated) { $h = PctHome; @(if ($h) { "$h\AppData\Local\Temp" }) + "$([Environment]::GetFolderPath('Windows'))\Temp" } else { $env:TEMP, "$env:windir\Temp" } }
$cut = (Get-Date).AddDays(-7); $day = (Get-Date).AddDays(-1); $freed = 0; $rp = [IO.FileAttributes]::ReparsePoint
# Обход без -Recurse (его поведение со ссылками зависит от версии; папку-точку соединения в списке он проходит): точки соединения и ссылки (папки и файлы) пропускаю — не захожу, не удаляю.
# Папка из списка или её родитель — точка соединения: не чищу
foreach ($d in $Dir) { $r = Get-Item -LiteralPath $d -Force; $ok = [bool]$r; for ($x = $r; $x; $x = $x.Parent) { if ($x.Attributes -band $rp) { $ok = $false } }; if (-not $ok) { continue }
  $st = New-Object Collections.Stack; $st.Push($r); $dirs = New-Object Collections.Generic.List[object]
  while ($st.Count) { foreach ($i in @(Get-ChildItem -LiteralPath $st.Pop().FullName -Force)) { if ($i.Attributes -band $rp) { continue }
      if ($i.PSIsContainer) { $st.Push($i); $dirs.Add($i) } elseif ($i.LastWriteTime -lt $cut) { $len = $i.Length; Remove-Item -LiteralPath $i.FullName -Force; if (-not (Test-Path -LiteralPath $i.FullName)) { $freed += $len } } } }
  # Пустая папка младше суток может быть нужна программе, которая её только что создала. Время и вид — заново: после удаления файлов они другие
  $dirs | Sort-Object { $_.FullName.Length } -Descending | Where-Object { $_.Refresh(); -not ($_.Attributes -band $rp) -and $_.LastWriteTime -lt $day -and -not (Get-ChildItem -LiteralPath $_.FullName -Force) } | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force } }
Add-Content "$(PctDir 'guard')\clean-temp.log" ("{0:yyyy-MM-dd HH:mm} освобождено {1:N1} МБ" -f (Get-Date), ($freed/1MB)) -Encoding UTF8