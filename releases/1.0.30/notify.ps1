# Уведомление Windows и строка в reports\alerts.log (до U1b — guard\, переносит PctData). Подключение: . (PctNotifyPath); без pct-core.ps1 (updater.ps1) — reports рядом с папкой этого файла
function Send-Notify([string]$Title, [string]$Body) {
  $log = $(if (Test-Path function:PctData) { PctData 'alerts.log' 'guard' } else { "$(Join-Path (Split-Path $PSScriptRoot -Parent) 'reports')\alerts.log" })
  Add-Content -Path $log -Value ("{0:yyyy-MM-dd HH:mm} | {1} | {2}" -f (Get-Date), $Title, $Body) -Encoding UTF8
  try {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
    $e = { param($s) [Security.SecurityElement]::Escape($s) }
    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml("<toast duration='long'><visual><binding template='ToastGeneric'><text>$(& $e $Title)</text><text>$(& $e $Body)</text></binding></visual></toast>")
    $app = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($app).Show([Windows.UI.Notifications.ToastNotification]::new($xml))
  } catch { }
}