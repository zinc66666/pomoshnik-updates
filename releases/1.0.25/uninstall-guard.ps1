. "$PSScriptRoot\pct-core.ps1"
'PCT-Guard-Autoruns','PCT-Guard-Downloads','PCT-Clean-Temp' | ForEach-Object { Unregister-ScheduledTask -TaskName $_ -Confirm:$false -ErrorAction SilentlyContinue }
Remove-Item ([Environment]::GetFolderPath('Desktop') + '\Проверка безопасности.lnk') -Force -ErrorAction SilentlyContinue
Write-Host "Сторожа удалены (папка $(PctDir 'guard') оставлена с журналами)." -ForegroundColor Green; Start-Sleep 8