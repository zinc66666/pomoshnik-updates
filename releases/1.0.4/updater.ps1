# Обновление Помощника: скачивает подписанный manifest.json с GitHub, проверяет подпись (RSA-3072, ключ ниже — только открытая часть),
# сверяет SHA-256 каждого файла, делает копию старых файлов и ставит новые. Ход загрузки пишет в update-status.json (его показывает окно).
# -Silent: без окна, итог уведомлением (ежедневная задача PCT-Helper-Update).
param([switch]$Silent)
$ErrorActionPreference = 'SilentlyContinue'
$Hd = 'C:\PC-Tweaks-Laptop\helpers'; $Base = 'https://raw.githubusercontent.com/zinc66666/pomoshnik-updates/main'
$st = "$Hd\update-status.json"; $verf = "$Hd\version.txt"; $logf = 'C:\PC-Tweaks-Laptop\reports\updates.log'
$pub = '<RSAKeyValue><Modulus>9JBBs40wV0047YBgqakG3vO2cenKQtwlSzStUhUory72XsV3CDdFJW8xDrTwF4OoZXcP6ltlK9ww6tItOCaD1XlETqOit7xpinGFZA+Jn3HthhhZTItwcCA28iRTe7P92FLFrfMWGpwJIfI7z0Fwm3E2QhJgIhGtY+NmYUe78PXHvKR7kM7kSkYpjJMYqUDd3JhAATioIcOU+OCgtF18aMiXGsjT1pgyh4ez0VhoK8b32uPW+tRNVBq9+ITIot4aepqIyb2VyXJ8pyRxXNH/1ELNgS4JpgYPGD7v+Yp6G8L4HRQQw04pDq0rPfBo/3oK7UswP8IawJgMilbVRRtAkUPvWcw/XpHSA0XppfvvkxZedd81vq8NJKSeTNnF8E9CYswpuxRE4Hskyo/whetmBKHSrWEOd5kqOfoPafH8lby8XfD04pqY3pEGazd28CvW5FgR3cLf1+OK0INhEGVIwyg/49vEhbYS8MHOm60RAGapUMBmIjP0UZgWz5DdJaRd</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>'
function Status($state, $pct, $msg, $ver, $notes) { $o = [ordered]@{ state = $state; pct = $pct; msg = $msg; ver = $ver; notes = $notes; t = (Get-Date -Format s) }
  [IO.File]::WriteAllText($st, ($o | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false)) }
function Log($t) { Add-Content -LiteralPath $logf ("{0:yyyy-MM-dd HH:mm} {1}" -f (Get-Date), $t) -Encoding UTF8 }
function Fetch($url, $out) {
  foreach ($px in @($null, '127.0.0.1:10808')) { Remove-Item -LiteralPath $out -Force
    $a = @('-s', '-f', '-L', '--max-time', '90', '-o', $out, "$url`?nocache=$(Get-Random)"); if ($px) { $a += @('--socks5-hostname', $px) }
    & curl.exe @a 2>$null; if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $out)) { return $true } }
  $false }
$tmp = Join-Path $env:TEMP 'pct-update'; Remove-Item $tmp -Recurse -Force; New-Item -ItemType Directory -Force "$tmp\f" | Out-Null
# точный коммит main через GitHub API: файлы по адресу коммита не берутся из устаревшего кэша (кэш main — до 5 минут)
foreach ($px in @($null, '127.0.0.1:10808')) { $a = @('-s', '-f', '--max-time', '20', '-H', 'Accept: application/vnd.github.sha', 'https://api.github.com/repos/zinc66666/pomoshnik-updates/commits/main'); if ($px) { $a += @('--socks5-hostname', $px) }
  $sha = "$(& curl.exe @a 2>$null)".Trim(); if ($sha -match '^[0-9a-f]{40}$') { $Base = $Base -replace '/main$', "/$sha"; break } }
$cur = "$(Get-Content $verf -TotalCount 1)".Trim(); if ($cur -notmatch '^\d+(\.\d+){1,3}$') { $cur = '0.0' }
Status 'checking' 0 'Проверяю обновления…' $cur ''
if (-not ((Fetch "$Base/manifest.json" "$tmp\manifest.json") -and (Fetch "$Base/manifest.sig" "$tmp\manifest.sig"))) { Status 'error' 0 'Нет связи с сервером обновлений' $cur ''; Log 'нет связи'; return }
$mb = [IO.File]::ReadAllBytes("$tmp\manifest.json")
$rsa = New-Object Security.Cryptography.RSACryptoServiceProvider; $rsa.FromXmlString($pub)
$sigOk = $false; try { $sigOk = $rsa.VerifyData($mb, 'SHA256', [Convert]::FromBase64String(([IO.File]::ReadAllText("$tmp\manifest.sig")).Trim())) } catch {}
if (-not $sigOk) { Status 'error' 0 'Подпись обновления не совпала — обновление отклонено' $cur ''; Log 'ПОДПИСЬ НЕ СОВПАЛА — отклонено'; return }
$m = [Text.Encoding]::UTF8.GetString($mb) | ConvertFrom-Json
if ("$($m.version)" -notmatch '^\d+(\.\d+){1,3}$' -or [version]$m.version -le [version]$cur) { Status 'uptodate' 100 "Последняя версия: $cur" $cur ''; return }
$files = @($m.files | Where-Object { $_.path -match '^[A-Za-z0-9._-]+\.(ps1|txt)$' -and $_.sha256 -match '^[0-9a-f]{64}$' })
$i = 0
foreach ($f in $files) { $i++
  Status 'downloading' ([int](100 * ($i - 1) / $files.Count)) "Скачиваю версию $($m.version): $($f.path)" $m.version $m.notes
  $out = "$tmp\f\$($f.path)"
  if (-not (Fetch "$Base/releases/$($m.version)/$($f.path)" $out)) { Status 'error' 0 "Не скачался файл $($f.path) — попробую позже" $cur ''; Log "не скачался $($f.path)"; return }
  if ((Get-FileHash -LiteralPath $out -Algorithm SHA256).Hash.ToLower() -ne $f.sha256) { Status 'error' 0 "Файл $($f.path) не прошёл проверку — обновление отменено" $cur ''; Log "ХЭШ НЕ СОВПАЛ $($f.path) — отменено"; return } }
Status 'installing' 100 "Устанавливаю версию $($m.version)…" $m.version $m.notes
$bk = "$Hd\update-backup\$cur"; New-Item -ItemType Directory -Force $bk | Out-Null
foreach ($f in $files) { $dst = "$Hd\$($f.path)"; if (Test-Path -LiteralPath $dst) { Copy-Item -LiteralPath $dst "$bk\$($f.path)" -Force }
  if ($f.path -eq 'proxy-sites-default.txt') { $have = @(Get-Content "$Hd\proxy-sites.txt" -Encoding UTF8 | ForEach-Object { $_.Trim().ToLower() })
    $add = @(Get-Content "$tmp\f\$($f.path)" -Encoding UTF8 | Where-Object { $_ -match '^[a-z0-9.-]+\.[a-z]{2,}$' -and $have -notcontains $_.Trim().ToLower() })
    if ($add) { Add-Content "$Hd\proxy-sites.txt" $add -Encoding UTF8; & "$Hd\smart-proxy.ps1" -Apply } }
  Copy-Item -LiteralPath "$tmp\f\$($f.path)" $dst -Force }
[IO.File]::WriteAllText($verf, "$($m.version)", (New-Object Text.UTF8Encoding $false))
Status 'done' 100 "Обновлено до версии $($m.version)" $m.version $m.notes
Log "обновлено $cur -> $($m.version) ($($files.Count) файлов): $($m.notes)"
if ($Silent) { . 'C:\PC-Tweaks-Laptop\guard\notify.ps1'; Send-Notify "Помощник обновлён до $($m.version)" "$($m.notes)" }
Remove-Item $tmp -Recurse -Force
