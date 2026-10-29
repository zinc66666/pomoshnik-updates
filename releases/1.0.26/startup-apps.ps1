$Host.UI.RawUI.WindowTitle = 'Автозагрузка'
Write-Host "`nАВТОЗАГРУЗКА — программы, которые запускаются вместе с Windows`n" -ForegroundColor Cyan
Write-Host 'Сейчас откроется Диспетчер задач на вкладке «Автозагрузка».'
Write-Host 'Чтобы программа не запускалась сама: правый щелчок по ней -> «Отключить».'
Write-Host 'Вернуть — так же, «Включить». Программа не удаляется, просто не стартует сама.'
Write-Host "`nНЕ отключай: PenTablet / XP-Pen (планшет), драйверы звука и тачпада (Realtek, Synaptics, ELAN)." -ForegroundColor Yellow
Write-Host 'Можно отключать: Steam, Discord, Яндекс, uTorrent, Telegram, лаунчеры игр — они откроются, когда запустишь их сама.' -ForegroundColor Green
Start-Process taskmgr.exe -ArgumentList '/0 /startup'
Write-Host "`nНажмите Enter, чтобы закрыть это окно."; Read-Host | Out-Null