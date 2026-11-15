# Уведомление Windows и строка в reports\alerts.log (до U1b — guard\, переносит PctData). Подключение: . (PctNotifyPath); без pct-core.ps1 (updater.ps1) — reports рядом с папкой этого файла
function Send-Notify([string]$Title, [string]$Body) {
  $log = $(if (Test-Path function:PctData) { PctData 'alerts.log' 'guard' } else { "$(Join-Path (Split-Path $PSScriptRoot -Parent) 'reports')\alerts.log" })
  Add-Content -Path $log -Value ("{0:yyyy-MM-dd HH:mm} | {1} | {2}" -f (Get-Date), $Title, $Body) -Encoding UTF8
  # больше 400 строк — оставляю 300 (как sites-watch.log), но не младше 8 дней: system-health считает предупреждения за неделю. Режу перед строкой с датой. .NET, не Select-Object: модуль сторожа не грузит
  try { $a = [IO.File]::ReadAllLines($log); if ($a.Count -gt 400) { $old = [DateTime]::Now.AddDays(-8); $k = $a.Count - 300
      while ($k -gt 0 -and -not ($a[$k] -match '^(\d{4}-\d\d-\d\d) ' -and $a[$k - 1] -match '^(\d{4}-\d\d-\d\d) ' -and [datetime]$Matches[1] -lt $old)) { $k-- }
      if ($k -gt 0) { [IO.File]::WriteAllLines($log, [string[]]$a[$k..($a.Count - 1)], [Text.UTF8Encoding]::new($true)) } } } catch {}
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