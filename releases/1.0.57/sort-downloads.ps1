$ErrorActionPreference = 'SilentlyContinue'
$Host.UI.RawUI.WindowTitle = 'Разобрать Загрузки'
$dl = [Environment]::ExpandEnvironmentVariables((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders').'{374DE290-123F-4565-9164-39C4925E467B}')
if (-not (Test-Path $dl)) { $dl = Join-Path $env:USERPROFILE 'Downloads' }
$map = [ordered]@{
  'Картинки'    = '.jpg','.jpeg','.png','.gif','.webp','.bmp','.heic','.psd','.svg','.ico','.tif','.tiff'
  'Видео'       = '.mp4','.mov','.mkv','.avi','.webm','.wmv','.m4v'
  'Музыка'      = '.mp3','.wav','.flac','.ogg','.m4a','.aac'
  'Документы'   = '.pdf','.doc','.docx','.xls','.xlsx','.ppt','.pptx','.txt','.rtf','.odt','.csv','.epub'
  'Архивы'      = '.zip','.rar','.7z','.tar','.gz'
  'Установщики' = '.exe','.msi','.msix','.appx','.apk'
}
$cut = (Get-Date).AddDays(-2); $log = Join-Path $dl '_разбор-журнал.csv'; $n = 0
Write-Host "`nРАЗБОР ПАПКИ «Загрузки»: $dl" -ForegroundColor Cyan
Write-Host 'Переносятся только файлы старше 2 дней. Папки и недокачанные файлы не трогаются.'
Get-ChildItem $dl -File | Where-Object { $_.LastWriteTime -lt $cut -and $_.Name -ne '_разбор-журнал.csv' -and $_.Extension -notin '.crdownload','.part','.tmp','.partial' } | ForEach-Object {
  $f = $_; $x = $f.Extension.ToLower(); $dest = 'Прочее'
  foreach ($k in $map.Keys) { if ($map[$k] -contains $x) { $dest = $k; break } }
  $dir = Join-Path $dl $dest; New-Item -ItemType Directory -Force $dir | Out-Null
  $to = Join-Path $dir $f.Name; $i = 1
  while (Test-Path -LiteralPath $to) { $to = Join-Path $dir ("{0} ({1}){2}" -f $f.BaseName, $i, $f.Extension); $i++ }
  Move-Item -LiteralPath $f.FullName -Destination $to
  if (Test-Path -LiteralPath $to) { Add-Content -LiteralPath $log -Value ('"{0}";"{1}"' -f $f.FullName, $to) -Encoding UTF8; $n++ }
}
Write-Host "`nПеренесено файлов: $n" -ForegroundColor Green
if ($n) { Write-Host 'Отменить можно ярлыком «5. Отменить разбор Загрузок».' }
Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null