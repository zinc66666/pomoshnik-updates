$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
$cut = (Get-Date).AddDays(-7); $freed = 0
foreach ($d in $env:TEMP, "$env:windir\Temp") {
  Get-ChildItem $d -Recurse -File -Force | Where-Object { $_.LastWriteTime -lt $cut } | ForEach-Object { $len = $_.Length; Remove-Item -LiteralPath $_.FullName -Force; if (-not (Test-Path -LiteralPath $_.FullName)) { $freed += $len } }
  Get-ChildItem $d -Recurse -Directory -Force | Sort-Object { $_.FullName.Length } -Descending | Where-Object { -not (Get-ChildItem $_.FullName -Force) } | Remove-Item -Force }
Add-Content "$(PctDir 'guard')\clean-temp.log" ("{0:yyyy-MM-dd HH:mm} освобождено {1:N1} МБ" -f (Get-Date), ($freed/1MB)) -Encoding UTF8