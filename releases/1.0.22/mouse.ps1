# «Мышь и тачпад»: что подключено, замер частоты и пропусков (Raw Input), вопросы про повышенную точность указателя и запрет отключения мыши, меняю выбранное, замер после. Перед изменением — бэкап.
# -Undo — «Вернуть как было» из бэкапа. PCT_MOUSE_FAKE=<файл JSON> — подмена мыши, тачпада, точности указателя и устройств для проверки (pct-core.ps1); замер — всегда настоящий, он только читает
param([switch]$Undo)
$ErrorActionPreference = 'SilentlyContinue'
$Host.UI.RawUI.WindowTitle = 'Мышь и тачпад'
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
. "$PSScriptRoot\pct-core.ps1"
$Fake = [bool]$env:PCT_MOUSE_FAKE; if ($Fake) { $env:PCT_ENERGY_FAKE = $env:PCT_MOUSE_FAKE }
$ru = [Globalization.CultureInfo]'ru-RU'
function Jr($t) { try { $d = PctDir 'reports'; [void][IO.Directory]::CreateDirectory($d); [IO.File]::AppendAllText("$d\mouse.log", "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $t`n", (New-Object Text.UTF8Encoding $false)) } catch {} }
function Enter { Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null }
function Yes($q) { $a = "$(Read-Host "$q (д/н)")".Trim(); Jr "вопрос: $q — ответ: $a"; $a -match '^(?i)(д|да|y|yes|l)' }
# Вопрос: заголовок и что делает — одна строка, совет — вторая, потом (д/н). Окно показывает две последние строки
function Ask2($head, $what, $rec, $q) { Write-Host "`n$head — $what" -ForegroundColor White; Write-Host $rec; Yes $q }
function Bw($b) { switch ($b) { 'radio' { 'радио 2,4 ГГц' } 'bt' { 'Bluetooth' } 'ps2' { 'встроенный, PS/2' } 'i2c' { 'встроенный' } 'virtual' { 'виртуальная' } default { 'USB' } } }
function Pn($p) { if ($p.Kind -eq 'touchpad') { "Тачпад$(if ($p.Ptp) { ' Precision' }) ($(Bw $p.Bus))" } else { "Мышь «$($p.N)» ($(Bw $p.Bus))" } }
function Lbl($x) { if ($x.Ptr) { Pn $x.Ptr } elseif ($x.Kind -eq 'touchpad') { 'Тачпад' } else { 'Мышь' } }
function Acc($a) { $(if (@($a).Count -eq 3 -and $a[2]) { 'вкл' } else { 'выкл' }) }
# Фирменные программы мыши: только сказать. Процессы и службы — по именам из их установщиков
function Vendors { if ($Fake) { return @((PctMsFake).vendors) }
  $m = [ordered]@{ 'Logitech G HUB' = @('lghub*'); 'Logitech Options+' = @('logioptionsplus*'); 'Razer Synapse' = @('Razer Synapse*', 'RazerCentral*', 'Razer*Service'); 'SteelSeries GG' = @('SteelSeriesGG*', 'SteelSeriesEngine*'); 'Corsair iCUE' = @('iCUE*', 'Corsair.Service*'); 'Bloody' = @('Bloody*') }
  foreach ($k in $m.Keys) { if ((Get-Service -Name $m[$k] -ErrorAction SilentlyContinue) -or (Get-Process -Name $m[$k] -ErrorAction SilentlyContinue)) { $k } } }

# Замер 5 с: окно-приёмник без показа (HWND_MESSAGE) с RIDEV_INPUTSINK — события мыши и тачпада (HID 0x0D/0x05) приходят и без фокуса. Время — Stopwatch в момент события, мкс
$RawCs = @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Diagnostics; using System.Text;
public static class PctRaw {
  delegate IntPtr WndProcD(IntPtr h, uint m, IntPtr w, IntPtr l);
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct WNDCLASSEX { public uint cbSize, style; public WndProcD proc; public int cls, wnd; public IntPtr inst, icon, cur, bg; public string menu, name; public IntPtr iconSm; }
  [StructLayout(LayoutKind.Sequential)] struct RID { public ushort page, usage; public uint flags; public IntPtr hwnd; }
  [StructLayout(LayoutKind.Sequential)] struct MSG { public IntPtr h; public uint m; public IntPtr w, l; public uint t; public int x, y; }
  [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern ushort RegisterClassEx(ref WNDCLASSEX c);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool UnregisterClass(string n, IntPtr i);
  [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr CreateWindowEx(uint ex, string cls, string name, uint st, int x, int y, int w, int h, IntPtr p, IntPtr menu, IntPtr inst, IntPtr par);
  [DllImport("user32.dll")] static extern bool DestroyWindow(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr DefWindowProc(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll", SetLastError = true)] static extern bool RegisterRawInputDevices(RID[] r, uint n, uint sz);
  [DllImport("user32.dll")] static extern uint GetRawInputData(IntPtr h, uint cmd, IntPtr data, ref uint sz, uint hsz);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern uint GetRawInputDeviceInfo(IntPtr h, uint cmd, StringBuilder data, ref uint sz);
  [DllImport("user32.dll")] static extern bool PeekMessage(out MSG m, IntPtr h, uint a, uint b, uint rm);
  [DllImport("user32.dll")] static extern IntPtr DispatchMessage(ref MSG m);
  [DllImport("user32.dll")] static extern uint MsgWaitForMultipleObjects(uint n, IntPtr[] hs, bool all, uint ms, uint mask);
  [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string n);
  static List<double> T; static List<int> D; static List<IntPtr> H; static List<int> K; static IntPtr buf; static long t0; static WndProcD keep;
  // Событие: время, мкс от начала, и номер источника. Источник: путь устройства, вид 0 — мышь, 1 — тачпад HID
  public static double[] Times; public static int[] Devs; public static string[] Names; public static int[] Kinds;
  static int Dev(IntPtr h, int k) { for (int i = 0; i < H.Count; i++) if (H[i] == h && K[i] == k) return i; H.Add(h); K.Add(k); return H.Count - 1; }
  static IntPtr Proc(IntPtr h, uint m, IntPtr w, IntPtr l) {
    if (m == 0x00FF) { long t = Stopwatch.GetTimestamp(); uint sz = 4096; uint hs = (uint)(8 + 2 * IntPtr.Size);
      if (GetRawInputData(l, 0x10000003, buf, ref sz, hs) != unchecked((uint)-1)) { int ty = Marshal.ReadInt32(buf); IntPtr dv = Marshal.ReadIntPtr(buf, 8); bool mv = ty == 2;
        if (ty == 0) mv = Marshal.ReadInt32(buf, (int)hs + 12) != 0 || Marshal.ReadInt32(buf, (int)hs + 16) != 0;
        if (mv) { T.Add((t - t0) * 1000000.0 / Stopwatch.Frequency); D.Add(Dev(dv, ty == 0 ? 0 : 1)); } } }
    return DefWindowProc(h, m, w, l); }
  public static string Measure(int ms) {
    T = new List<double>(); D = new List<int>(); H = new List<IntPtr>(); K = new List<int>(); buf = Marshal.AllocHGlobal(4096); keep = Proc;
    string cn = "PctRaw" + Process.GetCurrentProcess().Id; IntPtr inst = GetModuleHandle(null); IntPtr hw = IntPtr.Zero; RID[] r = null; uint rs = (uint)Marshal.SizeOf(typeof(RID));
    try {
      var wc = new WNDCLASSEX(); wc.cbSize = (uint)Marshal.SizeOf(typeof(WNDCLASSEX)); wc.proc = keep; wc.inst = inst; wc.name = cn;
      if (RegisterClassEx(ref wc) == 0) return "класс окна " + Marshal.GetLastWin32Error();
      hw = CreateWindowEx(0, cn, "", 0, 0, 0, 0, 0, new IntPtr(-3), IntPtr.Zero, inst, IntPtr.Zero); if (hw == IntPtr.Zero) return "окно " + Marshal.GetLastWin32Error();
      r = new RID[2]; r[0].page = 1; r[0].usage = 2; r[0].flags = 0x100; r[0].hwnd = hw; r[1].page = 0x0D; r[1].usage = 0x05; r[1].flags = 0x100; r[1].hwnd = hw;
      if (!RegisterRawInputDevices(r, 2, rs)) { r = new RID[] { r[0] }; if (!RegisterRawInputDevices(r, 1, rs)) { int e = Marshal.GetLastWin32Error(); r = null; return "Raw Input " + e; } }
      t0 = Stopwatch.GetTimestamp(); var sw = Stopwatch.StartNew(); MSG msg;
      while (sw.ElapsedMilliseconds < ms) { MsgWaitForMultipleObjects(0, null, false, (uint)Math.Max(1, ms - sw.ElapsedMilliseconds), 0x04FF);
        while (PeekMessage(out msg, IntPtr.Zero, 0, 0, 1)) DispatchMessage(ref msg); }
      return "";
    } finally { if (r != null) { for (int i = 0; i < r.Length; i++) { r[i].flags = 1; r[i].hwnd = IntPtr.Zero; } RegisterRawInputDevices(r, (uint)r.Length, rs); }
      if (hw != IntPtr.Zero) DestroyWindow(hw); UnregisterClass(cn, inst);
      Times = T.ToArray(); Devs = D.ToArray(); Kinds = K.ToArray(); Names = new string[H.Count];
      for (int i = 0; i < H.Count; i++) { uint n = 512; var sb = new StringBuilder(512); Names[i] = H[i] != IntPtr.Zero && GetRawInputDeviceInfo(H[i], 0x20000007, sb, ref n) != unchecked((uint)-1) ? sb.ToString() : ""; }
      Marshal.FreeHGlobal(buf); } }
}
'@
# Замер → группы PctMsGroups (пусто — не водили) или $null (замер не запустился, причина в журнале)
function Meas($when) { try { if (-not ('PctRaw' -as [type])) { Add-Type -TypeDefinition $RawCs -ErrorAction Stop }; $e = [PctRaw]::Measure(5000) } catch { $e = "$($_.Exception.Message)" }
  if ($e) { Jr "замер $when не запустился: $e"; return $null }
  $g = @(PctMsGroups ([PctRaw]::Times) ([PctRaw]::Devs) ([PctRaw]::Names) ([PctRaw]::Kinds) $Ptrs)
  Jr "замер ${when}: событий $([PctRaw]::Times.Count), источников $([PctRaw]::Names.Count); $(@($g | ForEach-Object { "$($_.Kind) $($_.Key) $($_.S.Hz) Гц ±$($_.S.Sp), пропусков $($_.S.Gap), окон $($_.S.Win)" }) -join '; ')"; , $g }
function Show($g) { foreach ($x in $g) { Write-Host "  $(Lbl $x): $($x.S.Hz) Гц, $(if ($x.S.Gap) { "пропусков: $($x.S.Gap)" } else { 'пропусков нет' })." -ForegroundColor White }
  # Медленно мышь сообщает реже своей частоты: большой разброс — замер неточный
  if (@($g | Where-Object { $_.S.Sp * 2 -gt $_.S.Hz }).Count) { Write-Host 'Разброс большой: мышь двигалась медленно или с остановками, и частота занижена. Для точного замера води быстрее, без остановок.' -ForegroundColor Yellow } }
function Sum($g) { if (-not $g) { return 'замер не получился' }; @($g | ForEach-Object { "$(if ($_.Kind -eq 'touchpad') { 'тачпад' } else { 'мышь' }) — $($_.S.Hz) Гц" }) -join ', ' }
function MeasAsk($head, $q) { if (-not (Ask2 $head '5 секунд считаю, как часто мышь и тачпад сообщают о движении и нет ли пропусков. Ничего не меняю.' 'Рекомендую: нажми «Да» и сразу води мышью или пальцем по тачпаду — быстро, кругами, без остановок.' $q)) { return $false }
  Write-Host 'Води мышью или пальцем по тачпаду 5 секунд — быстро, кругами.' -ForegroundColor Cyan; $true }

function DoUndo { Step -Plan 'Читаю, что было', 'Возвращаю как было'; Step 'Читаю, что было'; $b = PctMsBackup
  if (-not $b) { Step -Done 'возвращать нечего'; Write-Host 'Помощник не менял мышь — возвращать нечего.' -ForegroundColor Green; return }
  $n = [int](@($b.accel).Count -eq 3) + @($b.devices).Count; Step -Done "изменений: $n"
  Step 'Возвращаю как было' -Hint 'Пара секунд'; Step -Unsafe
  $r = PctMsUndo; Jr "откат: вернул $($r.Ok), не вернул: $($r.Bad -join '; ')"
  if ($r.Bad) { Step -Warn "вернул $($r.Ok), не вернул $($r.Bad.Count)"; Write-Host "Не вернул: $($r.Bad -join '; '). Нажми «Мышь и тачпад» ещё раз или позови помощь." -ForegroundColor Yellow }
  else { Step -Done "вернул всё: $($r.Ok)"; Write-Host "Вернул всё как было. Повышенная точность указателя: $(Acc @(PctMsAccel))." -ForegroundColor Green } }

Write-Host "`nМЫШЬ И ТАЧПАД`n" -ForegroundColor Cyan
Step -Safe
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $Fake -and -not $admin) { Step 'Проверяю права'; Step -Fail 'нет разрешения Windows' -Do 'Запусти «Мышь и тачпад» из Помощника и нажми «Да» в окне Windows.'; Write-Host 'Нужно разрешение Windows. Запусти «Мышь и тачпад» из Помощника.' -ForegroundColor Yellow; Enter; return }
$lk = PctLock 'mouse'; if (-not $lk) { Step 'Проверяю, не идёт ли настройка'; Step -Fail 'настройка уже идёт' -Do 'Дождись, пока она закончится.'; Write-Host 'Настройка мыши уже идёт. Дождись, пока она закончится.' -ForegroundColor Yellow; Enter; return }
try {
  Jr "начал: $(if ($Undo) { 'вернуть как было' } else { 'настройка' })$(if ($Fake) { ", подмена $env:PCT_MOUSE_FAKE" })"
  if ($Undo) { DoUndo; return }
  $D = PctEnDevice; $dev = $(if ($D.Laptop) { 'ноутбуку' } else { 'компьютеру' })
  $bk = PctMsBackup
  Step -Plan (@('Смотрю, что подключено') + @(if ($bk) { 'Спрашиваю, вернуть ли как было' }) + @('Замеряю мышь', 'Спрашиваю, что поменять', 'Сохраняю, как было, и меняю', 'Замеряю ещё раз'))
  # ---------- Смотрю ----------
  Step 'Смотрю, что подключено' -Hint 'Ничего не меняю'
  $Ptrs = @(PctMsDevices); $real = @($Ptrs | Where-Object { $_.Bus -ne 'virtual' }); $mice = @($real | Where-Object { $_.Kind -eq 'mouse' }); $tps = @($real | Where-Object { $_.Kind -eq 'touchpad' }); $vend = @(Vendors)
  if ($real) { Write-Host "Подключено к ${dev}:" -ForegroundColor White; foreach ($p in $real) { Write-Host "  $(Pn $p)" -ForegroundColor White } } else { Write-Host 'Не нашёл ни мыши, ни тачпада.' -ForegroundColor Yellow }
  if (@($Ptrs | Where-Object { $_.Bus -eq 'virtual' }).Count) { Write-Host 'Ещё есть виртуальная мышь фирменной программы — это не устройство, её не трогаю.' -ForegroundColor DarkGray }
  if ($tps -and -not @($tps | Where-Object { $_.Ptp }).Count) { Write-Host 'Тачпад не Precision: жесты и прокрутку настраивает программа его производителя.' -ForegroundColor DarkGray }
  if ($vend) { Write-Host "Нашёл программы мыши: $($vend -join ', '). Частоту опроса, чувствительность и кнопки меняй в них — Помощник их не трогает." -ForegroundColor Yellow }
  # В журнал — вид, шина и код VID&PID, без серийных номеров
  Jr "нашёл: $(@($Ptrs | ForEach-Object { "$($_.Kind) $($_.Bus)$(if ($_.Ptp) { ' precision' }) $(PctMsKey $_.Id)" }) -join '; '); программы: $($vend -join ', ')"
  $t = "мышь: $($mice.Count) · тачпад: $($tps.Count)"; if ($vend) { Step -Warn "$t · есть $($vend -join ', ')" } else { Step -Done $t }
  # Уже менял — сначала предложить вернуть
  if ($bk) { Step 'Спрашиваю, вернуть ли как было' -Hint 'Ответь на вопрос ниже'
    if (Ask2 "Помощник уже менял мышь ($(([datetime]$bk.created).ToString('d MMMM, HH:mm', $ru)))" 'могу вернуть всё как было.' 'Если нет — продолжу, а «Вернуть как было» потом всё равно вернёт к самому началу.' 'Вернуть всё как было?') { Step -Done 'вернуть'; DoUndo; return }
    Step -Done 'продолжаю настройку' }
  # ---------- Замер до ----------
  Step 'Замеряю мышь' -Hint 'Ответь на вопрос и води мышью 5 секунд'; $m0 = $null
  if (MeasAsk 'Замер мыши' 'Замерить?') { $m0 = Meas 'до'
    if ($null -eq $m0) { Step -Warn 'замер не запустился'; Write-Host 'Замер не запустился. Настройкам ниже это не мешает.' -ForegroundColor Yellow }
    elseif (-not $m0.Count) { Step -Warn 'замер не получился'; Write-Host 'Замер не получился: мышью не водили. Настройкам ниже это не мешает.' -ForegroundColor Yellow }
    else { Show $m0; if (@($m0 | Where-Object { $_.Kind -eq 'mouse' -and $_.S.Hz -lt 200 -and $_.S.Sp * 2 -le $_.S.Hz }).Count) { Write-Host 'Около 125 Гц — обычная мышь. Для игр лучше 500–1000 Гц: это меняется в программе мыши, если она умеет.' -ForegroundColor DarkGray }
      if (@($m0 | Where-Object { $_.S.Gap -ge 3 }).Count) { Write-Host 'Пропуск — пауза дольше трёх обычных. Немного пропусков бывает при медленном движении. Много при быстром — помеха радио или засыпает порт.' -ForegroundColor DarkGray }
      Step -Done (Sum $m0) } }
  else { Step -Done 'без замера' }
  # ---------- Спрашиваю ----------
  Step 'Спрашиваю, что поменять' -Hint 'Ответь на вопросы ниже'
  $a0 = @(PctMsAccel); $on = $a0.Count -eq 3 -and $a0[2] -ne 0; $pacc = $false
  if ($a0.Count -eq 3) { $pacc = Ask2 'Повышенная точность указателя' "сейчас $(Acc $a0). Windows ускоряет указатель: двигаешь быстро — он уходит дальше, медленно — точнее." 'По ситуации: для игр лучше выключить — рука привыкает к одному расстоянию. Для работы и тачпада удобнее включённая.' "$(if ($on) { 'Выключить' } else { 'Включить' }) повышенную точность указателя?" }
  else { Write-Host "`nПовышенную точность указателя не прочитал — её не трогаю." -ForegroundColor Yellow; Jr 'SPI_GETMOUSE не прочитал' }
  # Запрет отключения мыши и её приёмника — функциями «Энергосбережения» (9ao): устройства ввода с тем же VID&PID
  $mk = @($mice | Where-Object { $_.Bus -in 'usb', 'radio' } | ForEach-Object { PctMsKey $_.Id }); $ed = @(PctEnDevices | Where-Object { $_.K -eq 'input' -and $mk -contains (PctMsKey $_.Id) }); $edOn = @($ed | Where-Object { $_.On }); $pdev = $false
  $eb = @((PctEnBackup).devices | ForEach-Object { $_.id }) + @(Get-ChildItem (Split-Path (PctEnBackupPath)) -Filter 'energy-backup.*.done.json' -ErrorAction SilentlyContinue | ForEach-Object { try { ([IO.File]::ReadAllText($_.FullName) | ConvertFrom-Json).devices | ForEach-Object { $_.id } } catch {} })
  if ($edOn) { $dr = $(if ($D.Laptop) { 'По ситуации: от батареи заряд уйдёт чуть быстрее.' } else { 'Рекомендую запретить.' })
    $pdev = Ask2 'Отключение мыши для экономии' 'Windows может усыпить мышь или её приёмник: после паузы указатель на миг замирает, иногда мышь не просыпается.' "Сейчас разрешено: $($edOn.Count) из $($ed.Count). $dr" 'Запретить Windows отключать мышь?' }
  elseif ($ed) { Write-Host "`nОтключение мыши для экономии уже запрещено$(if (@($ed | Where-Object { $eb -contains $_.Id }).Count) { ' — это сделало «Энергосбережение»' }). Не меняю." -ForegroundColor DarkGray }
  elseif (@($mice | Where-Object { $_.Bus -eq 'bt' }).Count) { Write-Host "`nУ мыши Bluetooth Windows не даёт запретить отключение — здесь менять нечего." -ForegroundColor DarkGray }
  $nCh = [int]$pacc + [int]$pdev
  if (-not $nCh) { Step -Done 'ничего не меняю'; Write-Host "`nНичего не поменял." -ForegroundColor Green; Jr 'готово: ничего не менял'; return }
  Step -Done "поменять: $nCh"
  # ---------- Сохраняю и меняю, перечитываю ----------
  Step 'Сохраняю, как было, и меняю' -Hint 'Пара секунд'
  $b = PctMsBackupStart; Jr "бэкап: $(PctMsBackupPath)"; Step -Unsafe
  $ch = New-Object Collections.ArrayList; $bad = New-Object Collections.ArrayList
  if ($pacc) { if (@($b.accel).Count -ne 3) { $b.accel = $a0; PctMsBackupSave $b }; $nv = $(if ($on) { @(0, 0, 0) } else { @(6, 10, 1) })
    $okA = PctMsAccelSet $nv; $a1 = @(PctMsAccel); $r1 = @(PctMsAccelReg)
    if ($okA -and ($a1 -join ',') -eq ($nv -join ',') -and ($r1 -join ',') -eq ($nv -join ',')) { [void]$ch.Add("Повышенная точность указателя: $(Acc $a0) → $(Acc $a1)") }
    else { [void]$bad.Add('повышенная точность указателя'); Jr "точность указателя не записалась: Windows $($a1 -join ','), реестр $($r1 -join ',')" } }
  if ($pdev) { $okd = @(); foreach ($dv in $edOn) { PctMsRemember $b ([pscustomobject]@{ id = $dv.Id; name = $dv.N; old = $true })
      if (PctEnDeviceSet $dv.Id $false) { $okd += $dv.Id; Jr "устройство: запретил отключение — $($dv.N) $(PctMsKey $dv.Id)" } else { [void]$bad.Add("устройство $($dv.N)") } }
    # Перечитываю: Windows может вернуть разрешение (так бывает у части драйверов). В итоге — что стало на самом деле
    $rd = @(PctEnDevices); $st = @($edOn | Where-Object { $okd -contains $_.Id -and @($rd | Where-Object { $_.On } | ForEach-Object { $_.Id }) -contains $_.Id })
    $nd = @($edOn | Where-Object { @($rd | Where-Object { -not $_.On } | ForEach-Object { $_.Id }) -contains $_.Id }).Count
    foreach ($dv in @($edOn | Where-Object { $okd -contains $_.Id -and @($rd | ForEach-Object { $_.Id }) -notcontains $_.Id })) { [void]$bad.Add("устройство $($dv.N): не перечитал"); Jr "устройство: не перечитал — $($dv.N)" }
    if ($nd) { [void]$ch.Add("Отключение мыши для экономии: разрешено у $($edOn.Count) → запрещено у $nd") }
    if ($st.Count) { [void]$bad.Add("отключение мыши: Windows вернула разрешение у $($st.Count)"); Jr "устройство: Windows вернула разрешение — $(@($st | ForEach-Object { $_.N }) -join ', ')" } }
  foreach ($x in $ch) { Jr "изменил: $x" }
  if ($bad.Count) { Step -Warn "поменял: $($ch.Count), не вышло: $($bad.Count)" } else { Step -Done "поменял: $($ch.Count)" }
  # ---------- Замер после (если водили), было → стало ----------
  Step 'Замеряю ещё раз' -Hint 'Ответь на вопрос и води мышью 5 секунд'; $m1 = $null; $ask1 = $false
  # Шаг закрывает итог ниже: его видно на карточке
  if ($m0 -and $m0.Count) { if (MeasAsk 'Замер после' 'Замерить ещё раз?') { $ask1 = $true; $m1 = Meas 'после' } }
  Write-Host "`nБЫЛО → СТАЛО" -ForegroundColor Cyan; foreach ($x in $ch) { Write-Host "  $x" -ForegroundColor White }
  if ($bad.Count) { Write-Host "Не вышло: $($bad -join ', ')." -ForegroundColor Yellow }
  $lt = ''; $sh = @()
  if ($m0 -and $m1 -and $m1.Count) { foreach ($x in $m0) { $y = @($m1 | Where-Object { $_.Kind -eq $x.Kind -and $_.Key -eq $x.Key })[0]; if (-not $y) { continue }
      $sp = [math]::Max([math]::Max($x.S.Sp, $y.S.Sp), 1); $t = "$(Lbl $x): $($x.S.Hz) → $($y.S.Hz) Гц, пропусков $($x.S.Gap) → $($y.S.Gap)"; $lt += "$t; "; $sh += "$(if ($x.Kind -eq 'touchpad') { 'тачпад' } else { 'мышь' }) $($x.S.Hz) → $($y.S.Hz) Гц"; Write-Host "  $t" -ForegroundColor White
      if ([math]::Abs($y.S.Hz - $x.S.Hz) -le $sp) { Write-Host "  Разница меньше разброса (±$sp Гц) — частота та же. Так и должно быть: эти настройки меняют не частоту, а то, как указатель идёт за рукой и засыпает ли мышь." } }
    if (-not $lt) { Write-Host '  Мышь или тачпад после — не те, что до: сравнить нечего.' -ForegroundColor DarkGray } }
  elseif ($m0 -and $m0.Count -and $ask1) { Write-Host '  Замер после не получился — сравнить нечего.' -ForegroundColor DarkGray }
  Write-Host "`nВернуть как было: нажми «Мышь и тачпад» ещё раз и ответь «да» на первый вопрос." -ForegroundColor DarkGray
  Jr "готово: изменений $($ch.Count), не вышло: $($bad -join ', '); замер: $lt"
  $sum = "поменял: $($ch.Count)$(if ($sh) { " · $($sh -join ', ')" } elseif ($m0 -and $m0.Count -and $ask1) { " · замер после не получился" } elseif ($m0 -and $m0.Count) { " · $(Sum $m0), без замера после" } else { ' · без замера' })"
  if ($bad.Count) { Step -Warn "$sum · не вышло: $($bad.Count)" } else { Step -Done $sum }
} finally { PctUnlock $lk; Enter }
