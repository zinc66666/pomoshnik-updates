$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
$G = PctDir 'guard'; . (PctNotifyPath)
$dl = [Environment]::ExpandEnvironmentVariables((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders').'{374DE290-123F-4565-9164-39C4925E467B}')
if (-not $dl -or -not (Test-Path $dl)) { $dl = Join-Path $env:USERPROFILE 'Downloads' }
$state = "$G\downloads-last.txt"
$since = if (Test-Path $state) { [datetime]::Parse((Get-Content $state -Raw).Trim()) } else { Get-Date }
(Get-Date).ToString('o') | Set-Content $state
$exe = '.exe','.msi','.scr','.com','.dll','.cpl','.msix','.appx'
$scr = '.js','.jse','.vbs','.vbe','.wsf','.hta','.bat','.cmd','.ps1','.lnk','.url','.reg','.iso','.img','.vhd'
Get-ChildItem $dl -File -Recurse -Depth 1 | Where-Object { ($_.CreationTime -gt $since -or $_.LastWriteTime -gt $since) } | ForEach-Object {
  $f = $_; $x = $f.Extension.ToLower()
  if ($exe -contains $x) {
    $s = Get-AuthenticodeSignature -LiteralPath $f.FullName
    if ($s.Status -ne 'Valid') { Send-Notify 'Скачан файл БЕЗ подписи' "$($f.Name)`nНе запускайте, пока не проверите (Kaspersky/VirusTotal)." }
  } elseif ($scr -contains $x) {
    Send-Notify 'Скачан скрипт/ярлык' "$($f.Name)`nТакие файлы часто содержат вирусы. Не открывайте, если не ждали его."
  } elseif ($x -eq '.zip') {
    try { Add-Type -AssemblyName System.IO.Compression.FileSystem; $z = [IO.Compression.ZipFile]::OpenRead($f.FullName)
      $bad = @($z.Entries | Where-Object { ($exe + $scr) -contains ([IO.Path]::GetExtension($_.Name).ToLower()) } | Select-Object -First 3 -ExpandProperty Name); $z.Dispose()
      if ($bad.Count) { Send-Notify 'Архив с программами внутри' "$($f.Name): $($bad -join ', ')`nПроверьте перед запуском." } } catch { }
  }
}