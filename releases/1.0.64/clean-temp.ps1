# Уборка %TEMP% и Windows\Temp: файлы и пустые папки старше 7 дней. Задача PCT-Clean-Temp — с наивысшими правами. -Dir — свои папки (проверки). Удаление по дескрипторам (PctWipe, pct-wiper.ps1): подмена папки ссылкой посреди обхода не уводит
param([string[]]$Dir)
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
. "$PSScriptRoot\pct-wiper.ps1"
# Для pct-wiper.ps1: с повышением класс собирается в своей папке администратора. PCT_CLEAN_FAKE — стенд, только для RaceHook (с повышением при UAC подмену снимает pct-core)
$Elevated = PctElevated; $Fake = "$env:PCT_CLEAN_FAKE"
function Jr($t) { Add-Content "$(PctDir 'guard')\clean-temp.log" ("{0:yyyy-MM-dd HH:mm} {1}" -f (Get-Date), $t) -Encoding UTF8 }
# С повышением TEMP и windir из окружения не беру (HKCU\Environment пишет любой её процесс): %TEMP% — из профиля по SID (HKLM), путь с %…% — не чищу
if (-not $Dir) { $Dir = if (PctElevated) { $h = PctHome; @(if ($h) { "$h\AppData\Local\Temp" }) + "$([Environment]::GetFolderPath('Windows'))\Temp" } else { $env:TEMP, "$env:windir\Temp" } }
# Без повышения корни из окружения: PctWipe сверяет итоговый путь с заданным и не примет короткое имя (YURII~1) или косую в конце. Привожу к полному виду, ссылки не разрешаю (их проверка ниже). Не абсолютный не беру: пустой TEMP дал бы корень диска
if (-not $Elevated) { $Dir = @(foreach ($d in $Dir) { if ("$d" -match '^[A-Za-z]:[\\/]') { try { [IO.Path]::GetFullPath("$d\.") } catch { Jr "пропускаю ${d}: $($_.Exception.Message)" } } else { Jr "пропускаю «$d»: путь не полный" } }) }
$cut = (Get-Date).AddDays(-7).ToFileTimeUtc(); $freed = [long]0; $busy = 0; $rp = [IO.FileAttributes]::ReparsePoint
# Сбой сборки: ничего не удалено, причина в журнале (нет pct-wiper.ps1 — тоже здесь)
try { WipeInit } catch { Jr "уборки не было: $($_.Exception.Message)"; return }
# Папка из списка или её родитель — точка соединения: не чищу
foreach ($d in $Dir) { $r = Get-Item -LiteralPath $d -Force; $ok = [bool]$r; for ($x = $r; $x; $x = $x.Parent) { if ($x.Attributes -band $rp) { $ok = $false } }; if (-not $ok) { Jr "пропускаю ${d}: нет папки или ссылка на другую папку"; continue }
  try { [PctWipe]::Run($d, $keepName, $cut, $null, (RaceHook)) } catch { Jr "не убрал ${d}: $($_.Exception.Message)" }
  foreach ($l in [PctWipe]::Log) { if ($l -notlike 'не тронул:*') { Jr $l } }; $freed += [PctWipe]::Freed; $busy += [PctWipe]::Busy }
Jr ("освобождено {0:N1} МБ, занято файлов: {1}" -f ($freed/1MB), $busy)