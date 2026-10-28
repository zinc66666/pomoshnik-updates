# Обход заблокированных сайтов в браузере: сценарий прокси (PAC) — сайты из proxy-sites.txt через Happ (SOCKS из pct-core.ps1),
# если Happ не подключён — напрямую; все остальные сайты всегда напрямую. -On / -Off / -Apply (обновить, если включено).
param([switch]$On, [switch]$Off, [switch]$Apply)
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
$Hd = PctDir 'helpers'; $flag = "$Hd\smart-proxy-on.txt"; $list = "$Hd\proxy-sites.txt"
$k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
function Url { $d = @(Get-Content $list -Encoding UTF8 | ForEach-Object { (($_ -replace '#.*', '').Trim().ToLower() -replace '^[a-z]+://', '' -replace '[/:].*$', '' -replace '^www\.', '') } | Where-Object { $_ -match '^[a-z0-9.-]+\.[a-z]{2,}$' } | Select-Object -Unique)
  $js = 'function FindProxyForURL(url, host) { host = host.toLowerCase(); var d = [' + (($d | ForEach-Object { '"' + $_ + '"' }) -join ',') + ']; for (var i = 0; i < d.length; i++) { if (host == d[i] || dnsDomainIs(host, "." + d[i])) return "SOCKS5 ' + (PctSocks) + '; DIRECT"; } return "DIRECT"; }'
  'data:application/x-ns-proxy-autoconfig;base64,' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($js)) }
function Refresh { Add-Type -Namespace PCT -Name Inet -MemberDefinition '[DllImport("wininet.dll")] public static extern bool InternetSetOption(System.IntPtr h, int o, System.IntPtr b, int l);'
  [void][PCT.Inet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0); [void][PCT.Inet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) }
if ($Off) { $cur = (Get-ItemProperty $k).AutoConfigURL; if ($cur -like 'data:application/x-ns-proxy-autoconfig*') { Remove-ItemProperty $k -Name AutoConfigURL }; Remove-Item $flag -Force; Refresh; return }
if ($On) { Set-Content -LiteralPath $flag (Get-Date -Format s) }
if (($On -or $Apply) -and (Test-Path $flag)) { $u = Url; if ((Get-ItemProperty $k).AutoConfigURL -ne $u) { Set-ItemProperty $k -Name AutoConfigURL -Value $u; Refresh } }