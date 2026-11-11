$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
function Get-RealIf { $a = Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | Sort-Object { ($r = Get-NetRoute -InterfaceIndex $_.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1); if ($r) { $r.RouteMetric + $_.InterfaceMetric } else { 99999 } } | Select-Object -First 1; if ($a) { $a.ifIndex } }
function Strip-If($a) { ($a -replace '--wf-iface=\S+\s*', '').Trim() }
if (Get-Process winws) { return }
$cfg = Get-Content "$(PctDir 'helpers')\zapret-cmd.txt" -Encoding UTF8
if (-not $cfg -or -not (Test-Path -LiteralPath $cfg[0])) { return }
$i = $null; for ($t = 0; $t -lt 30 -and -not $i; $t++) { $i = Get-RealIf; if (-not $i) { Start-Sleep 2 } }
$args2 = Strip-If $cfg[1]; if ($i) { $args2 = "--wf-iface=$i " + $args2 }
Start-Process -FilePath $cfg[0] -ArgumentList $args2 -WorkingDirectory (Split-Path $cfg[0]) -WindowStyle Hidden