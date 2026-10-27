# Общие пути и порт Помощника. Подключение: . "$PSScriptRoot\pct-core.ps1". При подключении ничего не делает, только задаёт функции.
# Корень: $env:PCT_ROOT (для проверок) → папка выше helpers, если скрипт лежит в helpers → C:\PC-Tweaks-Laptop.
function PctRoot { if ($env:PCT_ROOT) { return $env:PCT_ROOT }
  if ((Split-Path $PSScriptRoot -Leaf) -eq 'helpers') { return (Split-Path $PSScriptRoot -Parent) }; 'C:\PC-Tweaks-Laptop' }
function PctDir([ValidateSet('helpers', 'guard', 'run', 'reports')][string]$Name) { Join-Path (PctRoot) $Name }
# SOCKS Happ: vpn.socks из профиля (только как JSON, только 127.0.0.1:<порт до 65535>), иначе 127.0.0.1:10808
function PctSocks { $s = ''; try { $s = "$(([IO.File]::ReadAllText("$env:LOCALAPPDATA\Pomoshnik\profile.json") | ConvertFrom-Json).vpn.socks)" } catch {}
  if ($s -match '^127\.0\.0\.1:(\d{2,5})$' -and [int]$Matches[1] -le 65535) { $s } else { '127.0.0.1:10808' } }
function PctSocksPort { [int](PctSocks).Split(':')[1] }
