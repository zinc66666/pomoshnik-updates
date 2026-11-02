# Включить или выключить фоновую задачу-сторожа (вызывается из Помощника, вкладка «Сторожа»). Пишет журнал.
param([string]$Task, [switch]$On)
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { $ps = "$([Environment]::GetFolderPath('System'))\WindowsPowerShell\v1.0\powershell.exe"; Start-Process $ps -Verb RunAs -WindowStyle Hidden -Wait -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Task `"$Task`"" + $(if ($On) { ' -On' } else { '' })); return }
if (-not (Get-ScheduledTask -TaskName $Task)) { return }
if ($On) { Enable-ScheduledTask -TaskName $Task | Out-Null } else { Disable-ScheduledTask -TaskName $Task | Out-Null }
New-Item -ItemType Directory -Force (PctDir 'reports') | Out-Null
Add-Content "$(PctDir 'reports')\guards.log" ("{0:yyyy-MM-dd HH:mm} {1} -> {2} (сейчас: {3})" -f (Get-Date), $Task, $(if ($On) { 'включить' } else { 'выключить' }), (Get-ScheduledTask -TaskName $Task).State) -Encoding UTF8
