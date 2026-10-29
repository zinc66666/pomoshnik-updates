# Обновление Помощника: скачивает подписанный manifest.json с GitHub, проверяет подпись (RSA-3072, ключ ниже — только открытая часть),
# сверяет SHA-256 каждого файла, делает копию старых файлов и ставит новые. Ход загрузки пишет в update-status.json (его показывает окно).
# Не встала или окно упало после установки → откат на копию, упавшая версия — в update-bad.txt и больше не ставится.
# -Silent: без окна, итог уведомлением (ежедневная задача PCT-Helper-Update). -Root: папка helpers (для проверок — временная).
param([switch]$Silent, [string]$Root)
$ErrorActionPreference = 'SilentlyContinue'
# корень и порт — сам, без pct-core.ps1: после отката его может не быть, а этот файл остаётся новым
if (-not $Root) { $Root = if ((Split-Path $PSScriptRoot -Leaf) -eq 'helpers') { $PSScriptRoot } else { 'C:\PC-Tweaks-Laptop\helpers' } }
$Socks = '127.0.0.1:10808'; try { $sx = "$(([IO.File]::ReadAllText("$env:LOCALAPPDATA\Pomoshnik\profile.json") | ConvertFrom-Json).vpn.socks)"; if ($sx -match '^127\.0\.0\.1:(\d{2,5})$' -and [int]$Matches[1] -le 65535) { $Socks = $sx } } catch {}
$Hd = $Root; $Pc = Split-Path $Hd -Parent; $Base = 'https://raw.githubusercontent.com/zinc66666/pomoshnik-updates/main'
$st = "$Hd\update-status.json"; $verf = "$Hd\version.txt"; $logf = "$Pc\reports\updates.log"
$pend = "$Hd\update-pending.json"; $badf = "$Hd\update-bad.txt"; $inv = [Globalization.CultureInfo]::InvariantCulture
$pub = '<RSAKeyValue><Modulus>9JBBs40wV0047YBgqakG3vO2cenKQtwlSzStUhUory72XsV3CDdFJW8xDrTwF4OoZXcP6ltlK9ww6tItOCaD1XlETqOit7xpinGFZA+Jn3HthhhZTItwcCA28iRTe7P92FLFrfMWGpwJIfI7z0Fwm3E2QhJgIhGtY+NmYUe78PXHvKR7kM7kSkYpjJMYqUDd3JhAATioIcOU+OCgtF18aMiXGsjT1pgyh4ez0VhoK8b32uPW+tRNVBq9+ITIot4aepqIyb2VyXJ8pyRxXNH/1ELNgS4JpgYPGD7v+Yp6G8L4HRQQw04pDq0rPfBo/3oK7UswP8IawJgMilbVRRtAkUPvWcw/XpHSA0XppfvvkxZedd81vq8NJKSeTNnF8E9CYswpuxRE4Hskyo/whetmBKHSrWEOd5kqOfoPafH8lby8XfD04pqY3pEGazd28CvW5FgR3cLf1+OK0INhEGVIwyg/49vEhbYS8MHOm60RAGapUMBmIjP0UZgWz5DdJaRd</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>'
function Status($state, $pct, $msg, $ver, $notes) { $o = [ordered]@{ state = $state; pct = $pct; msg = $msg; ver = $ver; notes = $notes; t = (Get-Date -Format s) }
  [IO.File]::WriteAllText($st, ($o | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false)) }
function Log($t) { Add-Content -LiteralPath $logf ("{0:yyyy-MM-dd HH:mm} {1}" -f (Get-Date), $t) -Encoding UTF8 }
function Fetch($url, $out) {
  foreach ($px in @($null, $Socks)) { Remove-Item -LiteralPath $out -Force
    $a = @('-s', '-f', '-L', '--max-time', '90', '-o', $out, "$url`?nocache=$(Get-Random)"); if ($px) { $a += @('--socks5-hostname', $px) }
    & curl.exe @a 2>$null; if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $out)) { return $true } }
  $false }
function Notify($t, $b) { . "$Pc\guard\notify.ps1"; Send-Notify $t $b }
# «Что нового» для окна: из manifest только строки 1–120 знаков в одну строку без личных данных, до 8 в разделе; нет changes → один пункт из notes
function WnList($a) { @(@($a) | Where-Object { $s = $_; $s -is [string] -and $s.Trim() -and $s.Length -le 120 -and $s -notmatch '[\r\n]' -and -not @('C:\\Users\\', '@(gmail|yandex|mail|bk|inbox)\.', '\+7\d{10}', '\b[78]\d{10}\b', '\b\d{9,10}\b' | Where-Object { $s -match $_ }).Count } | ForEach-Object { $_.Trim() } | Select-Object -First 8) }
function WhatsNew($m, $out) { $c = $m.changes
  $o = [ordered]@{ ver = "$($m.version)"; date = $(if ("$($m.date)" -match '^\d{4}-\d{2}-\d{2}$') { "$($m.date)" } else { '' }); new = @(WnList $c.new); fixed = @(WnList $c.fixed); improved = @(WnList $c.improved) }
  if (-not $c) { $o.new = @(WnList $m.notes) }
  [IO.File]::WriteAllText($out, ($o | ConvertTo-Json -Depth 3), (New-Object Text.UTF8Encoding $false)) }
# откат по копии update-backup\<версия>: вернуть заменённые файлы, удалить новые; $keep не трогать. Возвращает то, что не вышло
function Restore($bk, $keep) { $err = @(); if (-not (Test-Path -LiteralPath $bk)) { return @('копии нет') }
  foreach ($n in @(Get-Content -LiteralPath "$bk\new-files.list" | Where-Object { $_ -match '^[A-Za-z0-9._-]+\.(ps1|txt)$' -and $_ -ne $keep })) {
    try { if (Test-Path -LiteralPath "$Hd\$n") { Remove-Item -LiteralPath "$Hd\$n" -Force -ErrorAction Stop } } catch { $err += $n } }
  foreach ($b in @(Get-ChildItem -LiteralPath $bk -File | Where-Object { $_.Name -match '^[A-Za-z0-9._-]+\.(ps1|txt)$' -and $_.Name -ne $keep })) {
    try { if ((Get-FileHash -LiteralPath "$Hd\$($b.Name)").Hash -ne (Get-FileHash -LiteralPath $b.FullName).Hash) { Copy-Item -LiteralPath $b.FullName "$Hd\$($b.Name)" -Force -ErrorAction Stop } } catch { $err += $b.Name } }
  $err }
# один запуск: окно и задача PCT-Helper-Update могут начать вместе; мьютекс освобождается сам при выходе процесса
$mx = New-Object Threading.Mutex($false, 'Local\PCT-Helper-Updater'); $own = $false; try { $own = $mx.WaitOne(0) } catch { $own = $true }
if (-not $own) { Status 'checking' 0 'Обновление уже идёт' '' ''; Log 'второй запуск — обновление уже идёт'; return }
$cur = "$(Get-Content $verf -TotalCount 1)".Trim(); if ($cur -notmatch '^\d+(\.\d+){1,3}$') { $cur = '0.0' }
# проверка прошлой установки: окно упало после неё → откат; 24 ч без падений → установка принята
$p = $null; try { $p = [IO.File]::ReadAllText($pend) | ConvertFrom-Json } catch {}
if ($p) { $t0 = [datetime]::MinValue
  if (-not [datetime]::TryParseExact("$($p.t)", 's', $inv, 'None', [ref]$t0) -or "$($p.ver)" -ne $cur -or "$($p.prev)" -notmatch '^\d+(\.\d+){1,3}$') { Remove-Item -LiteralPath $pend -Force }
  elseif (@(Get-Content -LiteralPath "$Pc\reports\helper-app-error.txt" | Where-Object { $d = [datetime]::MinValue; $_.Length -ge 19 -and [datetime]::TryParseExact($_.Substring(0, 19), 's', $inv, 'None', [ref]$d) -and $d -gt $t0 -and $d -lt $t0.AddHours(24) }).Count) {
    # updater.ps1 остаётся новым: прошлый может не знать update-bad.txt и поставить эту версию снова
    $err = @(Restore "$Hd\update-backup\$($p.prev)" 'updater.ps1')
    if ($err.Count) { Status 'error' 0 'Новая версия не запустилась, вернуть прошлую пока не вышло — попробую позже' $cur ''; Log "НЕ ЗАПУСТИЛАСЬ $cur, откат не вышел: $($err -join ', ')"; return }
    [IO.File]::WriteAllText($verf, "$($p.prev)", (New-Object Text.UTF8Encoding $false)); Add-Content -LiteralPath $badf $cur -Encoding UTF8; Remove-Item -LiteralPath $pend -Force
    Status 'error' 0 'Новая версия не запустилась — Помощник вернул прошлую' $p.prev ''; Log "НЕ ЗАПУСТИЛАСЬ $cur — возвращена $($p.prev), $cur больше не ставится"
    Notify 'Новая версия не запустилась' 'Помощник вернул прошлую'; return }
  elseif (((Get-Date) - $t0).TotalHours -ge 24) { Remove-Item -LiteralPath $pend -Force } }
$tmp = Join-Path $env:TEMP 'pct-update'; Remove-Item $tmp -Recurse -Force; New-Item -ItemType Directory -Force "$tmp\f" | Out-Null
# точный коммит main через GitHub API: файлы по адресу коммита не берутся из устаревшего кэша (кэш main — до 5 минут)
foreach ($px in @($null, $Socks)) { $a = @('-s', '-f', '--max-time', '20', '-H', 'Accept: application/vnd.github.sha', 'https://api.github.com/repos/zinc66666/pomoshnik-updates/commits/main'); if ($px) { $a += @('--socks5-hostname', $px) }
  $sha = "$(& curl.exe @a 2>$null)".Trim(); if ($sha -match '^[0-9a-f]{40}$') { $Base = $Base -replace '/main$', "/$sha"; break } }
Status 'checking' 0 'Проверяю обновления…' $cur ''
if (-not ((Fetch "$Base/manifest.json" "$tmp\manifest.json") -and (Fetch "$Base/manifest.sig" "$tmp\manifest.sig"))) { Status 'error' 0 'Нет связи с сервером обновлений' $cur ''; Log 'нет связи'; return }
$mb = [IO.File]::ReadAllBytes("$tmp\manifest.json")
$rsa = New-Object Security.Cryptography.RSACryptoServiceProvider; $rsa.FromXmlString($pub)
$sigOk = $false; try { $sigOk = $rsa.VerifyData($mb, 'SHA256', [Convert]::FromBase64String(([IO.File]::ReadAllText("$tmp\manifest.sig")).Trim())) } catch {}
if (-not $sigOk) { Status 'error' 0 'Подпись обновления не совпала — обновление отклонено' $cur ''; Log 'ПОДПИСЬ НЕ СОВПАЛА — отклонено'; return }
$m = [Text.Encoding]::UTF8.GetString($mb) | ConvertFrom-Json
$bad = @(Get-Content -LiteralPath $badf | ForEach-Object { $_.Trim() })
if ("$($m.version)" -notmatch '^\d+(\.\d+){1,3}$' -or [version]$m.version -le [version]$cur -or $bad -contains "$($m.version)") { Status 'uptodate' 100 "Последняя версия: $cur" $cur ''; return }
$files = @($m.files | Where-Object { $_.path -match '^[A-Za-z0-9._-]+\.(ps1|txt)$' -and $_.sha256 -match '^[0-9a-f]{64}$' })
$i = 0
foreach ($f in $files) { $i++
  Status 'downloading' ([int](100 * ($i - 1) / $files.Count)) "Скачиваю версию $($m.version): $($f.path)" $m.version $m.notes
  $out = "$tmp\f\$($f.path)"
  if (-not (Fetch "$Base/releases/$($m.version)/$($f.path)" $out)) { Status 'error' 0 "Не скачался файл $($f.path) — попробую позже" $cur ''; Log "не скачался $($f.path)"; return }
  if ((Get-FileHash -LiteralPath $out -Algorithm SHA256).Hash.ToLower() -ne $f.sha256) { Status 'error' 0 "Файл $($f.path) не прошёл проверку — обновление отменено" $cur ''; Log "ХЭШ НЕ СОВПАЛ $($f.path) — отменено"; return } }
Status 'installing' 100 "Устанавливаю версию $($m.version)…" $m.version $m.notes
# копия всех заменяемых файлов и список новых — до первой замены
$bk = "$Hd\update-backup\$cur"; $new = @()
# прошлый откат не довершён → сначала довершить его, иначе копия прежней версии потеряется
if ((Test-Path -LiteralPath "$bk\restore-failed.list") -and @(Restore $bk $null).Count) { Status 'error' 0 'Прошлую версию вернуть пока не вышло — попробую позже' $cur ''; Log "откат по $bk снова не вышел"; return }
try { if (Test-Path -LiteralPath $bk) { Remove-Item -LiteralPath $bk -Recurse -Force -ErrorAction Stop }; New-Item -ItemType Directory -Force $bk -ErrorAction Stop | Out-Null
  foreach ($f in $files) { $dst = "$Hd\$($f.path)"; if (Test-Path -LiteralPath $dst) { Copy-Item -LiteralPath $dst "$bk\$($f.path)" -Force -ErrorAction Stop } else { $new += $f.path } }
  [IO.File]::WriteAllLines("$bk\new-files.list", [string[]]$new) }
catch { Status 'error' 0 'Не получилось сохранить копию старых файлов — обновление отменено' $cur ''; Log "копия не сделана: $($_.Exception.Message)"; return }
# замена, затем разбор каждого .ps1 версии; любая ошибка → откат по копии, version.txt прежний
$err = $null
try { foreach ($f in $files) { Copy-Item -LiteralPath "$tmp\f\$($f.path)" "$Hd\$($f.path)" -Force -ErrorAction Stop }
  foreach ($f in @($files | Where-Object { $_.path -like '*.ps1' })) { $pe = $null; [void][Management.Automation.Language.Parser]::ParseFile("$Hd\$($f.path)", [ref]$null, [ref]$pe)
    if ($pe) { throw "ошибка разбора $($f.path): $($pe[0].Message)" } }
  [IO.File]::WriteAllText($pend, ([ordered]@{ ver = "$($m.version)"; prev = $cur; t = (Get-Date -Format s) } | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false))
  [IO.File]::WriteAllText($verf, "$($m.version)", (New-Object Text.UTF8Encoding $false)) }
catch { $err = $_.Exception.Message }
if ($err) { $rb = @(Restore $bk $null); if ($rb.Count) { [IO.File]::WriteAllLines("$bk\restore-failed.list", [string[]]$rb) }
  Status 'error' 0 $(if ($rb.Count) { "Версия $($m.version) не установилась, прошлую вернуть пока не вышло — попробую позже" } else { "Версия $($m.version) не установилась — Помощник вернул прошлую" }) $cur ''
  Log "НЕ УСТАНОВИЛАСЬ $($m.version): $err; откат: $(if ($rb.Count) { 'не вышел для ' + ($rb -join ', ') } else { 'выполнен' })"; return }
# сайты дописываю после удачной установки: при откате proxy-sites.txt не трогается
if (Test-Path -LiteralPath "$tmp\f\proxy-sites-default.txt") { $have = @(Get-Content "$Hd\proxy-sites.txt" -Encoding UTF8 | ForEach-Object { $_.Trim().ToLower() })
  $add = @(Get-Content "$tmp\f\proxy-sites-default.txt" -Encoding UTF8 | Where-Object { $_ -match '^[a-z0-9.-]+\.[a-z]{2,}$' -and $have -notcontains $_.Trim().ToLower() })
  if ($add) { Add-Content "$Hd\proxy-sites.txt" $add -Encoding UTF8; & "$Hd\smart-proxy.ps1" -Apply } }
try { WhatsNew $m "$Hd\whats-new.json" } catch { Log "whats-new.json не записан: $($_.Exception.Message)" }
Status 'done' 100 "Обновлено до версии $($m.version)" $m.version $m.notes
Log "обновлено $cur -> $($m.version) ($($files.Count) файлов): $($m.notes)"
if ($Silent) { Notify "Помощник обновлён до $($m.version)" "$($m.notes)" }
Remove-Item $tmp -Recurse -Force
