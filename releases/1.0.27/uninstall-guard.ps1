. "$PSScriptRoot\pct-core.ps1"
$gt = 'PCT-Guard-Autoruns','PCT-Guard-Downloads','PCT-Clean-Temp'
$gt | ForEach-Object { Unregister-ScheduledTask -TaskName $_ -Confirm:$false -ErrorAction SilentlyContinue }
Remove-Item ([Environment]::GetFolderPath('Desktop') + '\Проверка безопасности.lnk') -Force -ErrorAction SilentlyContinue
# «Удалены» — только если задач правда нет (без прав администратора Windows не даёт их удалить)
$left = @($gt | Where-Object { Get-ScheduledTask -TaskName $_ -ErrorAction SilentlyContinue })
if ($left) { Write-Host "Не удалось удалить: $($left -join ', '). Запусти удаление от имени администратора." -ForegroundColor Red }
else { Write-Host "Сторожа удалены (папка $(PctDir 'guard') оставлена с журналами)." -ForegroundColor Green }
Start-Sleep 8