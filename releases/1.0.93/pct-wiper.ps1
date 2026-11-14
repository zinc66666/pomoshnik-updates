# Удаление по дескрипторам: один код на «Большую уборку» (big-clean.ps1) и «Почистить мусор» (clean-junk.ps1). Подключение после pct-core.ps1: . "$PSScriptRoot\pct-wiper.ps1". При подключении только задаёт функции и $keepName.
# От инструмента жду: $Fake (стенд PCT_CLEAN_FAKE), $Elevated (процесс с повышением), Jr (журнал инструмента).
# Внутри групп не трогаю обход (zapret), Happ и временные файлы Помощника (pct-*: обновление, номер AnyDesk)
$keepName = '(?i)zapret|^happ$|^pct-|^pomoshnik$|^pc-tweaks'

# Удаление по дескрипторам (как PctAcl.Walk в установщике): каждое имя открываю относительно уже открытой папки, за ссылку не иду. Подмена папки посреди обхода не уводит: открытая папка та же
function WipeInit { if ('PctWipe' -as [type]) { return }
  # С повышением компилятор пишет DLL во временную папку, а %TEMP% — от её процессов: на это время папка только для администраторов
  $own = $null; if ($Elevated -and -not $Fake) { $own = "$([Environment]::GetFolderPath('Windows'))\Temp\pct-$([guid]::NewGuid().ToString('N'))"; $s = New-Object Security.AccessControl.DirectorySecurity; $s.SetSecurityDescriptorSddlForm('O:BAD:P(A;OICI;FA;;;BA)(A;OICI;FA;;;SY)'); [void][IO.Directory]::CreateDirectory($own, $s); $env:TEMP = $own; $env:TMP = $own }
  try { Add-Type -ErrorAction Stop -TypeDefinition @'
using System; using System.Collections.Generic; using System.ComponentModel; using System.Runtime.InteropServices; using System.Text; using System.Text.RegularExpressions; using Microsoft.Win32.SafeHandles;
public static class PctWipe {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern SafeFileHandle CreateFileW(string n, uint a, uint s, IntPtr sa, uint d, uint f, IntPtr t);
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetFileInformationByHandle(SafeFileHandle h, [Out] uint[] i);
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetFileInformationByHandleEx(SafeFileHandle h, int c, byte[] b, int n);
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetFileInformationByHandle(SafeFileHandle h, int c, byte[] b, int n);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern int GetFinalPathNameByHandleW(SafeFileHandle h, StringBuilder b, int n, int f);
  [DllImport("ntdll.dll")] static extern int NtCreateFile(out SafeFileHandle h, uint a, ref Oa o, out Iosb s, IntPtr al, uint fa, uint sh, uint d, uint op, IntPtr ea, uint el);
  [DllImport("ntdll.dll")] static extern int RtlNtStatusToDosError(int s);
  [StructLayout(LayoutKind.Sequential)] struct Oa { public int Len; public IntPtr Root, Name; public uint Attr; public IntPtr Sd, Qos; }
  [StructLayout(LayoutKind.Sequential)] struct Us { public ushort Len, Max; public IntPtr Buf; }
  [StructLayout(LayoutKind.Sequential)] struct Iosb { public IntPtr St, Info; }
  public static long Freed; public static int Busy; public static List<string> Log = new List<string>();
  static Regex keep, pat; static long cut; static Action<string> hook;
  const uint RdAttr = 0x80, Del = 0x10080, Lst = 0x81, Sync = 0x100000;
  class Fail : Exception { public int E; public Fail(string p, int e) : base(p + ": " + new Win32Exception(e).Message) { E = e; } }
  // Имя относительно открытой папки (пустое имя — тот же объект заново): за ссылку не иду. Имени уже нет — null
  static SafeFileHandle At(SafeFileHandle d, string n, uint a, string p) { Us u = new Us(); u.Len = u.Max = (ushort)(n.Length * 2); u.Buf = Marshal.StringToHGlobalUni(n); IntPtr pu = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(Us)));
    try { Marshal.StructureToPtr(u, pu, false); Oa o = new Oa(); o.Len = Marshal.SizeOf(typeof(Oa)); o.Root = d.DangerousGetHandle(); o.Name = pu; o.Attr = 0x40; SafeFileHandle h; Iosb s;
      int st = NtCreateFile(out h, a | Sync, ref o, out s, IntPtr.Zero, 0, 7, 1, 0x204020, IntPtr.Zero, 0); if (st >= 0) return h;
      int e = RtlNtStatusToDosError(st); if (e == 2 || e == 3) return null; throw new Fail(p, e); }
    finally { Marshal.FreeHGlobal(pu); Marshal.FreeHGlobal(u.Buf); } }
  static uint[] Info(SafeFileHandle h, string p) { uint[] i = new uint[13]; if (!GetFileInformationByHandle(h, i)) throw new Fail(p, Marshal.GetLastWin32Error()); return i; }
  static List<string> Names(SafeFileHandle d, string p) { List<string> r = new List<string>(); byte[] b = new byte[65536]; int c = 15;
    while (GetFileInformationByHandleEx(d, c, b, b.Length)) { c = 14; for (int o = 0; ; ) { int nx = BitConverter.ToInt32(b, o); string n = Encoding.Unicode.GetString(b, o + 68, BitConverter.ToInt32(b, o + 60)); if (n != "." && n != "..") r.Add(n); if (nx == 0) break; o += nx; } }
    int e = Marshal.GetLastWin32Error(); if (e != 18) throw new Fail(p, e); return r; }
  static long Mtime(uint[] i) { return ((long)i[6] << 32) | i[5]; }
  // Удаление по дескриптору: имя исчезает сразу, «только чтение» не мешает; старая файловая система — обычным способом
  static bool Kill(SafeFileHandle f) { if (SetFileInformationByHandle(f, 21, BitConverter.GetBytes(0x13), 4)) return true; int e = Marshal.GetLastWin32Error(); return (e == 87 || e == 50 || e == 1) && SetFileInformationByHandle(f, 4, new byte[] { 1 }, 1); }
  // p — путь до корня (только начало обхода, последнее имя — без захода за ссылку), сверяю, куда он привёл. keepRx — имена, которые не трогаю; cutUtc — только старше (FILETIME, 0 — все); only — только такие файлы прямо в корне
  public static void Run(string p, string keepRx, long cutUtc, string only, Action<string> h) { Freed = 0; Busy = 0; Log = new List<string>(); keep = new Regex(keepRx); pat = string.IsNullOrEmpty(only) ? null : new Regex(only, RegexOptions.IgnoreCase); cut = cutUtc; hook = h;
    // Корень открываю без права удаления: текущая папка другой программы (она не разрешает удаление) не мешает обойти его. Файл-корень — на удаление заново, по дескриптору: тот же объект
    using (SafeFileHandle f = CreateFileW(p, RdAttr | Sync, 7, IntPtr.Zero, 3, 0x02200000, IntPtr.Zero)) { if (f.IsInvalid) { int e = Marshal.GetLastWin32Error(); if (e != 2 && e != 3) Log.Add(new Fail(p, e).Message); if (e == 5 || e == 32) Busy++; return; }
      StringBuilder sb = new StringBuilder(32768); int n = GetFinalPathNameByHandleW(f, sb, sb.Capacity, 0); if (n <= 0 || n >= sb.Capacity || !string.Equals(sb.ToString(), @"\\?\" + p, StringComparison.OrdinalIgnoreCase)) { Log.Add(p + ": путь ведёт в другое место — не трогаю"); return; }
      uint[] i = Info(f, p); if ((i[0] & 0x400) != 0) { Log.Add(p + ": ссылка — не трогаю"); return; }
      if ((i[0] & 0x10) != 0) Walk(f, p, true); else try { using (SafeFileHandle g = At(f, "", Del, p)) { if (g != null) Gone(g, i); } } catch (Fail x) { Log.Add(x.Message); if (x.E == 5 || x.E == 32) Busy++; } } }
  static void Gone(SafeFileHandle g, uint[] i) { bool link = (i[0] & 0x400) != 0; if (!link && cut != 0 && Mtime(i) >= cut) return; if (Kill(g)) { if (!link && i[10] <= 1) Freed += ((long)i[8] << 32) | i[9]; } else Busy++; }
  // Содержимое папки: до 3 проходов — имя, подменённое посреди обхода (новая ссылка), найдётся следующим проходом. Корень остаётся
  static void Walk(SafeFileHandle f, string p, bool top) { string leaf = p.Substring(p.LastIndexOf('\\') + 1);
    using (SafeFileHandle d = At(f, "", Lst, p)) { if (d == null) return; if (hook != null) hook(p); HashSet<string> seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
      for (int pass = 0; pass < 3; pass++) { bool any = false; foreach (string n in Names(d, p)) { if (!seen.Add(n)) continue; any = true; string c = p + "\\" + n;
          if (keep.IsMatch(n)) { Log.Add("не тронул: " + c); continue; } if (n.Equals("desktop.ini", StringComparison.OrdinalIgnoreCase) && leaf.StartsWith("S-1-5-")) continue; if (pat != null && !(top && pat.IsMatch(n))) continue;
          try { One(d, n, c); } catch (Fail x) { if (x.E == 5 || x.E == 32) Busy++; else Log.Add(x.Message); } }
        if (!any) break; } } }
  // Сначала смотрю, что это (без права удаления: занятая папка всё равно обойдётся), потом открываю заново на удаление и проверяю ещё раз: могли подменить. Непустая папка сама не удалится
  static void One(SafeFileHandle d, string n, string c) { uint[] i; bool dir; long mt;
    using (SafeFileHandle g = At(d, n, RdAttr, c)) { if (g == null) return; i = Info(g, c); dir = (i[0] & 0x10) != 0 && (i[0] & 0x400) == 0; mt = Mtime(i); if (dir) Walk(g, c, false); }
    using (SafeFileHandle g = At(d, n, Del, c)) { if (g == null) return; i = Info(g, c); if ((i[0] & 0x10) != 0 && (i[0] & 0x400) == 0) { if (dir && (cut == 0 || mt < cut)) Kill(g); return; } Gone(g, i); } }
}
'@ } catch { Jr "обход по дескрипторам не собрался: $($_.Exception.Message)"; throw } finally { if ($own) { try { [IO.Directory]::Delete($own, $true) } catch {} } } }
# Стенд: посреди обхода папка становится точкой соединения на приманку
function RaceHook { if (-not $Fake -or "$env:PCT_CLEAN_RACE" -notmatch '^(.+)\|(.+)$') { return $null }; $script:RaceP = $Matches[1]; $script:RaceT = $Matches[2]
  [Action[string]]{ param($x) if ($x -eq $script:RaceP -and $script:RaceP) { $script:RaceP = ''; [IO.Directory]::Move($x, "$x-old"); $null = & cmd.exe /c mklink /J "`"$x`"" "`"$script:RaceT`"" 2>&1; Jr "стенд: подмена $x" } } }
