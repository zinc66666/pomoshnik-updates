# Помощник — прототип DS0 (облик «живая станция», макет v5): сцена маяка, стеклянная шторка, главный экран и общий экран хода.
# PCT_DEMO=1 — показ по шагам на данных-образце (PCT_DEMO_OUT=ok|deny|fail, F2 — сменить исход); без него карточки работают как в main.
# Разделы — сетка стеклянных карточек по группам, «Сторожа» — строки с переключателем и панелью, «Позвать помощь» — окно с номером AnyDesk (DS0b). При ошибке загрузки окна открывается helper-menu.ps1.
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
$Hd = PctDir 'helpers'; $Gd = PctDir 'guard'; $RunDir = PctDir 'run'
$ps = "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"; $con = "$env:windir\System32\conhost.exe"
$Tools = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Мои инструменты'
try {
if (-not (Test-Path function:PctDir)) { throw 'не загрузился pct-core.ps1' }
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -Namespace PCT -Name Sys -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
[StructLayout(LayoutKind.Sequential)] public struct MEM { public uint len; public uint load; public ulong tot; public ulong av; public ulong tp; public ulong ap; public ulong tv; public ulong avv; public ulong ext; }
[DllImport("kernel32.dll")] public static extern bool GlobalMemoryStatusEx(ref MEM m);
public static uint MemLoad() { MEM m = new MEM(); m.len = (uint)System.Runtime.InteropServices.Marshal.SizeOf(typeof(MEM)); GlobalMemoryStatusEx(ref m); return m.load; }
[DllImport("ntdll.dll")] static extern int NtQuerySystemInformation(int c, long[] b, int len, out int ret);
// Память как в Диспетчере задач: всего, занято, кэш (резервный + изменённый список), свободно. Списков нет (класс 80) — кэш -1, свободно = доступно
public static long[] Mem() { MEM m = new MEM(); m.len = (uint)Marshal.SizeOf(typeof(MEM)); GlobalMemoryStatusEx(ref m); long tot = (long)m.tot, av = (long)m.av, pg = System.Environment.SystemPageSize; long[] b = new long[32]; int r;
  if (NtQuerySystemInformation(80, b, 256, out r) != 0 || r < 176) { return new long[] { tot, tot - av, -1, av }; }
  long sb = 0; for (int i = 5; i < 13; i++) { sb += b[i]; } long md = (b[2] + b[3]) * pg; return new long[] { tot, tot - av - md, sb * pg + md, (b[0] + b[1]) * pg }; }
[StructLayout(LayoutKind.Sequential)] public struct RB { public uint cb; public long size; public long n; }
[DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SHQueryRecycleBin(string root, ref RB r);
static long Dir(System.IO.DirectoryInfo d) { long n = 0; try { foreach (var f in d.EnumerateFiles()) { n += f.Length; }
  foreach (var s in d.EnumerateDirectories()) { if ((s.Attributes & System.IO.FileAttributes.ReparsePoint) == 0) { n += Dir(s); } } } catch { } return n; }
// Мусор: %TEMP% + Корзина диска, в потоке пула — окно не ждёт
public static System.Threading.Tasks.Task<long> Junk(string temp, string root) { return System.Threading.Tasks.Task.Run(() => { long n = Dir(new System.IO.DirectoryInfo(temp));
  RB r = new RB(); r.cb = (uint)Marshal.SizeOf(typeof(RB)); if (SHQueryRecycleBin(root, ref r) == 0) { n += r.size; } return n; }); }
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(System.IntPtr h, int a, ref int v, int s);
[DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int p);
'@
# Один экземпляр: второй запуск будит первое окно и выходит
if (-not $env:PCT_RENDER) { $new = $false; $script:mtx = New-Object Threading.Mutex($false, 'Local\PCT-Helper-App', [ref]$new)
  $script:wake = New-Object Threading.EventWaitHandle($false, 'AutoReset', 'Local\PCT-Helper-App-Show')
  if (-not $new) { [void][PCT.Sys]::AllowSetForegroundWindow(-1); [void]$script:wake.Set(); return } }
function MtxFree { if ($script:mtx) { $script:mtx.Dispose(); $script:mtx = $null } }
New-Item -ItemType Directory -Force $RunDir | Out-Null
Get-ChildItem $RunDir -File | Where-Object LastWriteTime -lt (Get-Date).AddDays(-2) | Remove-Item -Force

# Ход работы: одинаковый блок для главной (H) и экрана хода (A)
$runBlock = @'
<Border x:Name="@Sum" Visibility="Collapsed" CornerRadius="12" Background="{StaticResource Glass}" BorderBrush="{StaticResource Edge}" BorderThickness="1" Padding="18,14" Margin="0,0,0,10"/>
<Border x:Name="@Box" CornerRadius="12" Background="{StaticResource Glass}" BorderBrush="{StaticResource Edge}" BorderThickness="1" Padding="0,14,0,10">
  <StackPanel><Grid Margin="18,0,18,6"><TextBlock x:Name="@Head" Text="Что сейчас делаю" FontSize="15" FontWeight="SemiBold"/><TextBlock x:Name="@Clock" FontSize="13" Foreground="{StaticResource Dim}" HorizontalAlignment="Right" VerticalAlignment="Bottom"/></Grid><StackPanel x:Name="@List"/></StackPanel>
</Border>
<StackPanel x:Name="@After"/>
<!--CTL-->
<Button x:Name="@LogT" Style="{StaticResource Link}" Margin="0,10,0,0" HorizontalAlignment="Left"><StackPanel Orientation="Horizontal"><TextBlock Text="&#xE76C;" FontFamily="{StaticResource Ico}" FontSize="11" VerticalAlignment="Center" Margin="0,0,6,0" RenderTransformOrigin="0.5,0.5"><TextBlock.RenderTransform><RotateTransform x:Name="@LogR"/></TextBlock.RenderTransform></TextBlock><TextBlock Text="Подробности для помощника" FontSize="13"/></StackPanel></Button>
<Border x:Name="@LogBox" Visibility="Collapsed" CornerRadius="12" Background="{StaticResource Glass}" BorderBrush="{StaticResource Edge}" BorderThickness="1" Padding="14,10" Margin="0,6,0,0"><ScrollViewer x:Name="@LogSv" Focusable="False" MaxHeight="84" VerticalScrollBarVisibility="Hidden"><StackPanel x:Name="@Log" TextElement.FontFamily="{StaticResource Mono}" TextElement.FontSize="12"/></ScrollViewer></Border>
'@

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Помощник" Width="980" Height="700" WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize" WindowStyle="SingleBorderWindow"
        FontFamily="Segoe UI Variable Text, Segoe UI" UseLayoutRounding="True" Background="{DynamicResource Bg}" Foreground="{DynamicResource Text}">
  <WindowChrome.WindowChrome><WindowChrome CaptionHeight="0" ResizeBorderThickness="0" GlassFrameThickness="0,0,0,1" UseAeroCaptionButtons="False"/></WindowChrome.WindowChrome>
  <Window.Resources>
    <!-- Токены облика (DESIGN.md §2–§5). Цвета интерфейса — только отсюда; цвета сцены маяка — в самой сцене -->
    <SolidColorBrush x:Key="Bg" Color="#000000"/>
    <SolidColorBrush x:Key="Text" Color="#F3EDE2"/>
    <SolidColorBrush x:Key="Dim" Color="#9AA39D"/>
    <SolidColorBrush x:Key="Acc" Color="#2FD39A"/>
    <SolidColorBrush x:Key="Warm" Color="#F0D888"/>
    <SolidColorBrush x:Key="Err" Color="#FF5A5A"/>
    <SolidColorBrush x:Key="Ink" Color="#04140E"/>
    <SolidColorBrush x:Key="InkTrack" Color="#2604140E"/>
    <SolidColorBrush x:Key="Glass" Color="#BD14181A"/>
    <SolidColorBrush x:Key="GlassHi" Color="#F214181A"/>
    <SolidColorBrush x:Key="Solid" Color="#14181A"/>
    <SolidColorBrush x:Key="Edge" Color="#2ECCE8D5"/>
    <SolidColorBrush x:Key="Line" Color="#14CCE8D5"/>
    <SolidColorBrush x:Key="Hover" Color="#1ACCE8D5"/>
    <SolidColorBrush x:Key="GBg" Color="#14CCE8D5"/>
    <SolidColorBrush x:Key="GBgHi" Color="#29CCE8D5"/>
    <SolidColorBrush x:Key="AccSoft" Color="#1F2FD39A"/>
    <SolidColorBrush x:Key="AccEdge" Color="#992FD39A"/>
    <SolidColorBrush x:Key="AccHover" Color="#732FD39A"/>
    <SolidColorBrush x:Key="WarmSoft" Color="#14F0D888"/>
    <SolidColorBrush x:Key="WarmEdge" Color="#73F0D888"/>
    <SolidColorBrush x:Key="WarmTrack" Color="#40F0D888"/>
    <SolidColorBrush x:Key="ErrSoft" Color="#24FF5A5A"/>
    <SolidColorBrush x:Key="ErrEdge" Color="#59FF5A5A"/>
    <SolidColorBrush x:Key="DimSoft" Color="#249AA39D"/>
    <SolidColorBrush x:Key="DimTrack" Color="#339AA39D"/>
    <SolidColorBrush x:Key="SwOff" Color="#409AA39D"/>
    <SolidColorBrush x:Key="RowHover" Color="#0DCCE8D5"/>
    <SolidColorBrush x:Key="Field" Color="#101415"/>
    <SolidColorBrush x:Key="Scrim" Color="#80000000"/>
    <SolidColorBrush x:Key="CloseHover" Color="#C42B1C"/>
    <Color x:Key="GlowC">#292FD39A</Color>
    <Color x:Key="GlowC0">#002FD39A</Color>
    <LinearGradientBrush x:Key="PrimaryFill" StartPoint="0,0" EndPoint="0,1"><GradientStop Color="#8FF5CF" Offset="0"/><GradientStop Color="#2FD39A" Offset="1"/></LinearGradientBrush>
    <LinearGradientBrush x:Key="NowRow" StartPoint="0,0" EndPoint="1,0"><GradientStop Color="#14F0D888" Offset="0"/><GradientStop Color="#00F0D888" Offset="1"/></LinearGradientBrush>
    <FontFamily x:Key="Ico">Segoe Fluent Icons, Segoe MDL2 Assets</FontFamily>
    <FontFamily x:Key="Hand">Ink Free</FontFamily>
    <FontFamily x:Key="Mono">Cascadia Mono, Consolas</FontFamily>

    <!-- Рамка фокуса с клавиатуры -->
    <Style x:Key="Focus"><Setter Property="Control.Template"><Setter.Value><ControlTemplate><Rectangle Margin="-3" RadiusX="10" RadiusY="10" Stroke="{StaticResource Acc}" StrokeThickness="2"/></ControlTemplate></Setter.Value></Setter></Style>
    <!-- Прозрачная кнопка: пункты шторки, ссылки, кнопки окна. Подсветка при наведении — из BorderBrush -->
    <Style x:Key="Plain" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Dim}"/><Setter Property="Background" Value="Transparent"/><Setter Property="BorderBrush" Value="Transparent"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{StaticResource Focus}"/><Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"/></Border>
        <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="{StaticResource Text}"/><Setter TargetName="b" Property="Background" Value="{Binding BorderBrush, RelativeSource={RelativeSource TemplatedParent}}"/></Trigger></ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="Link" TargetType="Button" BasedOn="{StaticResource Plain}"><Setter Property="Foreground" Value="{StaticResource Acc}"/></Style>
    <!-- Стеклянная кнопка (все, кроме главной) -->
    <Style x:Key="GBtn" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Text}"/><Setter Property="FontSize" Value="13"/><Setter Property="Cursor" Value="Hand"/><Setter Property="FocusVisualStyle" Value="{StaticResource Focus}"/>
      <Setter Property="Padding" Value="14,7"/><Setter Property="Margin" Value="0,0,8,0"/><Setter Property="Background" Value="{StaticResource GBg}"/><Setter Property="BorderBrush" Value="{StaticResource Edge}"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="b" CornerRadius="8" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
        <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{StaticResource GBgHi}"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.45"/></Trigger></ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="GBtnAcc" TargetType="Button" BasedOn="{StaticResource GBtn}"><Setter Property="Foreground" Value="{StaticResource Acc}"/><Setter Property="BorderBrush" Value="{StaticResource AccEdge}"/></Style>
    <!-- Карточка-выбор: стекло, грань светлеет при наведении -->
    <Style x:Key="DCard" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Text}"/><Setter Property="Cursor" Value="Hand"/><Setter Property="FocusVisualStyle" Value="{StaticResource Focus}"/><Setter Property="Margin" Value="5"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/><Setter Property="VerticalContentAlignment" Value="Stretch"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="bd" CornerRadius="12" Background="{StaticResource Glass}" BorderBrush="{StaticResource Edge}" BorderThickness="1"><ContentPresenter/></Border>
        <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="BorderBrush" Value="{StaticResource AccHover}"/></Trigger></ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <!-- PrimaryButton (§5): одна на экран. beam — рамка во время работы, shine — блик, shadow — неподвижная тень -->
    <Style x:Key="PrimaryButton" TargetType="Button">
      <Setter Property="Cursor" Value="Hand"/><Setter Property="FocusVisualStyle" Value="{StaticResource Focus}"/><Setter Property="Foreground" Value="{StaticResource Ink}"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Grid>
          <Border x:Name="beam" CornerRadius="16" Margin="-2" BorderThickness="2" Opacity="0">
            <Border.BorderBrush><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><LinearGradientBrush.RelativeTransform><RotateTransform CenterX="0.5" CenterY="0.5"/></LinearGradientBrush.RelativeTransform>
              <GradientStop Color="#00F0D888" Offset="0.25"/><GradientStop Color="#F0D888" Offset="0.45"/><GradientStop Color="#8FF5CF" Offset="0.55"/><GradientStop Color="#008FF5CF" Offset="0.75"/></LinearGradientBrush></Border.BorderBrush></Border>
          <Border x:Name="shadow" CornerRadius="14" Background="{StaticResource Acc}"><Border.Effect><DropShadowEffect BlurRadius="22" ShadowDepth="0" Color="#2FD39A" Opacity="0.28"/></Border.Effect></Border>
          <Border CornerRadius="14" Background="{StaticResource PrimaryFill}"/>
          <Grid x:Name="inner">
            <ContentPresenter Margin="20,15" HorizontalAlignment="Left"/>
            <Rectangle x:Name="shine" Width="80" HorizontalAlignment="Left" Margin="-120,0,0,0" IsHitTestVisible="False">
              <Rectangle.Fill><LinearGradientBrush StartPoint="0,0" EndPoint="1,0"><GradientStop Color="#00FFFFFF" Offset="0"/><GradientStop Color="#8CFFFFFF" Offset="0.5"/><GradientStop Color="#00FFFFFF" Offset="1"/></LinearGradientBrush></Rectangle.Fill>
              <Rectangle.RenderTransform><TransformGroup><SkewTransform AngleX="-18"/><TranslateTransform/></TransformGroup></Rectangle.RenderTransform></Rectangle>
          </Grid>
        </Grid>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <!-- Строка списка (сторожа, переключатель): разделитель сверху, подсветка при наведении -->
    <Style x:Key="Row" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Text}"/><Setter Property="Cursor" Value="Hand"/><Setter Property="FocusVisualStyle" Value="{StaticResource Focus}"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Padding" Value="16,7"/><Setter Property="Background" Value="Transparent"/><Setter Property="BorderBrush" Value="{StaticResource Line}"/><Setter Property="BorderThickness" Value="0,1,0,0"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Padding="{TemplateBinding Padding}"><ContentPresenter/></Border>
        <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{StaticResource RowHover}"/></Trigger></ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
  </Window.Resources>

  <Grid x:Name="Root" ClipToBounds="True" KeyboardNavigation.TabNavigation="Local">
    <!-- Сцена: маяк у ночного моря, один слой фигур, без картинок. Свои цвета — только до «конец сцены» (проверка DS1 в check.ps1) -->
    <Canvas x:Name="Scene" Width="980" Height="700" HorizontalAlignment="Left" VerticalAlignment="Top" IsHitTestVisible="False">
      <Rectangle Width="980" Height="700" Fill="#03060A"/>
      <Rectangle Canvas.Top="330" Width="980" Height="125" Fill="#050A10"/>
      <Rectangle Canvas.Top="400" Width="980" Height="55" Fill="#07101A"/>
      <Canvas x:Name="Stars"/>
      <Ellipse Canvas.Left="865" Canvas.Top="52" Width="80" Height="80" Fill="#F0D888" Opacity="0.03"/>
      <Ellipse Canvas.Left="883" Canvas.Top="70" Width="44" Height="44" Fill="#F0D888" Opacity="0.92"/>
      <Ellipse Canvas.Left="894" Canvas.Top="65" Width="40" Height="40" Fill="#03060A"/>
      <Path Data="M220,455 Q300,438 360,446 Q420,432 470,448 L520,455 Z M560,455 Q610,446 660,450 L690,455 Z" Fill="#081018"/>
      <Rectangle Canvas.Top="455" Width="980" Height="245" Fill="#04121A"/>
      <Rectangle Canvas.Top="455" Width="980" Height="1" Fill="#2FD39A" Opacity="0.18"/>
      <Rectangle Canvas.Left="890" Canvas.Top="466" Width="30" Height="2" Fill="#F0D888" Opacity="0.35"/><Rectangle Canvas.Left="884" Canvas.Top="480" Width="40" Height="2" Fill="#F0D888" Opacity="0.28"/>
      <Rectangle Canvas.Left="894" Canvas.Top="496" Width="24" Height="2" Fill="#F0D888" Opacity="0.22"/><Rectangle Canvas.Left="880" Canvas.Top="514" Width="46" Height="2" Fill="#F0D888" Opacity="0.16"/>
      <Rectangle Canvas.Left="890" Canvas.Top="536" Width="30" Height="2" Fill="#F0D888" Opacity="0.12"/><Rectangle Canvas.Left="876" Canvas.Top="562" Width="52" Height="2" Fill="#F0D888" Opacity="0.08"/>
      <Path Stroke="#2FD39A" StrokeThickness="1.4" Opacity="0.13" Data="M250,490 q30,-5 60,0 t60,0 t60,0 M430,530 q30,-5 60,0 t60,0 t60,0 t60,0 M270,590 q30,-5 60,0 t60,0 t60,0 M540,640 q30,-5 60,0 t60,0 M590,485 q30,-5 60,0 t60,0 M330,660 q30,-5 60,0 t60,0"/>
      <Canvas x:Name="Beam" Opacity="0"><Canvas.RenderTransform><RotateTransform x:Name="BeamRot" CenterX="842" CenterY="232"/></Canvas.RenderTransform>
        <Polygon Points="842,232 0,140 0,324" Fill="#F0D888" Opacity="0.045"/><Polygon Points="842,232 0,190 0,274" Fill="#F0D888" Opacity="0.06"/><Polygon Points="842,232 0,218 0,246" Fill="#F0D888" Opacity="0.07"/></Canvas>
      <Path Data="M700,470 Q740,428 790,420 Q840,408 900,414 Q950,418 980,436 L980,500 L690,500 Z" Fill="#0B1216"/>
      <Path Data="M760,470 Q800,440 850,436 Q900,432 940,450 L960,480 L740,486 Z" Fill="#0F181D"/>
      <Path Data="M690,500 L980,500 L980,470 Q930,492 860,488 Q780,486 690,500 Z" Fill="#081014"/>
      <Rectangle Canvas.Left="770" Canvas.Top="510" Width="150" Height="2" Fill="#F0D888" Opacity="0.12"/><Rectangle Canvas.Left="800" Canvas.Top="524" Width="90" Height="2" Fill="#F0D888" Opacity="0.08"/><Rectangle Canvas.Left="820" Canvas.Top="540" Width="50" Height="2" Fill="#F0D888" Opacity="0.06"/>
      <Polygon Points="820,440 864,440 855,262 829,262" Fill="#E9E2D3"/><Polygon Points="842,440 864,440 855,262 842,262" Fill="#C9C1B1"/>
      <Polygon Points="823,404 861,404 859,380 825,380" Fill="#C64B47"/><Polygon Points="842,404 861,404 859,380 842,380" Fill="#A63D3A"/>
      <Polygon Points="826,336 858,336 857,312 827,312" Fill="#C64B47"/><Polygon Points="842,336 858,336 857,312 842,312" Fill="#A63D3A"/>
      <Rectangle Canvas.Left="838" Canvas.Top="290" Width="8" Height="10" RadiusX="4" RadiusY="4" Fill="#1A2226"/><Rectangle Canvas.Left="838" Canvas.Top="350" Width="8" Height="10" RadiusX="4" RadiusY="4" Fill="#1A2226"/>
      <Path Data="M835,440 V424 A7,7 0 0 1 849,424 V440 Z" Fill="#1A2226"/>
      <Rectangle Canvas.Left="814" Canvas.Top="254" Width="56" Height="8" RadiusX="2" RadiusY="2" Fill="#1A2226"/>
      <Path Stroke="#1A2226" StrokeThickness="1.5" Data="M816,254 L816,246 M868,254 L868,246 M816,246 L868,246"/>
      <Canvas x:Name="Glow" Opacity="0.6"><Ellipse Canvas.Left="796" Canvas.Top="186" Width="92" Height="92" Fill="#F0D888" Opacity="0.035"/><Ellipse Canvas.Left="814" Canvas.Top="204" Width="56" Height="56" Fill="#F0D888" Opacity="0.06"/></Canvas>
      <Rectangle Canvas.Left="828" Canvas.Top="220" Width="28" Height="26" Fill="#F0D888"/>
      <Path Stroke="#1A2226" StrokeThickness="1.6" Data="M837,220 L837,246 M847,220 L847,246"/>
      <Path Data="M822,221 L842,200 L862,221 Z" Fill="#1A2226"/>
      <Ellipse Canvas.Left="839.5" Canvas.Top="195.5" Width="5" Height="5" Fill="#1A2226"/>
    </Canvas>
    <!-- конец сцены -->

    <!-- Верх: живые показатели и кнопки окна -->
    <Grid x:Name="TopBar" Height="46" VerticalAlignment="Top" Margin="212,0,0,0" Background="Transparent" KeyboardNavigation.TabNavigation="Local" KeyboardNavigation.TabIndex="5">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,8,8,0">
        <StackPanel Orientation="Horizontal" Margin="0,0,14,0" VerticalAlignment="Center"><TextBlock Text="Процессор" FontSize="12" Foreground="{StaticResource Dim}" VerticalAlignment="Center" Margin="0,0,7,0"/>
          <Grid Width="56" Height="5" VerticalAlignment="Center"><Border CornerRadius="3" Background="{StaticResource DimTrack}"/><Border x:Name="MC" CornerRadius="3" Background="{StaticResource Acc}" RenderTransformOrigin="0,0.5"><Border.RenderTransform><ScaleTransform x:Name="MCs" ScaleX="0"/></Border.RenderTransform></Border></Grid>
          <TextBlock x:Name="MCt" Text="—" FontSize="12" Width="34" TextAlignment="Right" VerticalAlignment="Center" Margin="7,0,0,0"/></StackPanel>
        <StackPanel Orientation="Horizontal" Margin="0,0,14,0" VerticalAlignment="Center"><TextBlock Text="Память" FontSize="12" Foreground="{StaticResource Dim}" VerticalAlignment="Center" Margin="0,0,7,0"/>
          <Grid Width="56" Height="5" VerticalAlignment="Center"><Border CornerRadius="3" Background="{StaticResource DimTrack}"/><Border x:Name="MM" CornerRadius="3" Background="{StaticResource Acc}" RenderTransformOrigin="0,0.5"><Border.RenderTransform><ScaleTransform x:Name="MMs" ScaleX="0"/></Border.RenderTransform></Border></Grid>
          <TextBlock x:Name="MMt" Text="—" FontSize="12" Width="34" TextAlignment="Right" VerticalAlignment="Center" Margin="7,0,0,0"/></StackPanel>
        <Button x:Name="BtnMin" Style="{StaticResource Plain}" Width="34" Height="30" HorizontalContentAlignment="Center" BorderBrush="{StaticResource Hover}" ToolTip="Свернуть"><TextBlock Text="&#xE921;" FontFamily="{StaticResource Ico}" FontSize="11" Foreground="{StaticResource Text}"/></Button>
        <Button x:Name="BtnClose" Style="{StaticResource Plain}" Width="34" Height="30" HorizontalContentAlignment="Center" BorderBrush="{StaticResource CloseHover}" ToolTip="Закрыть"><TextBlock Text="&#xE8BB;" FontFamily="{StaticResource Ico}" FontSize="11" Foreground="{StaticResource Text}"/></Button>
      </StackPanel>
    </Grid>

    <!-- Шторка: свёртывание — масштаб подложки и сдвиг, без анимации ширины -->
    <Grid x:Name="Drawer" Width="212" HorizontalAlignment="Left" KeyboardNavigation.TabNavigation="Local" KeyboardNavigation.TabIndex="1">
      <Border x:Name="DrawerBg" Background="{StaticResource Glass}" RenderTransformOrigin="0,0"><Border.RenderTransform><ScaleTransform x:Name="DrawerScale"/></Border.RenderTransform></Border>
      <Rectangle Width="1" HorizontalAlignment="Right" Fill="{StaticResource Edge}"><Rectangle.RenderTransform><TranslateTransform x:Name="EdgeShift"/></Rectangle.RenderTransform></Rectangle>
      <Grid Margin="10,18,10,16">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <StackPanel x:Name="Brand" Orientation="Horizontal" Margin="4,0,0,22" Background="Transparent">
          <Button x:Name="BtnMenu" Style="{StaticResource Plain}" Width="36" Height="32" HorizontalContentAlignment="Center" BorderBrush="{StaticResource Hover}" ToolTip="Свернуть шторку"><TextBlock Text="&#xE700;" FontFamily="{StaticResource Ico}" FontSize="18" Foreground="{StaticResource Text}"/></Button>
          <TextBlock x:Name="BrandTx" Text="Помощник" FontSize="17" FontWeight="SemiBold" Margin="8,0,0,0" VerticalAlignment="Center"/>
        </StackPanel>
        <Grid Grid.Row="1">
          <Grid x:Name="Pill" Height="44" VerticalAlignment="Top" IsHitTestVisible="False"><Grid.RenderTransform><TranslateTransform x:Name="PillMove"/></Grid.RenderTransform>
            <Border Background="{StaticResource AccSoft}" CornerRadius="8" RenderTransformOrigin="0,0"><Border.RenderTransform><ScaleTransform x:Name="PillScale"/></Border.RenderTransform></Border>
            <Border Width="3" Height="20" CornerRadius="2" Background="{StaticResource Acc}" HorizontalAlignment="Left"/></Grid>
          <StackPanel x:Name="Nav"/>
        </Grid>
        <Button x:Name="VerBtn" Grid.Row="2" Style="{StaticResource Plain}" Padding="14,2" HorizontalAlignment="Left">
          <StackPanel><TextBlock FontSize="12"><Run x:Name="VerRun"/><Run x:Name="VerSep" Text=" · "/><Underline><Run Text="что нового"/></Underline></TextBlock><TextBlock Text="Сделано с любовью" FontSize="12" Margin="0,2,0,0"/></StackPanel></Button>
      </Grid>
    </Grid>

    <Grid x:Name="Views" Margin="240,26,0,60" HorizontalAlignment="Left" KeyboardNavigation.TabNavigation="Local" KeyboardNavigation.TabIndex="2">
      <Grid.RenderTransform><TranslateTransform x:Name="ViewShift"/></Grid.RenderTransform>
      <!-- Главная -->
      <StackPanel x:Name="VHome" Width="478" HorizontalAlignment="Left">
        <TextBlock x:Name="Hello" FontFamily="{StaticResource Hand}" FontSize="38" Foreground="{StaticResource Warm}"/>
        <TextBlock x:Name="HSub" FontSize="14" Foreground="{StaticResource Dim}" TextWrapping="Wrap" LineHeight="21" Margin="0,8,0,14" MinHeight="42"/>
        <WrapPanel x:Name="Chips" Margin="0,0,0,18"/>
        <Button x:Name="Pb" Style="{StaticResource PrimaryButton}">
          <StackPanel Orientation="Horizontal">
            <Grid Width="46" Height="46">
              <Ellipse Stroke="{StaticResource InkTrack}" StrokeThickness="4" Margin="1"/>
              <Ellipse x:Name="Rg" Stroke="{StaticResource Ink}" StrokeThickness="4" Margin="1" StrokeDashArray="31.42 40" StrokeDashOffset="31.42" StrokeDashCap="Round" Opacity="0" RenderTransformOrigin="0.5,0.5"><Ellipse.RenderTransform><RotateTransform Angle="-90"/></Ellipse.RenderTransform></Ellipse>
              <TextBlock x:Name="PIco" FontSize="20" FontWeight="SemiBold" Foreground="{StaticResource Ink}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Grid>
            <StackPanel Margin="16,0,0,0" VerticalAlignment="Center"><TextBlock x:Name="PTx" FontSize="20" FontWeight="SemiBold" Foreground="{StaticResource Ink}"/><TextBlock x:Name="PSx" FontSize="13" Foreground="{StaticResource Ink}" Opacity="0.85"/></StackPanel>
          </StackPanel>
        </Button>
        <Grid>
          <StackPanel x:Name="HCards">
            <TextBlock x:Name="Cap" Text="ЧАСТО НУЖНО" FontSize="12" Foreground="{StaticResource Dim}" Margin="0,20,0,10"/>
            <UniformGrid x:Name="Quick" Columns="2" Margin="-5"/>
            <StackPanel x:Name="LastRow" Orientation="Horizontal" Margin="0,14,0,0"><TextBlock Text="&#xE81C;" FontFamily="{StaticResource Ico}" FontSize="14" Foreground="{StaticResource Acc}" VerticalAlignment="Center" Margin="0,0,8,0"/><TextBlock x:Name="LastTx" FontSize="13" Foreground="{StaticResource Dim}"/></StackPanel>
          </StackPanel>
          <StackPanel x:Name="HRun" Visibility="Collapsed" Margin="0,14,0,0"><!--RUN H--></StackPanel>
        </Grid>
      </StackPanel>
      <!-- Экран хода: один на все карточки -->
      <StackPanel x:Name="VAct" Width="552" HorizontalAlignment="Left" Visibility="Collapsed">
        <Button x:Name="ABack" Style="{StaticResource Plain}" HorizontalAlignment="Left" Margin="0,0,0,10" Padding="0,2"><StackPanel Orientation="Horizontal"><TextBlock Text="&#xE72B;" FontFamily="{StaticResource Ico}" FontSize="13" VerticalAlignment="Center" Margin="0,0,8,0"/><TextBlock x:Name="ABackTx" FontSize="13"/></StackPanel></Button>
        <StackPanel Orientation="Horizontal" Margin="0,0,0,14"><Border Width="44" Height="44" CornerRadius="12" Background="{StaticResource AccSoft}"><TextBlock x:Name="AIco" FontFamily="{StaticResource Ico}" FontSize="20" Foreground="{StaticResource Acc}" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
          <StackPanel Margin="14,0,0,0" VerticalAlignment="Center"><TextBlock x:Name="ATitle" FontSize="22" FontWeight="SemiBold"/><TextBlock x:Name="ASub" FontSize="13" Foreground="{StaticResource Dim}"/></StackPanel></StackPanel>
        <!--RUN A-->
      </StackPanel>
      <!-- Раздел: заголовок, подпись и содержимое (собирается при входе) -->
      <StackPanel x:Name="VSec" Width="552" HorizontalAlignment="Left" Visibility="Collapsed">
        <TextBlock FontSize="28" FontWeight="SemiBold"><Run x:Name="STitle"/><Run x:Name="SHand" FontFamily="{StaticResource Hand}" FontSize="17" FontWeight="Normal" Foreground="{StaticResource Warm}"/></TextBlock>
        <TextBlock x:Name="SSub" FontSize="14" Foreground="{StaticResource Dim}" TextWrapping="Wrap" LineHeight="21" Margin="0,8,0,14"/>
        <ContentControl x:Name="SBody" Focusable="False"/>
      </StackPanel>
      <!-- Живые плитки «Скорости»: колонка справа от карточек, на месте сцены -->
      <ContentControl x:Name="VTiles" Width="152" Margin="564,26,0,0" HorizontalAlignment="Left" VerticalAlignment="Top" Focusable="False" Visibility="Collapsed"/>
    </Grid>

    <!-- Живая строка внизу -->
    <Border x:Name="Live" Margin="240,0,24,14" Height="34" VerticalAlignment="Bottom" CornerRadius="10" Background="{StaticResource Glass}" BorderBrush="{StaticResource Edge}" BorderThickness="1" Padding="14,0" KeyboardNavigation.TabNavigation="Local" KeyboardNavigation.TabIndex="3">
      <Border.RenderTransform><TranslateTransform x:Name="LiveMove"/></Border.RenderTransform>
      <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <Ellipse x:Name="LiveDot" Width="7" Height="7" Fill="{StaticResource Acc}" VerticalAlignment="Center" Margin="0,0,10,0"/>
        <Canvas Grid.Column="1" ClipToBounds="True" Height="18" VerticalAlignment="Center"><TextBlock x:Name="LiveTx" FontSize="12.5" Foreground="{StaticResource Dim}"><TextBlock.RenderTransform><TranslateTransform x:Name="LiveTxMove"/></TextBlock.RenderTransform></TextBlock></Canvas>
        <Button x:Name="LiveBtn" Grid.Column="2" Style="{StaticResource GBtnAcc}" Padding="10,2" FontSize="12" Margin="8,0,0,0" Visibility="Collapsed"><TextBlock x:Name="LiveBtnTx"/></Button>
      </Grid>
    </Border>

    <!-- Боковая панель: «что нового» -->
    <Border x:Name="Side" Width="390" HorizontalAlignment="Right" Margin="0,46,0,0" Background="{StaticResource Solid}" BorderBrush="{StaticResource Edge}" BorderThickness="1,0,0,0" Padding="24,26" Visibility="Collapsed" KeyboardNavigation.TabNavigation="Cycle" KeyboardNavigation.TabIndex="4">
      <Border.RenderTransform><TranslateTransform x:Name="SideMove" X="390"/></Border.RenderTransform>
      <Grid><ScrollViewer VerticalScrollBarVisibility="Hidden" Focusable="False"><StackPanel x:Name="SideBody"/></ScrollViewer>
        <Button x:Name="SideX" Style="{StaticResource Plain}" Width="30" Height="30" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,-14,-10,0" HorizontalContentAlignment="Center" BorderBrush="{StaticResource Hover}" ToolTip="Закрыть"><TextBlock Text="&#xE711;" FontFamily="{StaticResource Ico}" FontSize="14"/></Button></Grid>
    </Border>

    <!-- Подтверждение рискованного шага -->
    <Grid x:Name="Cfm" Background="{StaticResource Scrim}" Visibility="Collapsed">
      <Border x:Name="CfmBox" Width="380" VerticalAlignment="Center" HorizontalAlignment="Center" CornerRadius="12" Background="{StaticResource GlassHi}" BorderBrush="{StaticResource Edge}" BorderThickness="1" Padding="24" RenderTransformOrigin="0.5,0.5" KeyboardNavigation.TabNavigation="Cycle">
        <Border.RenderTransform><ScaleTransform x:Name="CfmScale"/></Border.RenderTransform>
        <StackPanel><TextBlock x:Name="CfmT" FontSize="18" FontWeight="SemiBold" TextWrapping="Wrap"/>
          <Grid Margin="0,12,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="110"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <TextBlock Text="Что сделаю" FontSize="13.5" Foreground="{StaticResource Dim}" Margin="0,4"/><TextBlock x:Name="CfmW" Grid.Column="1" FontSize="13.5" TextWrapping="Wrap" LineHeight="20" Margin="0,4"/>
            <TextBlock Grid.Row="1" Text="Как вернуть" FontSize="13.5" Foreground="{StaticResource Dim}" Margin="0,4"/><TextBlock x:Name="CfmU" Grid.Row="1" Grid.Column="1" FontSize="13.5" TextWrapping="Wrap" LineHeight="20" Margin="0,4"/></Grid>
          <StackPanel Orientation="Horizontal" Margin="0,18,0,0"><Button x:Name="CfmY" Style="{StaticResource GBtnAcc}"><TextBlock x:Name="CfmYt"/></Button><Button x:Name="CfmN" Style="{StaticResource GBtn}"><TextBlock x:Name="CfmNt"/></Button></StackPanel>
        </StackPanel>
      </Border>
    </Grid>

    <!-- Позвать помощь: номер AnyDesk и «Скопировать» -->
    <Grid x:Name="Hlp" Background="{StaticResource Scrim}" Visibility="Collapsed">
      <Border Width="380" VerticalAlignment="Center" HorizontalAlignment="Center" CornerRadius="12" Background="{StaticResource GlassHi}" BorderBrush="{StaticResource Edge}" BorderThickness="1" Padding="24" RenderTransformOrigin="0.5,0.5" KeyboardNavigation.TabNavigation="Cycle">
        <Border.RenderTransform><ScaleTransform x:Name="HlpScale"/></Border.RenderTransform>
        <StackPanel><StackPanel Orientation="Horizontal"><Border Width="36" Height="36" CornerRadius="10" Background="{StaticResource AccSoft}"><TextBlock Text="&#xE77B;" FontFamily="{StaticResource Ico}" FontSize="17" Foreground="{StaticResource Acc}" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
            <TextBlock Text="Позвать помощь" FontSize="18" FontWeight="SemiBold" Margin="12,0,0,0" VerticalAlignment="Center"/></StackPanel>
          <TextBlock x:Name="HlpP" FontSize="13.5" Foreground="{StaticResource Dim}" TextWrapping="Wrap" LineHeight="20" Margin="0,14,0,0"/>
          <TextBlock x:Name="HlpN" FontWeight="SemiBold" Margin="0,10,0,4" TextWrapping="Wrap" Typography.NumeralAlignment="Tabular"/>
          <TextBlock x:Name="HlpS" FontSize="12" Foreground="{StaticResource Dim}" TextWrapping="Wrap"/>
          <TextBlock Text="Когда AnyDesk спросит про подключение — нажми «Принять», только если сама звала помощь." FontSize="12" Foreground="{StaticResource Dim}" TextWrapping="Wrap" LineHeight="16" Margin="0,10,0,0"/>
          <StackPanel Orientation="Horizontal" Margin="0,18,0,0"><Button x:Name="HlpC" Style="{StaticResource GBtn}"><StackPanel Orientation="Horizontal"><TextBlock x:Name="HlpCi" FontFamily="{StaticResource Ico}" FontSize="13" VerticalAlignment="Center" Margin="0,0,8,0"/><TextBlock x:Name="HlpCt"/></StackPanel></Button>
            <Button x:Name="HlpX" Style="{StaticResource GBtn}"><TextBlock Text="Закрыть"/></Button></StackPanel>
        </StackPanel>
      </Border>
    </Grid>
  </Grid>
</Window>
'@
# ---------- Разделы и инструменты ----------
# Тип: admin — от администратора внутри окна; user — внутри окна; gui — своё окно; exe/note/folder — открыть; toggle — переключатель; help — окно AnyDesk.
# [5] — группа в разделе, [6] wide — карточка на весь ряд
$tools = @{
  net = @(
    @('&#xE714;', 'Не работает YouTube или Discord', 'Подберу новый способ обхода сам', "$Hd\zapret-repick.ps1", 'admin'),
    @('&#xE774;', 'Сайт не открывается', 'Проверю сайт и открою через VPN', "$Hd\site-fix.ps1", 'user'),
    @('&#xE72E;', 'Заблокированные сайты', 'Instagram, X, ChatGPT — через Happ', "$Hd\smart-proxy.ps1", 'toggle'),
    @('&#xE724;', 'Не работает Telegram', 'Переподключу Happ — прокси для Telegram', "$Hd\happ-connect.ps1", 'user'),
    @('&#xE909;', 'Какие сайты открываются', 'YouTube, Discord, Telegram, Instagram и другие', "$Hd\check-sites.ps1", 'user'),
    @('&#xE701;', 'Интернет совсем не работает', 'Сброшу сеть и перезапущу Wi-Fi', "$Gd\fix-internet.ps1", 'admin', '', 'wide'))
  speed = @(
    @('&#xEC4A;', 'Что тормозит сейчас', 'Покажу, что грузит ноутбук, и что делать', "$Hd\perf-now.ps1", 'user', 'КОГДА ЧТО-ТО НЕ ТАК'),
    @('&#xE82F;', 'Почему тормозит', 'Найду главную причину и скажу, что сделать', "$Hd\revive.ps1", 'user', 'КОГДА ЧТО-ТО НЕ ТАК'),
    @('&#xE74D;', 'Почистить мусор', 'Временные файлы, Корзина — по слову', "$Hd\clean-junk.ps1", 'admin', 'ПОРЯДОК НА НОУТБУКЕ'),
    @('&#xEA99;', 'Большая уборка', 'Уберу весь мусор, спрошу про каждую часть', "$Hd\big-clean.ps1", 'admin', 'ПОРЯДОК НА НОУТБУКЕ'),
    @('&#xE7E8;', 'Что запускается с Windows', 'Список и отключение лишнего', "$Hd\startup-all.ps1", 'admin', 'ПОРЯДОК НА НОУТБУКЕ'),
    @('&#xEDA2;', 'Что занимает место', 'Самые большие папки, ничего не удаляю', "$Hd\disk-space.ps1", 'user', 'ПОРЯДОК НА НОУТБУКЕ'),
    @('&#xE896;', 'Разобрать Загрузки', 'Картинки, видео, документы — по папкам', "$Hd\sort-downloads.ps1", 'user', 'ПОРЯДОК НА НОУТБУКЕ'),
    @('&#xE7A7;', 'Вернуть Загрузки как было', 'Отменю разбор Загрузок', "$Hd\undo-sort-downloads.ps1", 'user', 'ПОРЯДОК НА НОУТБУКЕ'),
    @('&#xE895;', 'Обновить программы', 'Найду и поставлю новые версии', "$Hd\update-apps.ps1", 'admin', 'ПОРЯДОК НА НОУТБУКЕ'),
    @('&#xE90F;', 'Не открываются файлы или меню', 'Найду и исправлю причину', "$Hd\file-repair.ps1", 'admin', 'КОГДА ЧТО-ТО НЕ ТАК'),
    @('&#xE945;', 'Энергосбережение', 'Уберу экономию питания, которая тормозит', "$Hd\energy.ps1", 'admin', 'КОГДА ЧТО-ТО НЕ ТАК'),
    @('&#xE962;', 'Мышь и тачпад', 'Замерю мышь и настрою точность указателя', "$Hd\mouse.ps1", 'admin', 'КОГДА ЧТО-ТО НЕ ТАК'))
  protect = @(
    @('&#xEA18;', 'Проверка безопасности', 'Нет ли вирусов в автозапуске и Загрузках', "$Gd\check-now.ps1", 'user'),
    @('&#xE88E;', 'Резервная копия', 'Документы и фото на флешку', "$Hd\backup.ps1", 'admin'),
    @('&#xE714;', 'Кто включал камеру и микрофон', 'Какие программы и когда снимали или слушали', "$Hd\privacy-check.ps1", 'user'),
    @('&#xE83F;', 'Отчёт о батарее', 'Износ и состояние батареи', "$Gd\battery-report.ps1", 'user'),
    @('&#xE721;', 'Найти файл', 'Мгновенный поиск любого файла (Everything)', 'C:\Program Files\Everything\Everything.exe', 'exe'))
  help = @(
    @('&#xE77B;', 'Позвать помощь', 'Покажу номер AnyDesk и скопирую его', '', 'help'),
    @('&#xE8A5;', 'Прочитать подсказки', 'Что делает каждая кнопка', (Join-Path $Tools 'ПРОЧИТАЙ МЕНЯ.txt'), 'note'),
    @('&#xE838;', 'Все инструменты', 'Папка со всеми ярлыками', $Tools, 'folder'),
    @('&#xE895;', 'Проверить обновления Помощника', 'Скачаю новую версию, если она вышла', '', 'update')) }
$pages = [ordered]@{
  home    = @('&#xE80F;', 'Главная', '', '', '')
  net     = @('&#xE774;', 'Интернет', 'Интернет и блокировки', 'YouTube, Discord, Telegram и заблокированные сайты — всё чинится здесь.', 'починим')
  speed   = @('&#xEC4A;', 'Скорость', 'Скорость и порядок', 'Что тормозит, что лишнее и где место на диске.', 'наведём порядок')
  protect = @('&#xEA18;', 'Защита', 'Защита и копии', 'Вирусы, камера, батарея и резервная копия.', 'под присмотром')
  guards  = @('&#xE7B3;', 'Сторожа', 'Сторожа', 'Что работает в фоне, зачем оно нужно и что можно выключить.', 'на посту')
  help    = @('&#xE77B;', 'Помощь', 'Помощь', 'Если что-то непонятно или не работает — позови человека.', 'я рядом') }
$quick = @($tools.net[0], $tools.net[1], $tools.speed[0], $tools.help[0])
$quickT = @('Не работает YouTube', 'Сайт не открывается', 'Что тормозит', 'Позвать помощь')
$hero = @('&#xE9D9;', 'Проверить ноутбук', 'Найду, что не так, и скажу, что делать', "$Hd\system-health.ps1", 'admin')

# Пункты шторки, карточки «Часто нужно» и чипы — строкой в XAML окна: сотни New-Object стоили ~0,4 с запуска
function Xe($s) { [Security.SecurityElement]::Escape("$s") }
$sb = New-Object Text.StringBuilder
foreach ($k in $pages.Keys) { [void]$sb.Append("<Button x:Name=`"Nav_$k`" Tag=`"$k`" Style=`"{StaticResource Plain}`" Height=`"44`" Margin=`"0,0,0,8`" Padding=`"16,0`" Width=`"192`" HorizontalAlignment=`"Left`" HorizontalContentAlignment=`"Stretch`" ToolTip=`"$($pages[$k][1])`"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width=`"Auto`"/><ColumnDefinition/><ColumnDefinition Width=`"Auto`"/></Grid.ColumnDefinitions>" +
  "<TextBlock x:Name=`"NavI_$k`" Text=`"$($pages[$k][0])`" FontFamily=`"{StaticResource Ico}`" FontSize=`"17`" Width=`"18`" TextAlignment=`"Center`" VerticalAlignment=`"Center`"/><TextBlock x:Name=`"NavL_$k`" Grid.Column=`"1`" Text=`"$($pages[$k][1])`" FontSize=`"15`" Margin=`"14,0,0,0`" VerticalAlignment=`"Center`"/>" +
  "<Ellipse x:Name=`"NavD_$k`" Grid.Column=`"2`" Width=`"8`" Height=`"8`" Fill=`"{StaticResource Warm}`" Opacity=`"0`" VerticalAlignment=`"Center`"><Ellipse.RenderTransform><TranslateTransform/></Ellipse.RenderTransform></Ellipse></Grid></Button>") }
$xaml = $xaml.Replace('<StackPanel x:Name="Nav"/>', '<StackPanel x:Name="Nav">' + $sb.ToString() + '</StackPanel>')
# Карточка-выбор: на главной и в разделах одна разметка; $at — свойства раскладки (колонка, ряд)
function CardX($it, $title, $name, $at = '') { $note = ''
  if ($it[4] -eq 'admin') { $note = @('&#xE7EF;', 'Windows спросит разрешение', 'Warm') } elseif ($it[4] -in @('gui', 'exe', 'note', 'folder')) { $note = @('&#xE8A7;', 'откроется в своём окне', 'Dim') }
  if ($note) { $note = "<Grid Margin=`"0,5,0,0`"><Grid.ColumnDefinitions><ColumnDefinition Width=`"Auto`"/><ColumnDefinition/></Grid.ColumnDefinitions><TextBlock Text=`"$($note[0])`" FontFamily=`"{StaticResource Ico}`" FontSize=`"11`" Foreground=`"{StaticResource $($note[2])}`" Margin=`"0,2,5,0`"/><TextBlock Grid.Column=`"1`" Text=`"$($note[1])`" FontSize=`"12`" Foreground=`"{StaticResource $($note[2])}`" TextWrapping=`"Wrap`"/></Grid>" }
  "<Button x:Name=`"$name`"$at Style=`"{StaticResource DCard}`"><Grid><Rectangle RadiusX=`"12`" RadiusY=`"12`" IsHitTestVisible=`"False`"><Rectangle.Fill><RadialGradientBrush MappingMode=`"Absolute`" RadiusX=`"180`" RadiusY=`"180`" Center=`"-200,-200`" GradientOrigin=`"-200,-200`"><GradientStop Color=`"{StaticResource GlowC}`" Offset=`"0`"/><GradientStop Color=`"{StaticResource GlowC0}`" Offset=`"0.7`"/></RadialGradientBrush></Rectangle.Fill></Rectangle>" +
    "<Grid Margin=`"14,13`"><Grid.ColumnDefinitions><ColumnDefinition Width=`"Auto`"/><ColumnDefinition/></Grid.ColumnDefinitions><Border Width=`"36`" Height=`"36`" CornerRadius=`"10`" Background=`"{StaticResource AccSoft}`" VerticalAlignment=`"Top`" RenderTransformOrigin=`"0.5,0.5`"><Border.RenderTransform><TransformGroup><RotateTransform/><ScaleTransform/></TransformGroup></Border.RenderTransform>" +
    "<TextBlock Text=`"$($it[0])`" FontFamily=`"{StaticResource Ico}`" FontSize=`"17`" Foreground=`"{StaticResource Acc}`" HorizontalAlignment=`"Center`" VerticalAlignment=`"Center`"/></Border><StackPanel Grid.Column=`"1`" Margin=`"12,0,0,0`"><TextBlock Text=`"$(Xe $title)`" FontSize=`"15`" FontWeight=`"SemiBold`" Margin=`"0,0,0,2`" TextWrapping=`"Wrap`"/>" +
    "<TextBlock Text=`"$(Xe $it[2])`" FontSize=`"13`" Foreground=`"{StaticResource Dim}`" LineHeight=`"18`" TextWrapping=`"Wrap`"/>$note</StackPanel></Grid></Grid></Button>" }
$sb = New-Object Text.StringBuilder; $q = 0
foreach ($it in $quick) { [void]$sb.Append((CardX $it $quickT[$q] "Q$q")); $q++ }
$xaml = $xaml.Replace('<UniformGrid x:Name="Quick" Columns="2" Margin="-5"/>', '<UniformGrid x:Name="Quick" Columns="2" Margin="-5">' + $sb.ToString() + '</UniformGrid>')
$sb = New-Object Text.StringBuilder; foreach ($i in 0..2) { [void]$sb.Append("<Border CornerRadius=`"14`" Background=`"{StaticResource Glass}`" BorderBrush=`"{StaticResource Edge}`" BorderThickness=`"1`" Padding=`"10,6`" Margin=`"0,0,6,6`"><StackPanel Orientation=`"Horizontal`"><Grid Width=`"7`" Height=`"7`" Margin=`"0,0,7,0`" VerticalAlignment=`"Center`"><Ellipse x:Name=`"ChipD$i`" Fill=`"{StaticResource Dim}`"/>" +
  "<Ellipse x:Name=`"ChipP$i`" Stroke=`"{StaticResource Acc}`" StrokeThickness=`"2`" Opacity=`"0`" RenderTransformOrigin=`"0.5,0.5`"><Ellipse.RenderTransform><ScaleTransform/></Ellipse.RenderTransform></Ellipse></Grid><TextBlock x:Name=`"ChipT$i`" FontSize=`"12.5`"/></StackPanel></Border>") }
$xaml = $xaml.Replace('<WrapPanel x:Name="Chips" Margin="0,0,0,18"/>', '<WrapPanel x:Name="Chips" Margin="0,0,0,18">' + $sb.ToString() + '</WrapPanel>')
# Звёзды сцены: тот же порядок случайных чисел, что в макете; строкой в XAML (70 New-Object — ~0,2 с к запуску)
$script:sd = 7; function Rnd { $script:sd = ([long]$script:sd * 9301 + 49297) % 233280; $script:sd / 233280 }
$inv = [Globalization.CultureInfo]::InvariantCulture; $sb = New-Object Text.StringBuilder
for ($i = 0; $i -lt 70; $i++) { $x = 220 + (Rnd) * 760; $y = (Rnd) * 420; $big = (Rnd) -lt 0.12; $rr = $(if ($big) { 1.5 } else { 0.5 + (Rnd) * 0.7 }); $op = $(if ($big) { 0.8 } else { 0.2 + (Rnd) * 0.4 })
  [void]$sb.Append([string]::Format($inv, '<Ellipse Canvas.Left="{0:0.##}" Canvas.Top="{1:0.##}" Width="{2:0.##}" Height="{2:0.##}" Fill="{{StaticResource Text}}" Opacity="{3:0.##}"/>', ($x - $rr), ($y - $rr), (2 * $rr), $op)) }
$xaml = $xaml.Replace('<Canvas x:Name="Stars"/>', '<Canvas x:Name="Stars">' + $sb.ToString() + '</Canvas>')
$xaml = $xaml.Replace('<!--RUN H-->', $runBlock.Replace('@', 'H').Replace('<!--CTL-->', '')).Replace('<!--RUN A-->', $runBlock.Replace('@', 'A').Replace('<!--CTL-->', '<StackPanel x:Name="ACtl" Orientation="Horizontal" Margin="0,12,0,0"/>'))
$win = [Windows.Markup.XamlReader]::Parse($xaml)
function G($n) { $win.FindName($n) }
function T($k) { $win.Resources[$k] }
# Ошибка в обработчике события не закрывает окно: строка в reports\helper-app-handler-errors.txt (до 512 КБ) и сообщение внизу. Тот же сбой подряд пишется один раз.
# Не в helper-app-error.txt: по нему updater.ps1 откатывает версию, а окно здесь не упало
$win.Dispatcher.Add_UnhandledException({ param($s, $e) $e.Handled = $true; $x = $e.Exception; while ($x.InnerException -and -not $x.ErrorRecord) { $x = $x.InnerException }
  $t = "обработчик: $($x.Message -replace '\s*[\r\n]+\s*', ' ')"; $ii = $x.ErrorRecord.InvocationInfo; if ($ii) { $ln = "$($ii.Line)".Trim(); $t += " | строка $($ii.ScriptLineNumber): $($ln.Substring(0, [math]::Min(200, $ln.Length)))" }
  if ($t -ne $script:lastErr) { $script:lastErr = $t; try { $d = PctDir 'reports'; [void][IO.Directory]::CreateDirectory($d); $lf = "$d\helper-app-handler-errors.txt"
      if (-not ([IO.FileInfo]$lf).Exists -or ([IO.FileInfo]$lf).Length -lt 512KB) { [IO.File]::AppendAllText($lf, "$(Get-Date -f s) $t`n", (New-Object Text.UTF8Encoding $false)) } } catch {} }
  try { Snack 'Что-то пошло не так — я записал подробности.' 5000 } catch {} })
# Движение «как в Windows»: системный «Эффекты анимации» выкл — без анимаций, информация та же. PCT_CALM=1/0 — выкл/вкл принудительно; PNG — сразу конечное состояние
$script:calm = [bool]$env:PCT_RENDER -or $env:PCT_CALM -eq '1' -or ($env:PCT_CALM -ne '0' -and -not [Windows.SystemParameters]::ClientAreaAnimation)
$script:demo = [bool]$env:PCT_RENDER -or $env:PCT_DEMO -eq '1'
$script:out = $(if ($env:PCT_DEMO_OUT -in @('deny', 'fail')) { $env:PCT_DEMO_OUT } else { 'ok' })
$script:noTimer = [bool]$env:PCT_RENDER

$guards = @(
  @{ T = 'PCT-Guard-Autoruns'; I = '&#xEA18;'; N = 'Сторож автозапуска'; S = 'Раз в день ищет новое в автозагрузке'; Rec = 2
     W = 'Раз в день сравнивает автозагрузку со снимком «как было». Если появилась новая программа — присылает уведомление. Так ловятся вирусы, майнеры и программы-«прилипалы», которые прописываются сами.'
     R = 'Новый вирус в автозапуске останется незамеченным. Антивируса на этом ноутбуке нет — этот сторож один из главных способов защиты.'; L = 'Несколько секунд раз в день — незаметно.' },
  @{ T = 'PCT-Guard-Downloads'; I = '&#xE896;'; N = 'Сторож Загрузок'; S = 'Предупреждает об опасных файлах'; Rec = 2
     W = 'Каждые 15 минут смотрит новые файлы в «Загрузках». Если скачан файл без цифровой подписи или скрипт — предупреждает, прежде чем ты его откроешь.'
     R = 'Можно случайно открыть вредный файл без предупреждения. Именно так в прошлый раз попали два вируса.'; L = 'Доли секунды раз в 15 минут — незаметно.' },
  @{ T = 'PCT-Sites-Watch'; I = '&#xE714;'; N = 'Сторож YouTube и Discord'; S = 'Сам чинит обход блокировок'; Rec = 2; Bg = 'sites-watch'
     W = 'При входе и каждые 3 часа проверяет YouTube и Discord. Если провайдер сменил блокировку — сам подбирает новый способ обхода и пишет уведомление. Заодно возвращает обход заблокированных сайтов, если его сбросили.'
     R = 'Когда YouTube или Discord сломаются, придётся заметить это самой и нажать «Не работает YouTube или Discord».'; L = 'Пара секунд раз в 3 часа. Подбор (до 10 минут) — только когда сайты уже не работают.' },
  @{ T = 'PCT-Zapret'; I = '&#xE785;'; N = 'Обход блокировок при входе'; S = 'Включает обход после перезагрузки'; Rec = 2
     W = 'Когда ты входишь в Windows, включает zapret — программу, благодаря которой YouTube и Discord работают без VPN.'
     R = 'После каждой перезагрузки YouTube и Discord перестанут работать, пока не включишь обход вручную.'; L = 'Один запуск при входе. Сам zapret почти не тратит ресурсы.' },
  @{ T = 'PCT-Happ-Connect'; I = '&#xE724;'; N = 'Подключение Happ при входе'; S = 'Telegram и сайты без VPN'; Rec = 2
     W = 'После входа в Windows подключает Happ в режиме прокси и сворачивает его окно. Через него работают Telegram и заблокированные сайты (Instagram, X, ChatGPT...).'
     R = 'После перезагрузки Telegram и заблокированные сайты не откроются, пока не подключишь Happ вручную.'; L = 'Один запуск при входе.' },
  @{ T = 'Happ Proxy Autostart v2'; I = '&#xE7E8;'; N = 'Автозапуск Happ'; S = 'Запускает саму программу Happ'; Rec = 2
     W = 'Задача самой программы Happ: запускает её при входе в Windows. Без неё подключение Happ при входе не сработает.'
     R = 'Happ не запустится сам — Telegram и заблокированные сайты не будут работать после перезагрузки.'; L = 'Happ занимает около 70 МБ памяти в фоне.' },
  @{ T = 'PCT-Helper-Update'; I = '&#xE895;'; N = 'Обновление Помощника'; S = 'Раз в день скачивает новую версию'; Rec = 1
     W = 'При входе и раз в день проверяет, не вышла ли новая версия Помощника. Ставит только версии с правильной цифровой подписью — подменить их нельзя.'
     R = 'Исправления и новые кнопки перестанут приходить сами. Обновить можно вручную: «Помощь» → «Проверить обновления Помощника».'; L = 'Пара секунд раз в день.' },
  @{ T = 'PCT-Health-Weekly'; I = '&#xE9D9;'; N = 'Проверка раз в неделю'; S = 'По воскресеньям проверяет ноутбук'; Rec = 1
     W = 'По воскресеньям в 18:00 тихо проверяет ноутбук: диск, батарею, обновления, обход блокировок, резервную копию. Уведомление приходит, только если что-то не так.'
     R = 'Проблемы (заканчивается место, устарела копия, сломался обход) будут копиться незаметно, пока не нажмёшь «Проверить ноутбук».'; L = 'Около минуты раз в неделю.' },
  @{ T = 'PCT-Clean-Temp'; I = '&#xE74D;'; N = 'Уборка временных файлов'; S = 'По воскресеньям удаляет мусор'; Rec = 0
     W = 'По воскресеньям удаляет из папок Temp файлы старше 7 дней — то, что программы оставили и забыли. Твои файлы не трогает.'
     R = 'Ничего не сломается. Мусор будет копиться (за несколько месяцев — гигабайты); его можно убрать кнопкой «Почистить мусор».'; L = 'Около минуты раз в неделю.' })
$script:gs = @{}
$script:gp = @{}
# Состояние сторожей: один обход всех папок планировщика через COM (~140 мс вместо ~4 с у Get-ScheduledTask)
function TaskSvc { if (-not $script:svc) { $script:svc = New-Object -ComObject Schedule.Service; $script:svc.Connect() }; $script:svc }
function GuardScan { $m = @{}; $p = @{}
  # Образец: состояния из макета, переключения живут до закрытия окна
  if ($script:demo) { if (-not $script:gs.Count) { foreach ($g in $guards) { $script:gs[$g.T] = $(if ($g.T -in @('PCT-Happ-Connect', 'PCT-Clean-Temp')) { 'off' } else { 'on' }) } }; return }
  try { $q = New-Object Collections.Queue; $q.Enqueue((TaskSvc).GetFolder('\'))
    while ($q.Count) { $f = $q.Dequeue()
      try { foreach ($t in $f.GetTasks(1)) { if (-not $m.ContainsKey($t.Name)) { $m[$t.Name] = $(if ($t.Enabled) { 'on' } else { 'off' }); $p[$t.Name] = $t.Path } } } catch {}
      try { foreach ($s in $f.GetFolders(0)) { $q.Enqueue($s) } } catch {} } } catch {}
  foreach ($g in $guards) { $script:gs[$g.T] = $(if ($m.ContainsKey($g.T)) { $m[$g.T] } else { '?' }); $script:gp[$g.T] = $p[$g.T] } }
function GuardOne($g) { try { $t = (TaskSvc).GetFolder('\').GetTask($script:gp[$g.T]); $script:gs[$g.T] = $(if ($t.Enabled) { 'on' } else { 'off' }) } catch { $script:gs[$g.T] = '?' } }
$recTxt = @{ 2 = 'нужен'; 1 = 'полезен'; 0 = 'можно выключить' }
$recCol = @{ 2 = @('AccSoft', 'Acc'); 1 = @('WarmSoft', 'Warm'); 0 = @('DimSoft', 'Dim') }

# ---------- Образец показа (PCT_DEMO): тексты шагов из макета v5. К инструментам не подключён ----------
function S($n, $d, $r, $ms, $o) { $s = @{ N = $n; D = $d; R = $r; Ms = $ms }; if ($o) { foreach ($k in $o.Keys) { $s[$k] = $o[$k] } }; $s }
function Uac { @{ N = 'Жду, пока Windows спросит разрешение'; Hint = 'Нажми «Да» в окне Windows'; D = 'Разрешение Windows'; R = 'дано'; Ms = 2000; Uac = 1 } }
function DemoHome { @((S 'Смотрю свободное место на диске' 'Свободное место на диске' 'хватает, 84 ГБ' 2200 @{ Num = 84 }), (S 'Проверяю обновления Windows' 'Обновления Windows' 'всё в порядке' 2600),
  (S 'Смотрю, что грузится при старте' 'Автозапуск' '1 лишняя программа' 3000 @{ Warn = 1 }), (S 'Жду ответ от Защитника Windows' 'Защитник Windows' 'включён' 2400),
  (S 'Проверяю доступ к YouTube и Discord' 'YouTube и Discord' 'открываются' 2600 @{ BadR = 'не открываются' })) }
# Свежая копия на каждый показ: ответ на вопрос меняет шаг
function DemoTool($name) { switch ($name) {
  'Не работает YouTube или Discord' { @{ Steps = @((Uac), (S 'Проверяю, открывается ли YouTube' 'YouTube сейчас' 'не открывается' 2200 @{ Warn = 1 }), (S 'Пробую способ обхода 1 из 6' 'Способ 1' 'не подошёл' 2000 @{ Warn = 1 }), (S 'Пробую способ обхода 2 из 6' 'Способ 2' 'подошёл' 2400), (S 'Проверяю Discord' 'Discord' 'открывается' 1800), (S 'Сохраняю рабочий способ' 'Способ сохранён' 'будет включаться сам' 1400)); Ok = 'YouTube и Discord снова работают'; OkSub = 'Подошёл способ 2 из 6' } }
  'Сайт не открывается' { @{ Steps = @((S 'Проверяю, есть ли интернет' 'Интернет' 'есть' 1500), (S 'Открываю сайт напрямую' 'Напрямую' 'не открывается' 2200 @{ Warn = 1 }), (S 'Открываю через Happ' 'Через Happ' 'открывается' 2000), (S 'Добавляю сайт в список обхода' 'Список обхода' 'сайт добавлен' 1400)); Ok = 'Сайт открывается через Happ'; OkSub = 'Дальше будет открываться сам' } }
  'Не работает Telegram' { @{ Steps = @((S 'Проверяю, запущен ли Happ' 'Happ' 'запущен' 1400), (S 'Переподключаю прокси' 'Прокси' 'подключён' 2400), (S 'Жду ответ от Telegram' 'Telegram' 'отвечает' 2200)); Ok = 'Telegram работает'; OkSub = 'Happ переподключён' } }
  'Какие сайты открываются' { @{ Steps = @((S 'Проверяю YouTube' 'YouTube' 'открывается' 1200), (S 'Проверяю Discord' 'Discord' 'открывается' 1200), (S 'Проверяю Telegram' 'Telegram' 'открывается' 1200), (S 'Проверяю Instagram' 'Instagram' 'не открывается' 1400 @{ Bad = 1 }), (S 'Проверяю ChatGPT' 'ChatGPT' 'открывается' 1200)); Ok = 'Открываются 4 из 5'; OkSub = 'Instagram — нажми «Сайт не открывается»'; Part = 1 } }
  'Интернет совсем не работает' { @{ Risk = @('Сброшу настройки сети и перезапущу Wi-Fi. Интернет пропадёт примерно на минуту.', 'Сохранённые пароли Wi-Fi останутся. Вручную ничего возвращать не нужно.'); Steps = @((Uac), (S 'Смотрю, видит ли ноутбук Wi-Fi' 'Wi-Fi' 'сеть видна' 1600), (S 'Сбрасываю настройки сети' 'Настройки сети' 'сброшены' 2600), (S 'Перезапускаю Wi-Fi' 'Wi-Fi' 'перезапущен' 2400), (S 'Жду ответ от интернета' 'Интернет' 'есть' 2000)); Ok = 'Интернет снова работает'; OkSub = 'Сеть сброшена, Wi-Fi перезапущен' } }
  'Что тормозит сейчас' { @{ Steps = @((S 'Смотрю загрузку процессора' 'Процессор' 'занят на 32 %' 1600), (S 'Смотрю память' 'Память' 'занята на 80 %' 1600 @{ Warn = 1 }), (S 'Ищу, кто занял память' 'Больше всех' 'Chrome — 1,9 ГБ' 2200 @{ Warn = 1 })); Ok = 'Тормозит браузер Chrome'; OkSub = 'Закрой лишние вкладки — станет легче'; Part = 1 } }
  'Почистить мусор' { @{ Risk = @('Удалю временные файлы, которые оставили программы. Документы, фото и Корзину не трогаю.', 'Вернуть нельзя — но это только мусор программ, им он больше не нужен.'); Steps = @((Uac), (S 'Считаю временные файлы' 'Временные файлы' '1,2 ГБ' 2000 @{ Num = 1.2 }), (S 'Считаю Корзину' 'Корзина' '340 МБ' 1600), (S 'Удаляю временные файлы' 'Удалено' '1,2 ГБ' 2600)); Ok = 'Освободил 1,2 ГБ'; OkSub = 'Корзину не трогал — спрошу отдельно' } }
  'Что запускается с Windows' { @{ Steps = @((Uac), (S 'Читаю список автозапуска' 'Автозапуск' '14 программ' 2000), (S 'Проверяю подписи программ' 'Подписи' 'все в порядке' 2200)); Ok = '14 программ в автозапуске'; OkSub = 'Лишняя — одна, её можно выключить'; Part = 1 } }
  'Что занимает место' { @{ Steps = @((S 'Смотрю диск C' 'Свободно' '84 ГБ из 238' 1600), (S 'Ищу самые большие папки' 'Больше всех' 'Видео — 41 ГБ' 2600)); Ok = 'Больше всего места — Видео'; OkSub = 'Ничего не удалял' } }
  'Разобрать Загрузки' { @{ Risk = @('Разложу файлы из Загрузок по папкам: Картинки, Видео, Документы.', 'Кнопка «Вернуть Загрузки как было» вернёт всё на место.'); Steps = @((S 'Смотрю папку Загрузки' 'Загрузки' '213 файлов' 1400), (S 'Раскладываю по папкам' 'Разложено' '213 файлов' 2600), (S 'Записываю, как вернуть' 'Можно вернуть' 'кнопкой рядом' 1200)); Ok = 'Загрузки разобраны'; OkSub = 'Вернуть как было — кнопка рядом' } }
  'Вернуть Загрузки как было' { @{ Steps = @((S 'Читаю, что куда переложил' 'Записи' 'найдены' 1200), (S 'Возвращаю файлы' 'Возвращено' '213 файлов' 2200)); Ok = 'Загрузки как были'; OkSub = 'Все 213 файлов на месте' } }
  'Обновить программы' { @{ Risk = @('Найду новые версии программ и поставлю их. Программы закроются на время установки.', 'Твои данные в программах сохранятся. Старую версию вернуть нельзя.'); Steps = @((Uac), (S 'Ищу новые версии' 'Найдено' '3 обновления' 2400), (S 'Ставлю Chrome' 'Chrome' 'обновлён' 2400), (S 'Ставлю 7-Zip' '7-Zip' 'обновлён' 1800), (S 'Ставлю Telegram' 'Telegram' 'обновлён' 2000)); Ok = 'Обновил 3 программы'; OkSub = 'Chrome, 7-Zip, Telegram' } }
  'Не открываются файлы или меню' { @{ Steps = @((Uac), (S 'Проверяю системные файлы' 'Системные файлы' 'целы' 2800), (S 'Проверяю связи файлов' 'Связи файлов' 'исправлены 2' 2200)); Ok = 'Исправил 2 связи файлов'; OkSub = 'Перезагрузка не нужна' } }
  'Проверка безопасности' { @{ Steps = @((S 'Проверяю автозапуск' 'Автозапуск' '2 новые записи' 2000 @{ Warn = 1 }),
      (S 'Жду твой ответ про 2 новые программы' 'Новые программы в автозапуске' '' 0 @{ Ask = @{ Q = 'В автозапуске 2 новые программы. Это ты ставила?'; Items = @(@('&#xE774;', 'Служба обновления Яндекс Браузера', 'папка Яндекс Браузера · подпись: Яндекс'), @('&#xE722;', 'Загрузка изображений Windows', 'служба Windows для сканеров и камер · подпись: Microsoft')); Yes = @('Да, это мои', 'твои — запомнил'); No = @('Нет, не ставила', 'убрал из автозапуска') } }),
      (S 'Проверяю Загрузки' 'Загрузки' 'чисто' 2000), (S 'Проверяю настройки прокси' 'Прокси' 'это обход Помощника — в порядке' 1600), (S 'Жду ответ от Защитника Windows' 'Защитник Windows' 'включён' 1800)); Ok = 'Вирусов не нашёл'; OkSub = 'Автозапуск, Загрузки и прокси в порядке' } }
  'Резервная копия' { @{ Steps = @((Uac), (S 'Ищу флешку' 'Флешка' 'найдена, 64 ГБ' 1600), (S 'Копирую документы' 'Документы' 'скопированы' 2600), (S 'Копирую фото' 'Фото' 'скопированы' 3000), (S 'Сверяю копию' 'Копия' 'совпадает' 1600)); Ok = 'Копия на флешке'; OkSub = 'Документы и фото — 12 ГБ' } }
  'Кто включал камеру и микрофон' { @{ Steps = @((S 'Читаю журнал камеры' 'Камера' 'Discord, вчера' 1800), (S 'Читаю журнал микрофона' 'Микрофон' 'Discord, Telegram' 1800)); Ok = 'Чужих программ нет'; OkSub = 'Камеру и микрофон брали Discord и Telegram' } }
  'Отчёт о батарее' { @{ Steps = @((S 'Спрашиваю отчёт у Windows' 'Отчёт' 'готов' 2200), (S 'Считаю износ' 'Износ' '18 %' 1400)); Ok = 'Батарея в порядке'; OkSub = 'Износ 18 % — это нормально' } }
  'Проверить обновления Помощника' { @{ Steps = @((S 'Спрашиваю GitHub о новой версии' 'Новая версия' 'нет' 2400), (S 'Сверяю подпись' 'Подпись' 'в порядке' 1200)); Ok = 'У тебя последняя версия'; OkSub = 'Новых версий нет' } }
  default { $null } } }

function PacOn { Test-Path "$Hd\smart-proxy-on.txt" }
function Glyph($code) { [string][char][Convert]::ToInt32(($code -replace '&#x|;', ''), 16) }
function Ch($n) { [string][char]$n }
function Low($s) { if ($s) { $s.Substring(0, 1).ToLower() + $s.Substring(1) } }

# ---------- Движение: только RenderTransform, Opacity, StrokeDashOffset ----------
$DP = @{ O = [Windows.UIElement]::OpacityProperty; X = [Windows.Media.TranslateTransform]::XProperty; Y = [Windows.Media.TranslateTransform]::YProperty
  SX = [Windows.Media.ScaleTransform]::ScaleXProperty; SY = [Windows.Media.ScaleTransform]::ScaleYProperty; A = [Windows.Media.RotateTransform]::AngleProperty; D = [Windows.Shapes.Shape]::StrokeDashOffsetProperty }
function Tw($o, $prop, $to, $ms, $ease = 'out', $from = $null, $delay = 0) {
  $a = New-Object Windows.Media.Animation.DoubleAnimation; $a.To = $to; if ($null -ne $from -and -not $script:calm) { $a.From = $from }
  $a.Duration = [TimeSpan]::FromMilliseconds($(if ($script:calm) { 0 } else { $ms })); if ($delay -and -not $script:calm) { $a.BeginTime = [TimeSpan]::FromMilliseconds($delay) }
  if ($ease -eq 'spring') { $e = New-Object Windows.Media.Animation.BackEase; $e.Amplitude = 0.45 } elseif ($ease -eq 'elastic') { $e = New-Object Windows.Media.Animation.ElasticEase; $e.Oscillations = 1; $e.Springiness = 5 } elseif ($ease -ne 'lin') { $e = New-Object Windows.Media.Animation.CubicEase }
  if ($e) { $e.EasingMode = 'EaseOut'; $a.EasingFunction = $e }; $a.SetValue([Windows.Media.Animation.Timeline]::DesiredFrameRateProperty, 60); $o.BeginAnimation($prop, $a) }
# Бесконечное движение — только пока идёт работа; при «без анимаций» не запускается
function Loop($o, $prop, $from, $to, $ms, $rev) { if ($script:calm) { return }; $a = New-Object Windows.Media.Animation.DoubleAnimation($from, $to, [TimeSpan]::FromMilliseconds($ms))
  $a.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever; $a.AutoReverse = [bool]$rev; $a.SetValue([Windows.Media.Animation.Timeline]::DesiredFrameRateProperty, 30); $o.BeginAnimation($prop, $a) }
function Tf($el) { $g = $el.RenderTransform; if (-not ($g -is [Windows.Media.TransformGroup]) -or $g.IsFrozen) { $g = New-Object Windows.Media.TransformGroup
    [void]$g.Children.Add((New-Object Windows.Media.ScaleTransform)); [void]$g.Children.Add((New-Object Windows.Media.TranslateTransform)); $el.RenderTransform = $g; $el.RenderTransformOrigin = '0.5,0.5' }; $g }
function Tt($el) { $t = $el.RenderTransform; if ($t -is [Windows.Media.TranslateTransform] -and -not $t.IsFrozen) { return $t }; (Tf $el).Children[1] }
# Появление блока: снизу на 12 и из прозрачности
function Rise($el, $delay = 0, $ms = 500) { $t = Tt $el; if (-not $script:calm) { $el.Opacity = 0; $t.Y = 12 }; Tw $el $DP.O 1 $ms 'out' 0 $delay; Tw $t $DP.Y 0 $ms 'out' 12 $delay }
# Нажатие 0,96 и пружина назад
function Press($el) { [void](Tf $el)
  $el.Add_PreviewMouseLeftButtonDown({ param($s, $e) $g = Tf $s; Tw $g.Children[0] $DP.SX 0.96 120; Tw $g.Children[0] $DP.SY 0.96 120 })
  $up = { param($s, $e) $g = Tf $s; Tw $g.Children[0] $DP.SX 1 500 'elastic'; Tw $g.Children[0] $DP.SY 1 500 'elastic' }; $el.Add_PreviewMouseLeftButtonUp($up); $el.Add_MouseLeave($up) }
function Later($ms, [scriptblock]$sb) { if ($script:noTimer) { & $sb; return }
  $t = New-Object Windows.Threading.DispatcherTimer; $t.Interval = [TimeSpan]::FromMilliseconds($ms); $t.Tag = $sb; $t.Add_Tick({ param($s, $e) $s.Stop(); & $s.Tag }); $t.Start() }

# ---------- Мелкие элементы ----------
function Tx($t, $size = 14, $fg = 'Text', $w) { $b = New-Object Windows.Controls.TextBlock; $b.Text = $t; $b.FontSize = $size; if ($fg) { $b.Foreground = T $fg }; $b.TextWrapping = 'Wrap'; if ($w) { $b.FontWeight = $w }; $b }
function Ic($g, $size = 16, $fg = 'Acc') { $b = New-Object Windows.Controls.TextBlock; $b.Text = $g; $b.FontFamily = T 'Ico'; $b.FontSize = $size; if ($fg) { $b.Foreground = T $fg }; $b.VerticalAlignment = 'Center'; $b.HorizontalAlignment = 'Center'; $b }
function CiBox($g, $sz = 36, $fs = 17, $r = 10) { $b = New-Object Windows.Controls.Border -Property @{ Width = $sz; Height = $sz; CornerRadius = $r; Background = (T 'AccSoft'); VerticalAlignment = 'Top' }; $b.Child = Ic $g $fs; $b }
function Glass($edge = 'Edge', $pad = '16,14') { New-Object Windows.Controls.Border -Property @{ CornerRadius = 12; Background = (T 'Glass'); BorderBrush = (T $edge); BorderThickness = 1; Padding = $pad; Margin = '0,10,0,0' } }
function Btn($text, $sb, $style = 'GBtn', $g) { $b = New-Object Windows.Controls.Button; $b.Style = T $style; $b.Tag = $sb
  if ($g) { $sp = New-Object Windows.Controls.StackPanel -Property @{ Orientation = 'Horizontal' }; $i = Ic $g 13 $null; $i.Margin = '0,0,8,0'; [void]$sp.Children.Add($i); [void]$sp.Children.Add((Tx $text 13 $null)); $b.Content = $sp } else { $b.Content = $text }
  $b.Add_Click({ param($s, $e) & $s.Tag }); Press $b; $b }
function Col($g, $w) { [void]$g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{ Width = $w })) }
function Put($g, $el, $c = 0, $r = 0) { [Windows.Controls.Grid]::SetColumn($el, $c); [Windows.Controls.Grid]::SetRow($el, $r); [void]$g.Children.Add($el); $el }
# Галочка и крестик рисуются штрихом
function Chk($size = 18, $fg = 'Acc', $x) { $pa = New-Object Windows.Shapes.Path; $pa.Data = [Windows.Media.Geometry]::Parse($(if ($x) { 'M4.5,4.5 L13.5,13.5 M13.5,4.5 L4.5,13.5' } else { 'M3.5,9.5 L7,13 L14.5,5' }))
  $pa.Stroke = T $fg; $pa.StrokeThickness = 2.6; $pa.StrokeStartLineCap = 'Round'; $pa.StrokeEndLineCap = 'Round'; $pa.StrokeLineJoin = 'Round'; $n = $(if ($x) { 5 } else { 7 })
  $pa.StrokeDashArray = New-Object Windows.Media.DoubleCollection; [void]$pa.StrokeDashArray.Add($n); [void]$pa.StrokeDashArray.Add($n); Tw $pa $DP.D 0 450 'out' $n
  $c = New-Object Windows.Controls.Canvas -Property @{ Width = 18; Height = 18 }; [void]$c.Children.Add($pa); New-Object Windows.Controls.Viewbox -Property @{ Width = $size; Height = $size; Child = $c } }
function Spinner { $g = New-Object Windows.Controls.Grid -Property @{ Width = 16; Height = 16 }; [void]$g.Children.Add((New-Object Windows.Shapes.Ellipse -Property @{ Stroke = (T 'WarmTrack'); StrokeThickness = 2 }))
  $a = New-Object Windows.Shapes.Path -Property @{ Data = [Windows.Media.Geometry]::Parse('M8,1 A7,7 0 0 1 15,8'); Stroke = (T 'Warm'); StrokeThickness = 2; StrokeStartLineCap = 'Round'; StrokeEndLineCap = 'Round' }
  $rot = New-Object Windows.Media.RotateTransform(0, 8, 8); $a.RenderTransform = $rot; [void]$g.Children.Add($a); Loop $rot $DP.A 0 360 800; $g.Tag = $rot; $g }
function Ring0 { New-Object Windows.Shapes.Ellipse -Property @{ Width = 12; Height = 12; Stroke = (T 'Dim'); StrokeThickness = 1.5 } }

# ---------- Строка шага: ✓ сделано · ⟳ идёт (секунды) · ○ впереди ----------
function StepRow($r, $s, $state, $ft) {
  $row = New-Object Windows.Controls.Border -Property @{ Padding = '18,8'; BorderBrush = (T 'Line'); BorderThickness = '0,1,0,0' }
  $g = New-Object Windows.Controls.Grid; Col $g 22; Col $g 12; Col $g '*'; Col $g 'Auto'; $row.Child = $g
  $txt = $(if ($state -eq 'now' -or $state -eq 'wait') { $s.N } else { $s.D }); $tc = 'Dim'; $tw = $null; $time = ''; $timeC = 'Dim'; $hint = $null
  switch ($state) {
    'done' { $ic = Chk 18 $(if ($s.Bad) { 'Err' } else { 'Acc' }) $s.Bad; $time = $s.R; $timeC = $(if ($s.Bad) { 'Err' } elseif ($s.Warn) { 'Warm' } else { 'Acc' }) }
    'fail' { $ic = Chk 18 'Err' $true; $time = $(if ($ft) { $ft } else { $s.BadR }); $timeC = 'Err' }
    'now'  { $tc = 'Text'; $tw = 'SemiBold'; $row.Background = T 'NowRow'; $time = '0 с'
             if ($s.Ask) { $ic = Ic (Ch 0xE897) 15 'Warm'; $hint = 'Вопрос — ниже' } else { $ic = Spinner; $r.Spin = $ic.Tag; $hint = $s.Hint } }
    'stop' { $ic = Ring0; $time = 'остановил' }
    default { $ic = Ring0 } }
  [void](Put $g $ic 0)
  $sp = New-Object Windows.Controls.StackPanel -Property @{ VerticalAlignment = 'Center' }; $t1 = Tx $txt 14 $tc $tw; [void]$sp.Children.Add($t1)
  if ($hint) { $h = Tx $hint 12.5 'Warm'; [void]$sp.Children.Add($h); $r.HintTb = $h }; [void](Put $g $sp 2)
  $tb = Tx $time 13 $timeC; $tb.TextWrapping = 'NoWrap'; $tb.TextAlignment = 'Right'; $tb.Margin = '10,0,0,0'; $tb.VerticalAlignment = 'Center'; [void](Put $g $tb 3)
  if ($state -eq 'now') { $r.Sec = $tb }; $r.LastT = $tb; $row }
function RowSet($r, $i, $state, $ft) { $l = Px $r.P 'List'; if ($i -ge $l.Children.Count) { return }; if ($r.Spin) { $r.Spin.BeginAnimation($DP.A, $null); $r.Spin = $null }
  $row = StepRow $r $r.Steps[$i] $state $ft; $l.Children.RemoveAt($i); $l.Children.Insert($i, $row); if ($i -eq 0) { $row.BorderThickness = 0 }
  if ($state -eq 'done' -and $r.Steps[$i].Num) { CountUp $r.LastT $r.Steps[$i] }; $row }
# Число набегает за 0,7 с
function CountUp($tb, $s) { if ($script:calm) { return }; $c = @{ Tb = $tb; S = $s; T0 = Get-Date }; $t = New-Object Windows.Threading.DispatcherTimer; $t.Interval = [TimeSpan]::FromMilliseconds(30); $t.Tag = $c
  $t.Add_Tick({ param($x, $e) $c = $x.Tag; $k = [math]::Min(1, ((Get-Date) - $c.T0).TotalMilliseconds / 700); $v = $c.S.Num * (1 - [math]::Pow(1 - $k, 3))
    $f = $(if ($c.S.Num -lt 10) { $v.ToString('0.0').Replace('.', ',') } else { [string][int][math]::Round($v) }); $c.Tb.Text = ([regex]'\d+(,\d+)?').Replace($c.S.R, $f, 1); if ($k -ge 1) { $x.Stop(); $c.Tb.Text = $c.S.R } }); $t.Start() }

function Px($p, $n) { G ($p.ToUpper() + $n) }
function LogReset($p) { (Px $p 'Log').Children.Clear() }
function LogLine($p, $t, $c) { $tb = New-Object Windows.Controls.TextBlock -Property @{ TextWrapping = 'Wrap'; LineHeight = 19 }
  $r1 = New-Object Windows.Documents.Run ((Get-Date).ToString('HH:mm:ss') + '  '); $r1.Foreground = T 'Text'; $r2 = New-Object Windows.Documents.Run ("$t"); $r2.Foreground = T $(if ($c) { $c } else { 'Dim' })
  $tb.Inlines.Add($r1); $tb.Inlines.Add($r2); [void](Px $p 'Log').Children.Add($tb); (Px $p 'LogSv').ScrollToEnd() }
function LogToggle($p) { $b = Px $p 'LogBox'; $open = $b.Visibility -ne 'Visible'
  if ($open) { $b.Visibility = 'Visible'; Rise $b 0 300 } else { $b.Visibility = 'Collapsed' }; Tw (Px $p 'LogR') $DP.A $(if ($open) { 90 } else { 0 }) 300 }

# Итог одной строкой: значок, заголовок, подпись, «Показать шаги» (и «Скрыть итог» у настоящей проверки на главной)
function Summary($p, $kind, $icon, $title, $sub, [switch]$Hide) { $sb = Px $p 'Sum'; $g = New-Object Windows.Controls.Grid; Col $g 'Auto'; Col $g '*'; Col $g 'Auto'
  $bc = New-Object Windows.Controls.Grid -Property @{ Width = 40; Height = 40; VerticalAlignment = 'Center' }
  [void]$bc.Children.Add((New-Object Windows.Shapes.Ellipse -Property @{ Fill = (T $(switch ($kind) { 'ok' { 'AccSoft' } 'bad' { 'ErrSoft' } default { 'DimSoft' } })) }))
  if ($kind -ne 'idle') { $pg = New-Object Windows.Shapes.Ellipse -Property @{ Stroke = (T $(if ($kind -eq 'ok') { 'Acc' } else { 'Err' })); StrokeThickness = 2; Opacity = 0; RenderTransformOrigin = '0.5,0.5' }
    [void]$bc.Children.Add($pg); if (-not $script:calm) { $st = (Tf $pg).Children[0]; Tw $st $DP.SX 3.2 1100 'out' 1; Tw $st $DP.SY 3.2 1100 'out' 1; Tw $pg $DP.O 0 1100 'out' 0.9 } }
  [void]$bc.Children.Add($icon); [void](Put $g $bc 0)
  $sp = New-Object Windows.Controls.StackPanel -Property @{ Margin = '14,0,12,0'; VerticalAlignment = 'Center' }; [void]$sp.Children.Add((Tx $title 16 'Text' 'SemiBold')); [void]$sp.Children.Add((Tx $sub 13 'Dim')); [void](Put $g $sp 1)
  $lk = New-Object Windows.Controls.Button -Property @{ Style = (T 'Link'); Content = 'Показать шаги'; FontSize = 13; Tag = $p; VerticalAlignment = 'Center' }
  $lk.Add_Click({ param($s, $e) $b = Px $s.Tag 'Box'; $b.Visibility = $(if ($b.Visibility -eq 'Visible') { 'Collapsed' } else { 'Visible' }); (Px $s.Tag 'Head').Text = 'Что я сделал'; (Px $s.Tag 'Clock').Text = '' })
  if ($Hide) { $lc = New-Object Windows.Controls.StackPanel -Property @{ Orientation = 'Horizontal'; VerticalAlignment = 'Center' }; $hb = New-Object Windows.Controls.Button -Property @{ Style = (T 'Link'); Content = 'Скрыть итог'; FontSize = 13; Margin = '16,0,0,0' }
    $hb.Add_Click({ HomeIdle }); [void]$lc.Children.Add($lk); [void]$lc.Children.Add($hb); [void](Put $g $lc 2) } else { [void](Put $g $lk 2) }
  $sb.Child = $g; $sb.Visibility = 'Visible'; Rise $sb 0 400 }
# Карточка ошибки (§7): что случилось · твои файлы и настройки · что сделать
function ErrCard($p, $what, $btn, $click, $files = 'Всё на месте, я ничего не менял.', $todo = 'Нажми — я попробую другой способ.') { $bx = Glass 'ErrEdge'
  $g = New-Object Windows.Controls.Grid; Col $g 160; Col $g '*'; Col $g 'Auto'; foreach ($i in 0..2) { [void]$g.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{ Height = 'Auto' })) }
  $k = 0; foreach ($pr in @(@('Что случилось', $what), @('Твои файлы и настройки', $files), @('Что сделать', $todo))) { $a = Tx $pr[0] 13 'Dim'; $a.Margin = '0,3,10,3'; [void](Put $g $a 0 $k)
    $b = Tx $pr[1] 13 'Text'; $b.Margin = '0,3'; $b.VerticalAlignment = 'Center'; [void](Put $g $b 1 $k); if ($k -lt 2) { [Windows.Controls.Grid]::SetColumnSpan($b, 2) }; $k++ }
  $bt = Btn $btn $click; $bt.Margin = '10,0,0,0'; [void](Put $g $bt 2 2); $bx.Child = $g; [void](Px $p 'After').Children.Add($bx); Rise $bx 150 400 }
# Подсказка: части текста (тёплые — жирные) и кнопка справа
function Tip($p, $parts, $btn, $click) { $bx = Glass 'Edge' '16,12'; $g = New-Object Windows.Controls.Grid; Col $g '*'; Col $g 'Auto'
  $tb = Tx '' 13 'Dim'; $tb.LineHeight = 19; $tb.VerticalAlignment = 'Center'; foreach ($pt in $parts) { $rn = New-Object Windows.Documents.Run ($pt[0]); if ($pt[1]) { $rn.Foreground = T 'Warm'; $rn.FontWeight = 'SemiBold' }; $tb.Inlines.Add($rn) }
  [void](Put $g $tb 0); if ($btn) { $bt = Btn $btn $click; $bt.Margin = '12,0,0,0'; $bt.VerticalAlignment = 'Center'; [void](Put $g $bt 1) }; $bx.Child = $g; [void](Px $p 'After').Children.Add($bx); Rise $bx 150 400 }

# ---------- Луч маяка: к текущему шагу, гаснет в конце ----------
function Aim($el) { try { $pt = $el.TranslatePoint((New-Object Windows.Point(($el.ActualWidth - 10), ($el.ActualHeight / 2))), (G 'Root')) } catch { return }
  $x = [math]::Min($pt.X, 700); $a = [math]::Atan2($pt.Y - 232, $x - 842) * 180 / [math]::PI - 180; Tw (G 'BeamRot') $DP.A $a 900; Tw (G 'Beam') $DP.O 1 600; Tw (G 'Glow') $DP.O 1 600 }
function BeamOff { Tw (G 'BeamRot') $DP.A 0 900; Tw (G 'Beam') $DP.O 0 600; Tw (G 'Glow') $DP.O 0.6 600 }
# Рамка главной кнопки: вращающийся градиент, только во время работы
function BeamBorder($on) { $pb = G 'Pb'; $bm = $pb.Template.FindName('beam', $pb); if (-not $bm) { return }; if ($bm.BorderBrush.IsFrozen) { $bm.BorderBrush = $bm.BorderBrush.Clone() }; $rot = $bm.BorderBrush.RelativeTransform
  if ($on) { $bm.Opacity = 1; if ($script:calm) { $rot.Angle = 30 } else { Loop $rot $DP.A 0 360 2600 } } else { $rot.BeginAnimation($DP.A, $null); $bm.Opacity = 0 } }
# Блик главной кнопки: 3 прохода после появления, 1 — по наведению и фокусу
function Shine($n = 1) { if ($script:calm -or $script:R) { return }; $pb = G 'Pb'; $sh = $pb.Template.FindName('shine', $pb); if (-not $sh) { return }; if ($sh.RenderTransform.IsFrozen) { $sh.RenderTransform = $sh.RenderTransform.Clone() }
  $a = New-Object Windows.Media.Animation.DoubleAnimation(0, ($pb.ActualWidth + 220), [TimeSpan]::FromMilliseconds(1400)); $e = New-Object Windows.Media.Animation.CubicEase; $e.EasingMode = 'EaseInOut'; $a.EasingFunction = $e
  $a.RepeatBehavior = New-Object Windows.Media.Animation.RepeatBehavior($n); $sh.RenderTransform.Children[1].BeginAnimation($DP.X, $a) }

# ---------- Живая строка внизу: сменяется сдвигом ----------
$script:idle = $(if ($script:demo) { 'Помощник отдыхает. Сторожа следят за ноутбуком.' } else { 'Помощник отдыхает. Нажми карточку — покажу каждый шаг.' })
function LiveText($t) { $tb = G 'LiveTx'; if ($tb.Text -eq $t) { return }; $m = G 'LiveTxMove'
  if ($script:calm -or -not $tb.Text) { $tb.Text = $t; return }; $script:liveNext = $t; Tw $m $DP.Y -18 200; Tw $tb $DP.O 0 200
  Later 220 { $tb = G 'LiveTx'; $tb.Text = $script:liveNext; Tw (G 'LiveTxMove') $DP.Y 0 400 'out' 18; Tw $tb $DP.O 1 400 'out' 0 } }
function LiveBusy($on) { $d = G 'LiveDot'; $d.Fill = T $(if ($on) { 'Warm' } else { 'Acc' }); if ($on) { Loop $d $DP.O 1 0.3 500 $true } else { $d.BeginAnimation($DP.O, $null); $d.Opacity = 1 } }
$script:snackId = 0
function Snack($t, [int]$hold = 3000) { $script:snackId++; $script:snackOn = $true; LiveText $t; if ($script:noTimer) { return }
  Later $hold ([scriptblock]::Create("if (`$script:snackId -eq $($script:snackId)) { `$script:snackOn = `$false; LiveRefresh }")) }
function LiveRefresh { if ($script:snackOn) { return }; $b = G 'LiveBtn'; $b.Visibility = 'Collapsed'
  if ($script:upd) { $u = $script:upd; LiveText $u.Msg; LiveBusy $u.Busy; if ($u.Done) { (G 'LiveBtnTx').Text = 'Перезапустить'; $b.Tag = 'restart'; $b.Visibility = 'Visible' }; return }
  $r = $script:run; $act = $r -and (RunSeen); $busy = $r -and $script:runTimer.IsEnabled
  if ($r -and -not $act -and ($busy -or ($r.Res -and -not $r.Seen))) {
    LiveText $(if ($script:asking) { "Ждёт твой ответ: $($r.Title)" } elseif ($busy) { "Идёт: $($r.Title)" } elseif ($r.Res -eq 'ok') { "Готово: $($r.Title)" } else { "Прервалось: $($r.Title)" })
    LiveBusy $busy; (G 'LiveBtnTx').Text = 'Показать'; $b.Tag = 'show'; $b.Visibility = 'Visible'; return }
  if ($busy) { LiveText $(if ($script:asking) { 'Жду твой ответ — вопрос на экране.' } elseif ($r.Live -and $r.Open) { $c = $r.Steps[$r.Cur]; 'Сейчас: ' + (Low $c.N) + $(if ($c.Hint) { ' — ' + (Low $c.Hint) }) + '…' } else { "Сейчас: $(Low $r.Title)…" }); LiveBusy $true; return }
  if ($act -and $r.Res -eq 'bad' -and ($r.P -ne 'h' -or $script:homeDone)) { LiveText 'Не получилось. Что делать — на экране.'; LiveBusy $false; return }
  if ($script:tgBusy) { LiveText "Сейчас: $(if ($script:tgOn) { 'включаю' } else { 'выключаю' }) обход заблокированных сайтов…"; LiveBusy $true; return }
  if ($null -ne $script:gBusy) { LiveText "Сейчас: $(if ($script:gWant) { 'включаю' } else { 'выключаю' }) «$($guards[$script:gBusy].N)»…"; LiveBusy $true; return }
  if ($script:bg -and -not $script:R) { $j = $script:bg; LiveText ('Сейчас в фоне: ' + (Low $j.step) + $(if ($j.hint) { ' — ' + (Low $j.hint) }) + '…'); LiveBusy $true; (G 'LiveBtnTx').Text = 'Показать'; $b.Tag = 'guards'; if ($script:page -ne 'guards') { $b.Visibility = 'Visible' }; return }
  if (-not $script:R) { LiveText $script:idle; LiveBusy $false } }

# ---------- Шторка ----------
$script:nav = @{}; $script:navKeys = @($pages.Keys)
foreach ($k in $script:navKeys) { $b = G "Nav_$k"; $b.Add_Click({ param($s, $e) Go $s.Tag }); $script:nav[$k] = @{ B = $b; I = (G "NavI_$k"); L = (G "NavL_$k"); D = (G "NavD_$k") } }
function NavMark($k) { $i = [array]::IndexOf($script:navKeys, $k); Tw (G 'PillMove') $DP.Y ($i * 52) 450 'spring'
  foreach ($n in $script:navKeys) { $x = $script:nav[$n]; if ($n -eq $k) { $x.L.Foreground = T 'Text'; $x.I.Foreground = T 'Acc' } else { $x.L.ClearValue([Windows.Controls.TextBlock]::ForegroundProperty); $x.I.ClearValue([Windows.Controls.TextBlock]::ForegroundProperty) } } }
# Точка у раздела, где идёт работа, если смотришь другой
function BadgeSync { $rk = $null; if ($script:R) { $rk = $(if ($script:R.P -eq 'h') { 'home' } else { $script:actPage }) } elseif ($script:run -and $script:runTimer.IsEnabled) { $rk = $script:run.Page } elseif ($script:bg) { $rk = 'guards' }
  foreach ($n in $script:navKeys) { $d = $script:nav[$n].D; if ($n -eq $rk -and $n -ne $script:page) { $d.Opacity = 1; Loop $d $DP.O 1 0.3 500 $true } else { $d.BeginAnimation($DP.O, $null); $d.Opacity = 0 } } }
$script:drawerOpen = $true
function DrawerSet($open) { $script:drawerOpen = $open; $k = $(if ($open) { 1 } else { 0 }); $dx = $(if ($open) { 0 } else { -148 })
  Tw (G 'DrawerScale') $DP.SX $(if ($open) { 1 } else { 64 / 212 }) 350; Tw (G 'EdgeShift') $DP.X $dx 350; Tw (G 'PillScale') $DP.SX $(if ($open) { 1 } else { 44 / 192 }) 350
  Tw (G 'ViewShift') $DP.X $dx 350; Tw (G 'LiveMove') $DP.X $dx 350
  foreach ($e in @((G 'BrandTx'), (G 'VerBtn'))) { Tw $e $DP.O $k 200 }; (G 'VerBtn').IsHitTestVisible = $open; (G 'VerBtn').Focusable = $open
  foreach ($n in $script:navKeys) { $x = $script:nav[$n]; Tw $x.L $DP.O $k 200; $x.B.Width = $(if ($open) { 192 } else { 44 }); $x.B.Padding = $(if ($open) { '16,0' } else { '13,0' }); Tw $x.D.RenderTransform $DP.X $(if ($open) { 0 } else { -4 }) 300; Tw $x.D.RenderTransform $DP.Y $(if ($open) { 0 } else { -10 }) 300 }
  (G 'BtnMenu').ToolTip = $(if ($open) { 'Свернуть шторку' } else { 'Развернуть шторку' }) }

# ---------- Экраны ----------
# Экран хода: отметка шторки — на разделе, куда ведёт «назад», даже если карточку нажали на главной
function Show($v) { if ($v -eq 'VAct' -and $script:actPage) { $script:page = $script:actPage; NavMark $script:actPage }
  foreach ($n in @('VHome', 'VAct', 'VSec')) { $e = G $n; $on = $n -eq $v; $was = $e.Visibility -eq 'Visible'; $e.Visibility = $(if ($on) { 'Visible' } else { 'Collapsed' }); if ($on -and -not $was) { Rise $e 0 300 } }
  (G 'VTiles').Visibility = $(if ($v -eq 'VSec' -and $script:secK -eq 'speed') { 'Visible' } else { 'Collapsed' }); LiveRefresh; BadgeSync }
function Go($k) { SideClose; $was = $script:page; $script:page = $k; NavMark $k
  # Вернулась на главную после увиденного итога проверки — снова покой с карточками
  if ($k -eq 'home') { if ($was -ne 'home' -and $script:homeDone -and $script:run.Seen) { HomeIdle } elseif ($script:homeDone -and $script:run.P -eq 'h') { $script:run.Seen = $true }; Show 'VHome'; return }
  if ($script:R -and $script:R.P -eq 'a' -and $script:actPage -eq $k -and -not $script:force) { Show 'VAct'; return }
  $script:force = $false; SecShow $k; Show 'VSec' }
function PageOf($it) { foreach ($k in $tools.Keys) { foreach ($t in $tools[$k]) { if ([object]::ReferenceEquals($t, $it)) { return $k } } }; 'home' }

# Карточка-выбор нового вида: подсветка за курсором, подъём, нажатие
# Карточка-выбор нового вида (разметка — в XAML окна): подсветка за курсором, подъём, нажатие
function DCard($b, $it) { $b.Tag = $it
  $b.Add_MouseMove({ param($s, $e) $rc = $s.Content.Children[0]; $p = $e.GetPosition($rc); $rc.Fill.Center = $p; $rc.Fill.GradientOrigin = $p })
  $b.Add_MouseEnter({ param($s, $e) Tw (Tf $s).Children[1] $DP.Y -3 300 'spring'; $t = $s.Content.Children[1].Children[0].RenderTransform; Tw $t.Children[0] $DP.A -8 350 'spring'; Tw $t.Children[1] $DP.SX 1.08 350 'spring'; Tw $t.Children[1] $DP.SY 1.08 350 'spring' })
  $b.Add_MouseLeave({ param($s, $e) $rc = $s.Content.Children[0]; $rc.Fill.Center = '-200,-200'; $rc.Fill.GradientOrigin = '-200,-200'; Tw (Tf $s).Children[1] $DP.Y 0 300; $t = $s.Content.Children[1].Children[0].RenderTransform; Tw $t.Children[0] $DP.A 0 350; Tw $t.Children[1] $DP.SX 1 350; Tw $t.Children[1] $DP.SY 1 350 })
  $b.Add_Click({ param($s, $e) CardClick $s.Tag $s }); Press $b }
function DChip($i, $text, $ok) { (G "ChipT$i").Text = $text; (G "ChipD$i").Fill = T $(if ($ok) { 'Acc' } else { 'Dim' }) }
function Ping($i) { if ($script:calm) { return }; $pg = G "ChipP$i"; $st = $pg.RenderTransform; foreach ($pp in @($DP.SX, $DP.SY)) { $a = New-Object Windows.Media.Animation.DoubleAnimation(1, 3.2, [TimeSpan]::FromMilliseconds(1000)); $a.RepeatBehavior = New-Object Windows.Media.Animation.RepeatBehavior(3); $st.BeginAnimation($pp, $a) }
  $a = New-Object Windows.Media.Animation.DoubleAnimation(0.9, 0, [TimeSpan]::FromMilliseconds(1000)); $a.RepeatBehavior = New-Object Windows.Media.Animation.RepeatBehavior(3); $pg.BeginAnimation($DP.O, $a) }
function FillChips { if ($script:demo) { DChip 0 'Обход: выключен' $false; DChip 1 'Happ: не подключён' $false; DChip 2 'Сторожа: работают' $true; return }
  $hp = [bool]([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() | Where-Object Port -eq (PctSocksPort)); $z = [bool](Get-Process winws); $pc = PacOn
  DChip 0 $(if ($z) { 'Обход: включён' } else { 'Обход: выключен' }) $z; DChip 1 $(if ($hp) { 'Happ: подключён' } else { 'Happ: не подключён' }) $hp; DChip 2 $(if ($pc) { 'Сайты через Happ: вкл' } else { 'Сайты через Happ: выкл' }) $pc }
function Hello { $h = (Get-Date).Hour; if ($h -lt 5) { 'Доброй ночи!' } elseif ($h -lt 12) { 'Доброе утро!' } elseif ($h -lt 18) { 'Добрый день!' } else { 'Добрый вечер!' } }

# ---------- Главная: покой · идёт · итог · ошибка · остановлено ----------
function SetBtn($t, $s, $ico, $glyph) { (G 'PTx').Text = $t; (G 'PSx').Text = $s; $i = G 'PIco'; $i.Text = $ico
  if ($glyph) { $i.FontFamily = T 'Ico'; $i.FontWeight = 'Normal' } else { $i.FontFamily = $win.FontFamily; $i.FontWeight = 'SemiBold' } }
function Ring($f) { $rg = G 'Rg'; $rg.Opacity = $(if ($f -gt 0) { 1 } else { 0 }); Tw $rg $DP.D (31.42 * (1 - $f)) 600 }
function HomeReset { (G 'Hello').Text = Hello; (G 'HSub').Text = 'Всё для ноутбука в одном месте. Нажми карточку — остальное я сделаю сам и покажу каждый шаг.'
  (G 'HCards').Visibility = 'Visible'; (G 'HRun').Visibility = 'Collapsed'; (G 'HSum').Visibility = 'Collapsed'; (G 'HAfter').Children.Clear(); (G 'HLogBox').Visibility = 'Collapsed'; Tw (G 'HLogR') $DP.A 0 0
  SetBtn 'Проверить ноутбук' 'Найду, что не так, и скажу, что делать' (Ch 0xE9D9) $true; (G 'Rg').Opacity = 0; (G 'Rg').BeginAnimation($DP.D, $null); (G 'Rg').StrokeDashOffset = 31.42
  # Данных о прошлой проверке нет — без образца строки нет
  (G 'LastTx').Text = $(if ($script:demo) { 'Последняя проверка — 3 дня назад: всё было хорошо.' } else { '' }); (G 'LastRow').Visibility = $(if ($script:demo) { 'Visible' } else { 'Collapsed' }); FillChips }
# Итог настоящей проверки скрыт: покой с карточками, главная кнопка помнит проверку
$script:homeDone = $false
function HomeIdle { HomeReset; SetBtn 'Проверить ещё раз' 'Последняя проверка — только что' (Ch 0xE9D9) $true; $script:homeDone = $false }
function HomeRun($err) { Go 'home'; (G 'HCards').Visibility = 'Collapsed'; (G 'HRun').Visibility = 'Visible'; Ring 0
  (G 'HSub').Text = 'Проверяю ноутбук. Каждый шаг — прямо здесь, можно не ждать.'; BeamBorder $true; RunStart 'h' (DemoHome) @{ Fail = $err } }
function HomeDone($tm, $err) { Ring 1; SetBtn 'Проверить ещё раз' 'Последняя проверка — только что' (Ch 0xE9D9) $true
  if (-not $err) { (G 'HSub').Text = 'Проверил. Ниже — итог и один совет.'; Summary 'h' 'ok' (Chk 24) 'Всё хорошо, кроме одного' "5 шагов за $tm"
    Tip 'h' @(@('Совет: ', $true), @('лишняя программа в автозапуске замедляет включение.', $false)) 'Убрать' { Snack 'Образец: здесь откроется «Что запускается с Windows».' }
    (G 'ChipT2').Text = 'Проверка: всё хорошо'; Ping 2 }
  else { (G 'HSub').Text = 'Проверил. Одно не работает — ниже, что делать.'; Summary 'h' 'bad' (Chk 24 'Err' $true) 'YouTube и Discord не открываются' "4 из 5 в порядке · $tm"
    ErrCard 'h' 'YouTube и Discord не открываются через нынешний способ обхода.' 'Подобрать обход' { $t = $tools.net[0]; AskAct $t (DemoTool $t[1]) } } }

# ---------- Показ по шагам (образец): общий ход для главной (h) и экрана хода (a) ----------
$script:R = $null
$script:rt = New-Object Windows.Threading.DispatcherTimer; $script:rt.Interval = [TimeSpan]::FromMilliseconds(250)
function RunStart($p, $steps, $o) { $n = $(if ($null -ne $o.FailAt) { $o.FailAt + 1 } else { $steps.Count })
  $script:R = @{ P = $p; Steps = $steps; Cur = -1; T0 = Get-Date; St0 = Get-Date; N = $n; FailAt = $o.FailAt; FailText = $o.FailText; Fail = $o.Fail; Wait = $false }
  (Px $p 'Sum').Visibility = 'Collapsed'; (Px $p 'Box').Visibility = 'Visible'; (Px $p 'After').Children.Clear(); (Px $p 'Head').Text = 'Что сейчас делаю'; (Px $p 'Clock').Text = ''; (Px $p 'List').Children.Clear(); LogReset $p
  LiveBusy $true; BadgeSync; StepStart 0; if (-not $script:noTimer) { $script:rt.Start() } }
function StepStart($i) { $r = $script:R; $p = $r.P; $s = $r.Steps[$i]; $l = Px $p 'List'
  if ($i -gt 0) { $pv = $r.Steps[$i - 1]; [void](RowSet $r ($i - 1) 'done'); LogLine $p "готово: $($pv.D) — $($pv.R)" }
  $row = StepRow $r $s 'now'; if ($i -eq 0) { $row.BorderThickness = 0 }; [void]$l.Children.Add($row); Rise $row 0 400; $r.Cur = $i; $r.St0 = Get-Date; LogLine $p "начал: $($s.N)"
  if ($p -eq 'h') { SetBtn "Проверяю… $($i + 1) из $($r.Steps.Count)" 'Нажми, чтобы остановить' "$($i + 1)" $false; Ring ($i / $r.Steps.Count) }
  LiveText $(if ($s.Ask) { 'Жду твой ответ — вопрос на экране.' } else { 'Сейчас: ' + (Low $s.N) + $(if ($s.Hint) { ' — ' + (Low $s.Hint) }) + '…' })
  $win.UpdateLayout(); Aim $row; if ($s.Ask) { $r.Wait = $true; LiveBusy $false; ShowAsk $p $s } }
function Clock($r) { $s = [int][math]::Floor(((Get-Date) - $r.T0).TotalSeconds); (Px $r.P 'Clock').Text = 'идёт {0}:{1:00}' -f [math]::Floor($s / 60), ($s % 60)
  if ($r.Sec) { $r.Sec.Text = "$([int][math]::Floor(((Get-Date) - $r.St0).TotalSeconds)) с" } }
function StepNext { $r = $script:R; if ($r.Cur + 1 -lt $r.N) { StepStart ($r.Cur + 1) } else { Finish } }
$script:rt.Add_Tick({ $r = $script:R; if (-not $r) { $script:rt.Stop(); return }; Clock $r; if (-not $r.Wait -and ((Get-Date) - $r.St0).TotalMilliseconds -ge $r.Steps[$r.Cur].Ms) { StepNext } })
function EndCommon { $r = $script:R; $sec = [int][math]::Round(((Get-Date) - $r.T0).TotalSeconds); $script:rt.Stop(); if ($r.Spin) { $r.Spin.BeginAnimation($DP.A, $null) }
  BeamOff; BeamBorder $false; LiveBusy $false; $script:R = $null; BadgeSync; $script:lastSec = $sec }
function Finish { $r = $script:R; $L = $r.N - 1; $last = $r.Steps[$L]; $f = ($null -ne $r.FailAt) -or $r.Fail; $ft = $(if ($r.FailText) { $r.FailText } else { $last.BadR })
  [void](RowSet $r $L $(if ($f) { 'fail' } else { 'done' }) $r.FailText); LogLine $r.P $(if ($f) { "ошибка: $($last.D) — $ft" } else { "готово: $($last.D) — $($last.R)" }) $(if ($f) { 'Err' })
  EndCommon; $sec = $script:lastSec; $tm = '{0}:{1:00}' -f [math]::Floor($sec / 60), ($sec % 60)
  LiveText $(if ($f) { 'Не получилось. Что делать — на экране.' } else { "Готово за $tm. Помощник отдыхает." }); $script:fin = @{ R = $r; Tm = $tm; L = $L; F = $f }; Later 700 { FinishShow } }
# Новый показ начался за эти 0,7 с — итог прошлого не рисуем
function FinishShow { if ($script:R) { return }; $x = $script:fin; $r = $x.R; $p = $r.P
  if ($null -ne $r.FailAt) { (Px $p 'Head').Text = 'Что я успел'; (Px $p 'Clock').Text = ''; ActFailed $x.Tm $x.L; return }
  (Px $p 'Box').Visibility = 'Collapsed'; if ($p -eq 'h') { HomeDone $x.Tm $r.Fail } else { ActDone $x.Tm } }
function StopRun { $r = $script:R; if (-not $r) { return }; $p = $r.P; $i = $r.Cur; EndCommon; (Px $p 'After').Children.Clear(); LogLine $p "остановлено тобой на шаге $($i + 1)"
  if ($i -ge 0) { [void](RowSet $r $i 'stop') }; for ($k = $i + 1; $k -lt $r.Steps.Count; $k++) { [void](Px $p 'List').Children.Add((StepRow $r $r.Steps[$k] 'wait')) }
  (Px $p 'Head').Text = 'Что я успел'; (Px $p 'Clock').Text = ''
  Summary $p 'idle' (Ic (Ch 0xE769) 18 'Dim') 'Остановил' "Сделано $([math]::Max($i, 0)) из $($r.Steps.Count) · ничего не изменено"; LiveText "Остановлено на шаге $($i + 1) из $($r.Steps.Count)."
  if ($p -eq 'h') { SetBtn 'Проверить заново' 'Начну с первого шага' (Ch 0xE768) $true; (G 'HSub').Text = 'Остановил. Ничего не изменено.' }
  else { ActCtl @(@((Ch 0xE768), 'Начать заново', { ActAgain }), @($null, 'Назад', { BackFromAct })) } }
# Вопрос к ней посреди работы: работа ждёт ответа
function ShowAsk($p, $s) { $a = $s.Ask; $bx = Glass 'WarmEdge'; $st = New-Object Windows.Controls.StackPanel
  $q = New-Object Windows.Controls.Grid -Property @{ Margin = '0,0,0,8' }; Col $q 'Auto'; Col $q '*'; $qi = Ic (Ch 0xE897) 15 'Warm'; $qi.Margin = '0,0,10,0'; [void](Put $q $qi 0); [void](Put $q (Tx $a.Q 15 'Text' 'SemiBold') 1); [void]$st.Children.Add($q)
  $n = 0; foreach ($it in $a.Items) { $row = New-Object Windows.Controls.Border -Property @{ Padding = '0,6'; BorderBrush = (T 'Line'); BorderThickness = $(if ($n) { '0,1,0,0' } else { '0' }) }
    $g = New-Object Windows.Controls.Grid; Col $g 'Auto'; Col $g '*'; $cb = CiBox (Glyph $it[0]) 28 13 8; $cb.VerticalAlignment = 'Center'; [void](Put $g $cb 0)
    $ts = New-Object Windows.Controls.StackPanel -Property @{ Margin = '10,0,0,0'; VerticalAlignment = 'Center' }; [void]$ts.Children.Add((Tx $it[1] 13)); [void]$ts.Children.Add((Tx $it[2] 12 'Dim')); [void](Put $g $ts 1); $row.Child = $g; [void]$st.Children.Add($row); $n++ }
  $bs = New-Object Windows.Controls.WrapPanel -Property @{ Margin = '0,12,0,0' }
  $y = Btn $a.Yes[0] ([scriptblock]::Create("DemoAnswer '$($a.Yes[1])'")) 'GBtnAcc'; $no = Btn $a.No[0] ([scriptblock]::Create("DemoAnswer '$($a.No[1])'")); $hp = Btn 'Не знаю — позвать помощь' { Snack 'Образец: здесь откроется «Позвать помощь».' }
  foreach ($b in @($y, $no, $hp)) { $b.Margin = '0,0,8,8'; [void]$bs.Children.Add($b) }; [void]$st.Children.Add($bs); $bx.Child = $st; [void](Px $p 'After').Children.Add($bx); Rise $bx 0 400; [void]$y.Focus() }
function DemoAnswer($ans) { $r = $script:R; if (-not $r -or -not $r.Wait) { return }; $r.Steps[$r.Cur].R = $ans; (Px $r.P 'After').Children.Clear(); $r.Wait = $false; LiveBusy $true; LogLine $r.P "твой ответ: $ans"; StepNext }

# ---------- Экран хода ----------
function ActCtl($items) { $c = G 'ACtl'; $c.Children.Clear(); foreach ($i in $items) { [void]$c.Children.Add((Btn $i[1] $i[2] 'GBtn' $i[0])) } }
function ActHead($it) { $k = PageOf $it; $script:actPage = $k; (G 'ABackTx').Text = $pages[$k][1]; (G 'AIco').Text = Glyph $it[0]; (G 'ATitle').Text = $it[1]; (G 'ASub').Text = $it[2] }
function AskAct($it, $d) { if ($script:R -or ($script:run -and $script:runTimer.IsEnabled)) { Snack 'Сначала дождись конца или останови текущее дело.'; return }
  if ($d.Risk) { $script:pend = @($it, $d); Cfm "$($it[1])?" $d.Risk[0] $d.Risk[1] 'Да, начать' 'Отмена' { OpenAct $script:pend[0] $script:pend[1] } } else { OpenAct $it $d } }
function OpenAct($it, $d) { if ($script:R) { return }; $script:curTool = $it; ActHead $it
  ActCtl (,@((Ch 0xE769), 'Остановить', { StopRun })); (G 'ALogBox').Visibility = 'Collapsed'; Tw (G 'ALogR') $DP.A 0 0; Show 'VAct'
  $uac = $d.Steps[0].Uac; $o = @{}; if ($script:out -eq 'deny' -and $uac) { $o = @{ FailAt = 0; FailText = 'ты нажала «Нет»' } }
  if ($script:out -eq 'fail') { $fi = [math]::Min($d.Steps.Count - 1, $(if ($uac) { 2 } else { 1 })); while ($d.Steps[$fi].Ask -and $fi -lt $d.Steps.Count - 1) { $fi++ }; $o = @{ FailAt = $fi; FailText = 'не получилось' } }
  $script:curD = $d; RunStart 'a' $d.Steps $o }
function ActAgain { $t = $script:curTool; OpenAct $t (DemoTool $t[1]) }
function ActFailed($tm, $L) { $d = $script:curD
  if ($script:out -eq 'deny') { Summary 'a' 'idle' (Ic (Ch 0xE7EF) 18 'Warm') 'Windows не дал разрешение' 'Ты нажала «Нет» — я ничего не менял'
    Tip 'a' @(@('Без разрешения Windows этот инструмент не работает. Нажми «Ещё раз» и в окне Windows выбери ', $false), @('«Да»', $true), @('.', $false)) }
  else { Summary 'a' 'bad' (Chk 24 'Err' $true) 'Не получилось до конца' "Шаг «$($d.Steps[$L].D)» — $($L + 1) из $($d.Steps.Count) · $tm"
    ErrCard 'a' "Шаг «$($d.Steps[$L].D)» не прошёл: Windows вернул ошибку." 'Позвать помощь' { Snack 'Образец: здесь откроется «Позвать помощь».' } 'Всё на месте: я остановился до изменений.' 'Нажми «Ещё раз». Не выйдет — позови помощь.' }
  ActCtl @(@((Ch 0xE72C), 'Ещё раз', { ActAgain }), @($null, 'Назад', { BackFromAct })) }
function ActDone($tm) { $d = $script:curD; if ($d.Part) { Summary 'a' 'idle' (Ic (Ch 0xE946) 18 'Warm') $d.Ok "$($d.OkSub) · $tm" } else { Summary 'a' 'ok' (Chk 24) $d.Ok "$($d.OkSub) · $tm" }
  ActCtl @(@((Ch 0xE72C), 'Ещё раз', { ActAgain }), @($null, 'Готово', { BackFromAct })) }
function BackFromAct { $script:force = $true; Go $script:actPage }

# ---------- Подтверждение рискованного шага: что сделаю · как вернуть ----------
# -Safe: фокус на «нет» (выключение нужного сторожа)
function Cfm($title, $what, $undo, $yes, $no, [scriptblock]$onYes, [switch]$Safe) { (G 'CfmT').Text = $title; (G 'CfmW').Text = $what; (G 'CfmU').Text = $undo; (G 'CfmYt').Text = $yes; (G 'CfmNt').Text = $no; $script:cfmYes = $onYes
  $c = G 'Cfm'; $c.Visibility = 'Visible'; Tw $c $DP.O 1 300 'out' 0; Tw (G 'CfmScale') $DP.SX 1 450 'spring' 0.94; Tw (G 'CfmScale') $DP.SY 1 450 'spring' 0.94; [void](G $(if ($Safe) { 'CfmN' } else { 'CfmY' })).Focus() }
function CfmClose { (G 'Cfm').Visibility = 'Collapsed' }
(G 'CfmY').Add_Click({ CfmClose; & $script:cfmYes }); (G 'CfmN').Add_Click({ CfmClose })
(G 'Cfm').Add_MouseLeftButtonDown({ param($s, $e) if ([object]::ReferenceEquals($e.OriginalSource, $s)) { CfmClose } })
Press (G 'CfmY'); Press (G 'CfmN')

# ---------- Боковая панель ----------
function SideOpen { $sd = G 'Side'; $sd.Visibility = 'Visible'; $script:sideOn = $true; Tw (G 'SideMove') $DP.X 0 350; [void](G 'SideX').Focus() }
function SideClose { if (-not $script:sideOn) { return }; $script:sideOn = $false; Tw (G 'SideMove') $DP.X 390 350; Later 360 { if (-not $script:sideOn) { (G 'Side').Visibility = 'Collapsed' } } }
(G 'SideX').Add_Click({ SideClose })

# ---------- Разделы: карточки по группам, переключатель, сторожа (собираются при входе) ----------
$fragNS = 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
# Фрагмент разбирается отдельно от окна: ресурсы окна — через DynamicResource
function Frag($x) { [Windows.Markup.XamlReader]::Parse("<StackPanel $fragNS>$x</StackPanel>".Replace('StaticResource', 'DynamicResource')) }
function F($n) { $script:sec.FindName($n) }
# Переключатель: дорожка выкл · вкл · «жду ответ», кружок едет с пружиной
function SwX($n) { "<Button x:Name=`"$n`" Style=`"{StaticResource Plain}`" Padding=`"0`" Margin=`"12,0,0,0`" VerticalAlignment=`"Center`"><Grid Width=`"40`" Height=`"22`"><Border CornerRadius=`"11`" Background=`"{StaticResource SwOff}`"/>" +
  "<Border x:Name=`"${n}on`" CornerRadius=`"11`" Background=`"{StaticResource Acc}`" Opacity=`"0`"/><Border x:Name=`"${n}busy`" CornerRadius=`"11`" Background=`"{StaticResource WarmTrack}`" Opacity=`"0`"/>" +
  "<Ellipse x:Name=`"${n}k`" Width=`"16`" Height=`"16`" HorizontalAlignment=`"Left`" Margin=`"3,0,0,0`" Fill=`"{StaticResource Text}`"><Ellipse.RenderTransform><TranslateTransform/></Ellipse.RenderTransform></Ellipse></Grid></Button>" }
function SwSet($n, $on, $busy, $dead) { $sw = F $n; $sw.IsEnabled = -not $dead; $sw.Opacity = $(if ($dead) { 0.45 } else { 1 })
  Tw (F "${n}on") $DP.O $(if ($on -and -not $busy) { 1 } else { 0 }) 300; Tw (F "${n}busy") $DP.O $(if ($busy) { 1 } else { 0 }) 300
  $k = F "${n}k"; $k.Fill = T $(if ($on -and -not $busy) { 'Ink' } else { 'Text' }); Tw $k.RenderTransform $DP.X $(if ($on) { 18 } else { 0 }) 450 'spring' }
# Строка списка: значок, имя, одна строка состояния, справа — $right
function RowX($n, $glyph, $title, $right, $first) { "<Button x:Name=`"$n`" Style=`"{StaticResource Row}`"$(if ($first) { ' BorderThickness="0"' })><Grid><Grid.ColumnDefinitions><ColumnDefinition Width=`"Auto`"/><ColumnDefinition/><ColumnDefinition Width=`"Auto`"/></Grid.ColumnDefinitions>" +
  "<Border x:Name=`"${n}b`" Width=`"32`" Height=`"32`" CornerRadius=`"9`" VerticalAlignment=`"Center`"><TextBlock x:Name=`"${n}i`" Text=`"$glyph`" FontFamily=`"{StaticResource Ico}`" FontSize=`"15`" HorizontalAlignment=`"Center`" VerticalAlignment=`"Center`"/></Border>" +
  "<StackPanel Grid.Column=`"1`" Margin=`"12,0,0,0`" VerticalAlignment=`"Center`"><TextBlock Text=`"$(Xe $title)`" FontSize=`"14`" FontWeight=`"SemiBold`" TextWrapping=`"Wrap`"/><TextBlock x:Name=`"${n}s`" FontSize=`"12.5`" Foreground=`"{StaticResource Dim}`" TextWrapping=`"Wrap`"/></StackPanel>" +
  "<StackPanel Grid.Column=`"2`" Orientation=`"Horizontal`" VerticalAlignment=`"Center`">$right</StackPanel></Grid></Button>" }
function RowPaint($n, $on) { (F "${n}b").Background = T $(if ($on) { 'AccSoft' } else { 'DimSoft' }); (F "${n}i").Foreground = T $(if ($on) { 'Acc' } else { 'Dim' }) }
function Rows($x, $name) { "<Border x:Name=`"$name`" CornerRadius=`"12`" Background=`"{StaticResource Glass}`" BorderBrush=`"{StaticResource Edge}`" BorderThickness=`"1`" Padding=`"0,4`" Margin=`"0,0,0,10`"><StackPanel>$x</StackPanel></Border>" }

# Карточки раздела: переключатель сверху, группы с подписью, сетка 2 в ряд, wide — на весь ряд; высота рядов группы одинакова
function SecX($k) { $sb = New-Object Text.StringBuilder; $grs = [ordered]@{}; $script:secIt = New-Object Collections.ArrayList; $script:tgIt = $null
  foreach ($t in $tools[$k]) { if ($t[4] -eq 'toggle') { $script:tgIt = $t; continue }; $gn = "$($t[5])"; if (-not $grs.Contains($gn)) { $grs[$gn] = New-Object Collections.ArrayList }; [void]$grs[$gn].Add($t) }
  if ($script:tgIt) { [void]$sb.Append((Rows (RowX 'TG' $script:tgIt[0] $script:tgIt[1] (SwX 'TGt') $true) 'TgBox')) }
  $gi = 0; foreach ($gn in $grs.Keys) { if ($gn) { [void]$sb.Append("<TextBlock x:Name=`"Cap$gi`" Text=`"$(Xe $gn)`" FontSize=`"12`" Foreground=`"{StaticResource Dim}`" Margin=`"$(if ($gi) { '0,14,0,8' } else { '0,0,0,8' })`"/>") }
    $c = 0; $r = 0; $cells = New-Object Text.StringBuilder; $wr = @()
    foreach ($t in $grs[$gn]) { $w = $t[6] -eq 'wide'; if ($w -and $c) { $r++; $c = 0 }; if ($w) { $wr += $r }
      [void]$cells.Append((CardX $t $t[1] "C$($script:secIt.Count)" " Grid.Row=`"$r`" Grid.Column=`"$c`"$(if ($w) { ' Grid.ColumnSpan="2"' })")); [void]$script:secIt.Add($t)
      if ($w -or $c) { $r++; $c = 0 } else { $c = 1 } }
    # Ряд wide — по своему тексту, остальные ряды группы — одной высоты
    $rd = -join (0..($r + $c - 1) | ForEach-Object { if ($_ -in $wr) { '<RowDefinition Height="Auto"/>' } else { '<RowDefinition Height="Auto" SharedSizeGroup="R"/>' } })
    [void]$sb.Append("<Grid x:Name=`"Grp$gi`" Margin=`"-5`" Grid.IsSharedSizeScope=`"True`"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions><Grid.RowDefinitions>$rd</Grid.RowDefinitions>$cells</Grid>"); $gi++ }
  $sb.ToString() }

# Заблокированные сайты: строка с переключателем. Без образца — smart-proxy.ps1, как в main
function PacSt { if ($script:demo) { [bool]$script:pacDemo } else { PacOn } }
function TgPaint { if ($script:secK -ne 'net' -or -not $script:tgIt) { return }; $on = PacSt; RowPaint 'TG' $on
  (F 'TGs').Text = $(if ($script:tgBusy) { if ($on) { 'Выключаю…' } else { 'Включаю… подключаю Happ' } } elseif ($on) { 'Включено · сайты открываются через Happ' } else { 'Выключено · ' + $script:tgIt[2] }); SwSet 'TGt' $on $script:tgBusy $false }
function TgFlip { if ($script:tgBusy) { return }; $script:tgBusy = $true; $script:tgOn = -not (PacSt); TgPaint; LiveBusy $true
  LiveText $(if ($script:tgOn) { 'Сейчас: включаю обход заблокированных сайтов…' } else { 'Сейчас: выключаю обход заблокированных сайтов…' })
  if ($script:demo) { Later 1600 { $script:pacDemo = $script:tgOn; TgDone }; return }
  # smart-proxy.ps1 — отдельным процессом: окно не ждёт, итог — по таймеру
  try { $script:px = @{ P = (Start-Process $ps -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($tools.net[2][3])`" $(if ($script:tgOn) { '-On' } else { '-Off' })" -WindowStyle Hidden -PassThru -ErrorAction Stop); T0 = Get-Date }; $script:pxTimer.Start() }
  catch { TgDone } }
function TgDone { $script:tgBusy = $false; LiveBusy $false; TgPaint; Snack $(if (PacSt) { 'Заблокированные сайты: включено — обнови страницу' } else { 'Заблокированные сайты: выключено' }); Tick }
# Ждём не дольше 60 с; итог — по файлу-отметке, как раньше
$script:pxTimer = New-Object Windows.Threading.DispatcherTimer; $script:pxTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$script:pxTimer.Add_Tick({ $done = ((Get-Date) - $script:px.T0).TotalSeconds -gt 60; try { $done = $done -or $script:px.P.HasExited } catch {}; if ($done) { $script:pxTimer.Stop(); TgDone } })

# Сторожа: строки со своим переключателем, щелчок по строке — панель подробностей справа
function GuardsX { $sb = New-Object Text.StringBuilder; $i = 0
  foreach ($g in $guards) { $rc = $recCol[$g.Rec]; $chip = "<Border CornerRadius=`"10`" Padding=`"8,2`" Margin=`"12,0,0,0`" VerticalAlignment=`"Center`" Background=`"{StaticResource $($rc[0])}`"><TextBlock Text=`"$($recTxt[$g.Rec])`" FontSize=`"12`" Foreground=`"{StaticResource $($rc[1])}`"/></Border>"
    [void]$sb.Append((RowX "G$i" $g.I $g.N ($chip + (SwX "G${i}t")) (-not $i))); $i++ }
  Rows $sb.ToString() 'GBox' }
$script:gBusy = $null
function GPaint($i) { if ($script:secK -ne 'guards') { return }; $g = $guards[$i]; $st = $script:gs[$g.T]; $on = $st -eq 'on'; $busy = $script:gBusy -eq $i; RowPaint "G$i" $on
  $bw = $script:bg -and $g.Bg -eq $script:bg.name
  (F "G${i}s").Text = $(if ($bw -and -not $busy) { 'Работает: ' + (Low $script:bg.step) } elseif ($busy) { $(if ($on) { 'Выключаю…' } else { 'Включаю…' }) + ' жду ответ Windows' } else { $(switch ($st) { 'on' { 'Включён' } 'off' { 'Выключен' } default { 'Не найден' } }) + ' · ' + $g.S }); SwSet "G${i}t" $on $busy ($st -eq '?') }
function GuardSide($i) { $g = $guards[$i]; $st = $script:gs[$g.T]; $on = $st -eq 'on'; $l = G 'SideBody'; $l.Children.Clear(); $script:sideI = $i
  $h = New-Object Windows.Controls.Grid -Property @{ Margin = '0,6,30,0' }; Col $h 'Auto'; Col $h '*'; $cb = CiBox (Glyph $g.I) 44 20 12; $cb.VerticalAlignment = 'Center'; [void](Put $h $cb 0)
  $sp = New-Object Windows.Controls.StackPanel -Property @{ Margin = '12,0,0,0'; VerticalAlignment = 'Center' }; [void]$sp.Children.Add((Tx $g.N 18 'Text' 'SemiBold'))
  [void]$sp.Children.Add((Tx ('● Сейчас ' + $(switch ($st) { 'on' { 'включён' } 'off' { 'выключен' } default { 'не найден' } })) 13 $(if ($on) { 'Acc' } else { 'Dim' }))); [void](Put $h $sp 1); [void]$l.Children.Add($h); $script:sideHead = $h
  $rc = $recCol[$g.Rec]; $chip = New-Object Windows.Controls.Border -Property @{ CornerRadius = 10; Padding = '8,2'; Background = (T $rc[0]); HorizontalAlignment = 'Left'; Margin = '0,14,0,0' }; $chip.Child = Tx "Совет: $($recTxt[$g.Rec])" 12 $rc[1]; [void]$l.Children.Add($chip)
  foreach ($p in @(@('ЧТО ДЕЛАЕТ', $g.W), @('ЕСЛИ ВЫКЛЮЧИТЬ', $g.R), @('НАГРУЗКА', $g.L))) { $a = Tx $p[0] 12 'Dim' 'SemiBold'; $a.Margin = '0,16,0,6'; [void]$l.Children.Add($a); $b = Tx $p[1] 13.5 'Text'; $b.LineHeight = 20; [void]$l.Children.Add($b) }
  $bt = Btn $(if ($on) { 'Выключить' } else { 'Включить' }) ([scriptblock]::Create("GuardFlip $i")); $bt.HorizontalAlignment = 'Left'; $bt.Margin = '0,20,0,0'; $bt.IsEnabled = $st -ne '?' -and $null -eq $script:gBusy; [void]$l.Children.Add($bt); SideOpen }
function GSideSync($i) { $l = (G 'SideBody').Children; if ($script:sideOn -and $script:sideI -eq $i -and $l.Count -and [object]::ReferenceEquals($l[0], $script:sideHead)) { GuardSide $i } }
# Переключение: рекомендованного «нужен» — через подтверждение; окно не ждёт процесс, итог — по таймеру
function GuardFlip($i, $ok) { $g = $guards[$i]; $st = $script:gs[$g.T]; if ($st -eq '?') { return }
  if ($null -ne $script:gBusy) { Snack "Подожди: переключаю «$($guards[$script:gBusy].N)»."; return }
  $on = $st -ne 'on'
  if (-not $on -and $g.Rec -eq 2 -and -not $ok) { $script:gPend = $i; Cfm "Выключить «$($g.N)»?" "Выключу этого сторожа. $($g.R)" 'Включить обратно — этим же переключателем.' 'Выключить' 'Оставить включённым' { GuardFlip $script:gPend $true } -Safe; return }
  $script:gBusy = $i; $script:gWant = $on; GPaint $i; GSideSync $i; LiveBusy $true; LiveText "Сейчас: $(if ($on) { 'включаю' } else { 'выключаю' }) «$($g.N)»…"
  Later $(if ($script:demo) { 1400 } else { 60 }) { $i = $script:gBusy; $g = $guards[$i]
    if ($script:demo) { $script:gs[$g.T] = $(if ($script:gWant) { 'on' } else { 'off' }); GuardDone; return }
    try { $p = Start-Process $ps -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"$Hd\guard-toggle.ps1`" -Task `"$($g.T)`"" + $(if ($script:gWant) { ' -On' } else { '' })) -Verb RunAs -WindowStyle Hidden -PassThru -ErrorAction Stop }
    catch { $script:gBusy = $null; LiveBusy $false; GPaint $i; GSideSync $i; Snack 'Отменено: Windows не дал разрешение'; return }
    $script:tg = @{ G = $g; P = $p; T0 = Get-Date }; $script:tgTimer.Start() } }
function GuardDone { $i = $script:gBusy; $g = $guards[$i]; $script:gBusy = $null; LiveBusy $false; GPaint $i; GSideSync $i
  Snack ("«{0}» {1}." -f $g.N, $(if ($script:gs[$g.T] -eq 'on') { 'включён' } else { 'выключен' })) }

# Вход в раздел: разметка одним разбором, затем обработчики и появление по очереди
function SecShow($k) { $pg = $pages[$k]; (G 'STitle').Text = $pg[2]; (G 'SHand').Text = '  ' + $pg[4]; (G 'SSub').Text = $pg[3]; $script:secK = $k; if ($k -eq 'speed') { TilesOpen }
  if ($k -eq 'guards') { GuardScan; $script:sec = Frag (GuardsX) } else { $script:sec = Frag (SecX $k) }; (G 'SBody').Content = $script:sec
  if ($k -eq 'guards') { for ($i = 0; $i -lt $guards.Count; $i++) { $r = F "G$i"; $r.Tag = $i; $r.Add_Click({ param($s, $e) GuardSide $s.Tag })
      $t = F "G${i}t"; $t.Tag = $i; $t.Add_Click({ param($s, $e) $e.Handled = $true; GuardFlip $s.Tag }); GPaint $i }; Rise (F 'GBox') 0 400; return }
  if ($script:tgIt) { (F 'TG').Add_Click({ TgFlip }); (F 'TGt').Add_Click({ param($s, $e) $e.Handled = $true; TgFlip }); TgPaint; Rise (F 'TgBox') 0 400 }
  $n = 0; while ($c = F "Cap$n") { Rise $c (40 * $n) 400; $n++ }
  for ($j = 0; $j -lt $script:secIt.Count; $j++) { $c = F "C$j"; DCard $c $script:secIt[$j]; Rise $c (40 * $j) 500 } }

# ---------- Настоящий запуск (без PCT_DEMO): run.ps1, ход в том же экране хода ----------
$colors = @{ Green = 'Acc'; DarkGreen = 'Acc'; Red = 'Err'; DarkRed = 'Err'; Yellow = 'Warm'; DarkYellow = 'Warm'; White = 'Text' }
$script:run = $null
$script:runTimer = New-Object Windows.Threading.DispatcherTimer; $script:runTimer.Interval = [TimeSpan]::FromMilliseconds(150)
# Панель хода настоящего запуска: a — экран хода, h — главная («Проверить ноутбук»)
function RunP { $script:run.P }
function RunSeen { (G $(if ((RunP) -eq 'h') { 'VHome' } else { 'VAct' })).Visibility -eq 'Visible' }
function AddLine($color, $text) { if (-not "$text".Trim()) { return }; $c = $colors[$color]; if ($text -match '^\s*(===|—)') { $c = 'Text' }; LogLine (RunP) $text $c
  if ($text -match '^\s*\[!!\]') { $script:run.Bad++ }; if ($text -match '^\s*\[OK\]') { $script:run.Ok++ }; if ($script:run.HintTb -and -not $script:run.Live -and -not $script:asking) { $script:run.HintTb.Text = $text.Trim() } }
function Answer($a) { if (-not $script:run) { return }; [IO.File]::WriteAllText($script:run.Ans, "$a", (New-Object Text.UTF8Encoding $false)); (Px (RunP) 'After').Children.Clear(); $script:asking = $false; LiveRefresh }
function Ask($prompt) { $ctx = @((Px (RunP) 'Log').Children | Select-Object -Last 2 | ForEach-Object { ($_.Inlines | Select-Object -Last 1).Text.Trim() })
  $q = (@($ctx) + @("$prompt".Trim()) | Where-Object { $_ }) -join "`n"; if (-not $q) { $q = 'Ответь и нажми «Ответить».' }; $yn = $q -match 'д и |Напиши д|\(д/н\)|\[д/н\]|1 и Enter'
  $bx = Glass 'WarmEdge'; $st = New-Object Windows.Controls.StackPanel; $h = New-Object Windows.Controls.StackPanel -Property @{ Orientation = 'Horizontal'; Margin = '0,0,0,8' }; $hi = Ic (Ch 0xE897) 15 'Warm'; $hi.Margin = '0,0,10,0'
  [void]$h.Children.Add($hi); [void]$h.Children.Add((Tx 'Нужен твой ответ' 15 'Text' 'SemiBold')); [void]$st.Children.Add($h); [void]$st.Children.Add((Tx $q 13 'Text'))
  $bs = New-Object Windows.Controls.WrapPanel -Property @{ Margin = '0,12,0,0' }
  if ($yn) { $f = Btn 'Да' { Answer 'д' } 'GBtnAcc'; [void]$bs.Children.Add($f); [void]$bs.Children.Add((Btn 'Нет' { Answer '' })) }
  else { $f = New-Object Windows.Controls.TextBox -Property @{ Name = 'AskIn'; Width = 260; Height = 32; Margin = '0,0,8,0'; FontSize = 14; Background = (T 'Field'); Foreground = (T 'Text'); BorderBrush = (T 'Edge'); CaretBrush = (T 'Text'); VerticalContentAlignment = 'Center'; Padding = '8,0' }
    $f.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { Answer $s.Text } }); [void]$bs.Children.Add($f); $ok = Btn 'Ответить' { Answer $script:askIn.Text } 'GBtnAcc'; $script:askIn = $f; [void]$bs.Children.Add($ok) }
  [void]$st.Children.Add($bs); $bx.Child = $st; $a = Px (RunP) 'After'; $a.Children.Clear(); [void]$a.Children.Add($bx); Rise $bx 0 400; $script:asking = $true
  if ($script:run.HintTb) { $script:run.HintTb.Text = 'Вопрос — ниже' }; [void]$f.Focus(); Snack 'Нужен твой ответ'; LiveRefresh }
# Итог настоящего запуска: ok — строка E; bad — процесс вышел без E; nostart — журнал не появился за 25 с
# Шаг закрыт с ошибкой (S|fail) — итог fail, даже если инструмент дошёл до конца. С шагами замечания — шаги S|warn, а не строки [!!]
function RealEnd($res, $sec) { $r = $script:run; $p = $r.P; $script:runTimer.Stop(); if ($res -eq 'ok' -and $r.Failed) { $res = 'fail' }
  if ($r.Live) { RealClose $(if ($res -eq 'ok') { 'done' } else { 'fail' }) $(if ($res -eq 'ok') { '' } else { 'прервалось' }); $r.Bad = [int]$r.Warns }; if ($r.Spin) { $r.Spin.BeginAnimation($DP.A, $null) }; BeamOff; (Px $p 'After').Children.Clear(); $script:asking = $false
  $r.Res = $(if ($res -eq 'ok') { 'ok' } else { 'bad' }); $r.Seen = RunSeen; (Px $p 'Head').Text = 'Что я сделал'; (Px $p 'Clock').Text = ''; $l = Px $p 'List'
  # С шагами список остаётся: при успехе без невыполненных ○, при сбое ○ — что не успел
  if ($r.Live) { if ($res -eq 'ok') { while ($l.Children.Count -gt $r.Cur + 1) { $l.Children.RemoveAt($l.Children.Count - 1) } } }
  else { $l.Children.Clear(); $s = @{ D = $(if ($res -eq 'ok') { 'Готово' } else { $r.Title }); R = "за $sec с" }; $r.Steps = @($s) }
  if ($p -eq 'h') { $script:homeDone = $true; BeamBorder $false; SetBtn 'Проверить ещё раз' 'Последняя проверка — только что' (Ch 0xE9D9) $true
    (G 'HSub').Text = $(if ($res -ne 'ok') { 'Проверка прервалась. Что делать — ниже.' } elseif ($r.Bad) { 'Проверил. Есть замечания — подробности ниже.' } else { 'Проверил. Итог — ниже.' }) }
  if ($res -eq 'ok') { if (-not $r.Live) { [void]$l.Children.Add((StepRow $r $s 'done')) }; (Px $p 'Box').Visibility = 'Collapsed'
    # «Большая уборка», «Энергосбережение», «Мышь и тачпад» и «Почему тормозит»: итог последнего шага («освобождено N · свободно …», «поменял N · было → стало», «главная причина: …») виден на карточке без «Показать шаги»
    $bt = $(if ($r.Live -and ($r.It[3] -like '*\big-clean.ps1' -or $r.It[3] -like '*\energy.ps1' -or $r.It[3] -like '*\mouse.ps1' -or $r.It[3] -like '*\revive.ps1')) { "$($r.Steps[$r.Cur].R)" } else { '' })
    if ($r.Bad) { Summary $p 'idle' (Ic (Ch 0xE946) 18 'Warm') "Готово, замечаний: $($r.Bad)" $(if ($bt) { $bt } else { 'Подробности — ниже' }) -Hide:($p -eq 'h') }
    elseif ($p -eq 'h') { Summary $p 'ok' (Chk 24) 'Готово' "$($r.Title) · за $sec с" -Hide } else { Summary $p 'ok' (Chk 24) "Готово: $($r.Title)" $(if ($bt) { $bt } else { "за $sec с" }) }
    if ($p -eq 'a') { ActCtl (,@($null, 'Закрыть', { BackFromAct })) }; Snack "Готово: $($r.Title)" }
  else { if (-not $r.Live) { [void]$l.Children.Add((StepRow $r $s 'fail' $(if ($res -eq 'nostart') { 'не запустилось' } else { 'прервалось' }))) }
    Summary $p 'bad' (Chk 24 'Err' $true) $(if ($res -eq 'nostart') { 'Не удалось запустить' } elseif ($res -eq 'fail') { 'Не получилось' } else { 'Действие прервалось' }) $r.Title -Hide:($p -eq 'h')
    if ($res -eq 'nostart') { ErrCard $p 'Не удалось запустить.' 'Позвать помощь' { Run $tools.help[0] $null } 'Всё на месте: я ничего не начинал.' 'Попробуй ещё раз или позови помощь.' }
    else { $fl = $(if ($r.Safe) { 'Всё на месте: я только смотрел.' } else { 'Не знаю, что успело измениться — подробности по кнопке ниже.' })
      if ($res -eq 'fail') { ErrCard $p "$($r.Failed.D): $(Low $r.Failed.R)." 'Позвать помощь' { Run $tools.help[0] $null } $fl $(if ($r.Failed.Do) { $r.Failed.Do } else { 'Попробуй ещё раз или позови помощь.' }) }
      else { ErrCard $p 'Действие прервалось на середине.' 'Позвать помощь' { Run $tools.help[0] $null } $fl 'Попробуй ещё раз или позови помощь.' } }
    # Журнал свёрнут, на главной и список (он под «Показать шаги»): кнопка «Подробности для помощника» на виду над живой строкой. Старый снек не заслоняет «Не получилось»
    if ((Px $p 'LogBox').Visibility -eq 'Visible') { LogToggle $p }; if ($p -eq 'h') { (Px $p 'Box').Visibility = 'Collapsed' }; $script:snackOn = $false; if ($p -eq 'a') { ActCtl @(@((Ch 0xE72C), 'Ещё раз', { Run $script:run.It $null }), @($null, 'Назад', { BackFromAct })) } }
  # После чистки мусор пересчитывается заново
  if ($r.It[3] -like '*\clean-junk.ps1' -or $r.It[3] -like '*\big-clean.ps1') { $script:jt = $null; if (TilesOn) { JunkStart } }; BadgeSync; LiveRefresh; Tick }
$script:runTimer.Add_Tick({
  $r = $script:run; if (-not $r) { $script:runTimer.Stop(); return }
  # Выход замечен на прошлом тике, лог после него уже дочитан
  if ($r.Gone) { RealEnd 'bad' ([int]((Get-Date) - $r.T0).TotalSeconds); return }; if ($r.Proc) { try { $r.Gone = $r.Proc.HasExited } catch {} }
  if (-not (Test-Path -LiteralPath $r.Log)) { if (((Get-Date) - $r.T0).TotalSeconds -gt 25) { RealEnd 'nostart' 25 }; return }
  $s = [int][math]::Floor(((Get-Date) - $r.T0).TotalSeconds); (Px $r.P 'Clock').Text = 'идёт {0}:{1:00}' -f [math]::Floor($s / 60), ($s % 60); if ($r.Sec) { $r.Sec.Text = "$(if ($r.Live) { [int][math]::Floor(((Get-Date) - $r.St0).TotalSeconds) } else { $s }) с" }
  try { $fs = [IO.File]::Open($r.Log, 'Open', 'Read', 'ReadWrite'); $len = $fs.Length - $r.Pos
    if ($len -le 0) { $fs.Close(); return }; [void]$fs.Seek($r.Pos, 'Begin'); $buf = New-Object byte[] $len; $n = $fs.Read($buf, 0, $len); $fs.Close()
    $last = [Array]::LastIndexOf($buf, [byte]10, $n - 1); if ($last -lt 0) { return }; $r.Pos += $last + 1
    foreach ($ln in ([Text.Encoding]::UTF8.GetString($buf, 0, $last) -split "`n")) { RunLine $ln } } catch {} })
# Одна строка журнала run.ps1
function RunLine($ln) { $p = $ln -split '\|', 3; if ($p.Count -lt 3) { return }
  switch ($p[0]) {
    'L' { AddLine $p[1] $p[2] }
    'P' { Ask $p[2] }
    'A' { LogLine $script:run.P ("→ твой ответ: " + $(if ($p[2]) { $p[2] } else { '(пусто)' })) 'Acc' }
    'S' { RealStep $p[1] $p[2] }
    'E' { RealEnd $(if ($p[1] -eq 'Red') { 'bad' } else { 'ok' }) $p[2] } } }
# Шаги настоящего инструмента (строки S): список как у образца. Первая S убирает строку «Запускаю…»; вывод L — в журнале
function RealStep($k, $a) { $r = $script:run; $p = $r.P; $l = Px $p 'List'
  if ($k -eq 'safe' -or $k -eq 'unsafe') { $r.Safe = $k -eq 'safe'; return }
  if (-not $r.Live) { $r.Live = $true; $r.Steps = New-Object Collections.ArrayList; $r.Cur = -1; $r.Open = $false; if ($r.Spin) { $r.Spin.BeginAnimation($DP.A, $null); $r.Spin = $null }; $r.Sec = $null; $r.HintTb = $null; $l.Children.Clear() }
  if ($k -eq 'plan') { foreach ($t in ($a -split '\|')) { if ($t) { $s = @{ N = $t; D = $t }; [void]$r.Steps.Add($s); $row = StepRow $r $s 'wait'; if (-not $l.Children.Count) { $row.BorderThickness = 0 }; [void]$l.Children.Add($row) } }; return }
  if ($k -ne 'now') { RealClose $k $a; return }
  RealClose 'done' ''; $t, $h = $a -split '\|', 2; $i = $r.Cur + 1
  if ($i -lt $r.Steps.Count) { $s = $r.Steps[$i]; $s.N = $t; $s.D = $t } else { $s = @{ N = $t; D = $t }; [void]$r.Steps.Add($s) }; $s.Hint = $h
  $row = StepRow $r $s 'now'; if ($i -eq 0) { $row.BorderThickness = 0 }; if ($i -lt $l.Children.Count) { $l.Children.RemoveAt($i); $l.Children.Insert($i, $row) } else { [void]$l.Children.Add($row) }
  $r.Cur = $i; $r.Open = $true; $r.St0 = Get-Date; LogLine $p "начал: $t"; if ($p -eq 'h') { Ring ($i / $r.Steps.Count) }; $win.UpdateLayout(); Aim $row; LiveRefresh }
# Закрыть текущий шаг: done/warn — ✓ с итогом (без итога — секунды), fail — ✗
function RealClose($k, $a) { $r = $script:run; if (-not $r.Open) { return }; $r.Open = $false; $s = $r.Steps[$r.Cur]; $s.Warn = $k -eq 'warn'; if ($s.Warn) { $r.Warns++ }
  $s.R = $(if ($a) { $a } else { "$([int][math]::Floor(((Get-Date) - $r.St0).TotalSeconds)) с" }); if ($k -eq 'fail') { $s.R, $s.Do = $s.R -split '\|', 2; $r.Failed = $s }
  if ($r.Spin) { $r.Spin.BeginAnimation($DP.A, $null); $r.Spin = $null }; $r.Sec = $null; $r.HintTb = $null; $l = Px $r.P 'List'
  $row = StepRow $r $s $(if ($k -eq 'fail') { 'fail' } else { 'done' }) $s.R; if ($r.Cur -eq 0) { $row.BorderThickness = 0 }; $l.Children.RemoveAt($r.Cur); $l.Children.Insert($r.Cur, $row)
  LogLine $r.P $(if ($k -eq 'fail') { "ошибка: $($s.D) — $($s.R)" } else { "готово: $($s.D) — $($s.R)" }) $(if ($k -eq 'fail') { 'Err' }) }
function RunInApp($it, $p = 'a') {
  if ($script:run -and $script:runTimer.IsEnabled) { ShowRealAct; Snack 'Сначала дождись, пока закончится текущее действие'; return }
  $id = [guid]::NewGuid().ToString('N').Substring(0, 10)
  $a = "-NoProfile -ExecutionPolicy Bypass -File `"$Hd\run.ps1`" -Script `"$($it[3])`" -Id $id -Owner $PID"
  try { if ($it[4] -eq 'admin') { $pr = Start-Process $ps -ArgumentList $a -Verb RunAs -WindowStyle Hidden -PassThru -ErrorAction Stop } else { $pr = Start-Process $ps -ArgumentList $a -WindowStyle Hidden -PassThru -ErrorAction Stop } }
  catch { Snack 'Отменено: Windows не дал разрешение'; return }
  RunShow $it $p $id $pr }
# Ход настоящего запуска на панели p (без процесса — для PCT_RENDER)
function RunShow($it, $p, $id, $pr) {
  $script:run = @{ Id = $id; Log = "$RunDir\$id.log"; Ans = "$RunDir\$id.ans"; Pos = 0; T0 = Get-Date; Title = $it[1]; It = $it; Bad = 0; Ok = 0; Proc = $pr; Gone = $false; P = $p; Page = (PageOf $it); Seen = $true }
  if ($p -eq 'h') { $script:homeDone = $false; (G 'HCards').Visibility = 'Collapsed'; (G 'HRun').Visibility = 'Visible'; Ring 0; SetBtn 'Проверяю ноутбук…' 'Каждый шаг — ниже' (Ch 0xE9D9) $true; (G 'HSub').Text = 'Проверяю ноутбук. Каждый шаг — прямо здесь, можно не ждать.'; BeamBorder $true }
  else { ActHead $it }
  (Px $p 'Sum').Visibility = 'Collapsed'; (Px $p 'Box').Visibility = 'Visible'; (Px $p 'After').Children.Clear(); (Px $p 'Head').Text = 'Что сейчас делаю'; (Px $p 'Clock').Text = ''; LogReset $p; $script:asking = $false
  $l = Px $p 'List'; $l.Children.Clear(); $row = StepRow $script:run @{ N = $it[1]; Hint = 'Запускаю…' } 'now'; $row.BorderThickness = 0; [void]$l.Children.Add($row)
  if ((Px $p 'LogBox').Visibility -ne 'Visible') { LogToggle $p }; if ($p -eq 'a') { ActCtl (,@($null, 'Свернуть', { BackFromAct })) }; ShowRealAct; $win.UpdateLayout(); Aim $row; $script:runTimer.Start(); BadgeSync; LiveRefresh }
function ShowRealAct { if ($script:run.P -eq 'h') { Go 'home' } else { Show 'VAct' }; if ($script:run) { $script:run.Seen = $true }; LiveRefresh }

function Run($it, $btn) {
  try { switch ($it[4]) {
      'admin'  { RunInApp $it }
      'user'   { RunInApp $it }
      'gui'    { Start-Process $con -ArgumentList "--headless $ps -NoProfile -ExecutionPolicy Bypass -File `"$($it[3])`""; Snack "Открываю: $($it[1])" }
      'exe'    { Start-Process $it[3]; Snack "Открываю: $($it[1])" }
      'note'   { Start-Process notepad.exe -ArgumentList "`"$($it[3])`""; Snack "Открываю: $($it[1])" }
      'folder' { Start-Process explorer.exe -ArgumentList "`"$($it[3])`""; Snack "Открываю: $($it[1])" }
      'help'   { HelpOpen }
      'update' { StartUpdate }
    } }
  catch { Snack 'Отменено' } }
# Карточка: при PCT_DEMO — показ образца, иначе как в main
function CardClick($it, $btn) { if ($script:demo -and $it[4] -ne 'help') { $d = DemoTool $it[1]; if ($d) { AskAct $it $d; return }
    Snack "Образец: «$($it[1])» откроется в своём окне."; return }
  Run $it $btn }

# ---------- Позвать помощь: номер AnyDesk (как call-help.ps1), «Скопировать номер» ----------
function AdInfo { $exe = Get-Content "$Hd\anydesk-path.txt" -Encoding UTF8 -TotalCount 1
  if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { $exe = @("${env:ProgramFiles(x86)}\AnyDesk\AnyDesk.exe", "$env:ProgramFiles\AnyDesk\AnyDesk.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1 }
  # Поиск на рабочем столе — только если в обычных местах нет
  if (-not $exe) { $exe = Get-ChildItem ([Environment]::GetFolderPath('Desktop')) -Recurse -Depth 3 -Filter 'AnyDesk*.exe' | Select-Object -First 1 -ExpandProperty FullName }
  if ($exe -and -not (Get-Process AnyDesk)) { Start-Process -FilePath $exe }
  $id = $null; foreach ($c in "$env:APPDATA\AnyDesk\system.conf", "$env:ProgramData\AnyDesk\system.conf") {
    $m = Select-String -LiteralPath $c -Pattern '^ad\.anynet\.id=(\d+)' | Select-Object -First 1; if ($m) { $id = $m.Matches[0].Groups[1].Value; break } }
  @{ Exe = $exe; Id = $id } }
# Номера нет в system.conf — спрашиваю AnyDesk.exe --get-id отдельным процессом; итог по таймеру, не дольше 5 с
# Временный файл номера: после Kill его может держать дочерний процесс — повторяю каждые 500 мс до 10 с, остаток уберёт HelpOpen
function AdDel($f, $n = 0) { try { [IO.File]::Delete($f) } catch { if ($n -lt 20) { Later 500 ({ AdDel $f ($n + 1) }.GetNewClosure()) } } }
$script:adq = $null; $script:adTimer = New-Object Windows.Threading.DispatcherTimer; $script:adTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$script:adTimer.Add_Tick({ $q = $script:adq; $id = $null; $done = $false; try { $done = $q.P.HasExited } catch { $done = $true }
  if (-not $done -and ((Get-Date) - $q.T0).TotalSeconds -lt 5) { return }
  $script:adTimer.Stop(); if (-not $done) { try { $q.P.Kill() } catch {} }
  $m = [regex]::Match("$(Get-Content -LiteralPath $q.F -Raw)", '\d{6,}'); if ($done -and $m.Success) { $id = $m.Value }; AdDel $q.F
  $script:adq = $null; if ((G 'Hlp').Visibility -eq 'Visible') { HelpShow $id $q.Exe } })
function HelpShow($id, $exe, [switch]$Wait) { $n = G 'HlpN'; $n.FontSize = 34; $s = G 'HlpS'; $p = 'Назови этот номер человеку, который поможет. Он подключится через AnyDesk.'; $script:hid = $id
  if ($id) { $n.Text = $id -replace '(\d)(?=(\d{3})+$)', '$1 '; $s.Text = $(if ($script:demo) { 'образец номера' } else { 'Скопируй и отправь его в Telegram (Ctrl+V).' }) }
  elseif ($Wait) { $n.FontSize = 20; $n.Text = 'Ищу номер…'; $s.Text = ''; $p = 'Спрашиваю AnyDesk. Это займёт пару секунд.' }
  else { $n.FontSize = 20; $n.Text = 'Номер не нашёлся'; $s.Text = ''; $p = $(if ($exe) { 'Он написан в окне AnyDesk слева сверху (9–10 цифр). Назови его человеку, который поможет.' } else { 'AnyDesk не найден на ноутбуке.' }) }
  (G 'HlpP').Text = $p; $s.Visibility = $(if ($s.Text) { 'Visible' } else { 'Collapsed' })
  $ci = G 'HlpCi'; $ci.Text = Ch 0xE8C8; $ci.ClearValue([Windows.Controls.TextBlock]::ForegroundProperty); (G 'HlpCt').Text = 'Скопировать номер'; (G 'HlpC').IsEnabled = [bool]$script:hid
  [void](G $(if ($script:hid) { 'HlpC' } else { 'HlpX' })).Focus() }
function HelpOpen { $id = $null; $exe = $null; $wait = $false
  if ($script:demo) { $id = '0' * 9 }
  else { $a = AdInfo; $id = $a.Id; $exe = $a.Exe
    Get-ChildItem -LiteralPath $env:TEMP -Filter 'pct-adid-*.txt' | Where-Object { -not $script:adq -or $_.FullName -ne $script:adq.F } | ForEach-Object { try { [IO.File]::Delete($_.FullName) } catch {} }
    if (-not $id -and $exe -and -not $script:adq) { $f = Join-Path $env:TEMP ('pct-adid-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
      try { $script:adq = @{ P = (Start-Process -FilePath $exe -ArgumentList '--get-id' -RedirectStandardOutput $f -WindowStyle Hidden -PassThru -ErrorAction Stop); F = $f; T0 = Get-Date; Exe = $exe }; $script:adTimer.Start() } catch {} }
    $wait = [bool]$script:adq }
  $h = G 'Hlp'; $h.Visibility = 'Visible'; HelpShow $id $exe -Wait:$wait; Tw $h $DP.O 1 300 'out' 0; Tw (G 'HlpScale') $DP.SX 1 450 'spring' 0.94; Tw (G 'HlpScale') $DP.SY 1 450 'spring' 0.94 }
# В образце буфер обмена не трогаю
function HelpCopy { if (-not $script:hid) { return }; if (-not $script:demo) { try { [Windows.Clipboard]::SetText($script:hid) } catch { Snack 'Не получилось скопировать. Назови номер вслух.'; return } }
  $ci = G 'HlpCi'; $ci.Text = Ch 0xE73E; $ci.Foreground = T 'Acc'; (G 'HlpCt').Text = 'Скопировано'; Snack 'Номер AnyDesk скопирован.' }
function HelpClose { (G 'Hlp').Visibility = 'Collapsed' }
(G 'HlpC').Add_Click({ HelpCopy }); (G 'HlpX').Add_Click({ HelpClose }); Press (G 'HlpC'); Press (G 'HlpX')
(G 'Hlp').Add_MouseLeftButtonDown({ param($s, $e) if ([object]::ReferenceEquals($e.OriginalSource, $s)) { HelpClose } })

# ---------- Живые показатели: раз в 2 с, от 80 % — тёплый цвет ----------
$script:prev = $null
function Cpu { $i = 0L; $k = 0L; $u = 0L; [void][PCT.Sys]::GetSystemTimes([ref]$i, [ref]$k, [ref]$u); $now = @($i, ($k + $u))
  $v = 0; if ($script:prev) { $di = $now[0] - $script:prev[0]; $dt = $now[1] - $script:prev[1]; if ($dt -gt 0) { $v = [math]::Round(100 * (1 - $di / $dt)) } }; $script:prev = $now; [int][math]::Max(0, [math]::Min(100, $v)) }
function Meter($n, $v) { Tw (G "${n}s") $DP.SX ($v / 100) 700; (G $n).Background = T $(if ($v -ge 80) { 'Warm' } else { 'Acc' }); (G "${n}t").Text = "$v %" }
$script:tickN = 0
function Tick { $script:cpuV = Cpu; Meter 'MC' $script:cpuV; if (TilesOn) { Tiles }; Meter 'MM' ([int][PCT.Sys]::MemLoad()); $script:tickN++; if (-not $script:demo -and $script:page -eq 'home' -and ($script:tickN % 5 -eq 0) -and -not $script:R) { FillChips } }

# ---------- Живые плитки «Скорости»: тем же таймером и только пока раздел на экране ----------
# Сеть — разница байт за промежуток: первые 0,5 с «меряю…». Мусор — один подсчёт в фоне при входе и после чистки
$ru = [Globalization.CultureInfo]::GetCultureInfo('ru-RU')
function Gb($b) { if ($b -lt 1GB) { return ([double]$b / 1MB).ToString('0', $ru) + ' МБ' }; ([double]$b / 1GB).ToString($(if ($b -ge 100GB) { '0' } else { '0.0' }), $ru) + ' ГБ' }
function Mbit($b, $sec) { $v = [math]::Max([long]0, $b) * 8 / 1e6 / $sec; if ($v -lt 0.1) { 'почти 0' } else { $v.ToString($(if ($v -ge 10) { '0' } else { '0.0' }), $ru) + ' Мбит/с' } }
function Tl($n) { $script:tl.FindName($n) }
function TilesOn { $script:tl -and (G 'VTiles').Visibility -eq 'Visible' }
# Одна стеклянная панель, плитки — части с разделителем: сцена не видна в щелях между ними
function TileX($n, $title, $body, $first) { "<Border BorderBrush=`"{StaticResource Line}`" BorderThickness=`"$(if ($first) { 0 } else { '0,1,0,0' })`" Padding=`"14,16`"><StackPanel>" +
  "<TextBlock x:Name=`"${n}h`" Text=`"$title`" FontSize=`"12`" Foreground=`"{StaticResource Dim}`" Margin=`"0,0,0,8`"/>$body</StackPanel></Border>" }
# Кольцо 44 px, толщина 5: длина по кругу — 24,5 толщины
function RingX($n, $sub) { "<Grid><Grid.ColumnDefinitions><ColumnDefinition Width=`"Auto`"/><ColumnDefinition/></Grid.ColumnDefinitions><Grid Width=`"44`" Height=`"44`"><Ellipse Stroke=`"{StaticResource DimTrack}`" StrokeThickness=`"5`"/>" +
  "<Ellipse x:Name=`"${n}r`" Stroke=`"{StaticResource Acc}`" StrokeThickness=`"5`" StrokeDashArray=`"24.5 40`" StrokeDashOffset=`"24.5`" RenderTransformOrigin=`"0.5,0.5`"><Ellipse.RenderTransform><RotateTransform Angle=`"-90`"/></Ellipse.RenderTransform></Ellipse></Grid>" +
  "<StackPanel Grid.Column=`"1`" Margin=`"12,0,0,0`" VerticalAlignment=`"Center`"><TextBlock x:Name=`"${n}v`" FontSize=`"15`" FontWeight=`"SemiBold`"/><TextBlock Text=`"$sub`" FontSize=`"12`" Foreground=`"{StaticResource Dim}`"/></StackPanel></Grid>" }
function LegX($n, $br) { "<StackPanel Orientation=`"Horizontal`" Margin=`"0,4,0,0`"><Border Width=`"8`" Height=`"8`" CornerRadius=`"2`" Background=`"{StaticResource $br}`" VerticalAlignment=`"Center`" Margin=`"0,0,8,0`"/><TextBlock x:Name=`"$n`" FontSize=`"12.5`"/></StackPanel>" }
function BarX($n, $br) { "<Border x:Name=`"$n`" CornerRadius=`"4`" Background=`"{StaticResource $br}`" RenderTransformOrigin=`"0,0.5`"><Border.RenderTransform><ScaleTransform ScaleX=`"0`"/></Border.RenderTransform></Border>" }
function NetX($n, $t) { "<TextBlock Text=`"$t`" FontSize=`"12`" Foreground=`"{StaticResource Dim}`" Margin=`"0,4,0,0`"/><TextBlock x:Name=`"$n`" FontSize=`"15`" FontWeight=`"SemiBold`"/>" }
function TilesX { "<Border CornerRadius=`"12`" Background=`"{StaticResource GlassHi}`" BorderBrush=`"{StaticResource Edge}`" BorderThickness=`"1`"><StackPanel>" + (TileX 'TC' 'Процессор' (RingX 'TC' 'загрузка') $true) +
  (TileX 'TM' 'Память' ("<Grid Height=`"8`" Margin=`"0,0,0,4`"><Border CornerRadius=`"4`" Background=`"{StaticResource DimTrack}`"/>$(BarX 'TMc' 'AccEdge')$(BarX 'TMu' 'Acc')</Grid>" + (LegX 'TMut' 'Acc') + (LegX 'TMct' 'AccEdge') + (LegX 'TMft' 'DimTrack'))) +
  (TileX 'TD' 'Диск' ((RingX 'TD' 'занято') + "<TextBlock x:Name=`"TDf`" FontSize=`"12.5`" Margin=`"0,10,0,0`"/><TextBlock x:Name=`"TDj`" FontSize=`"12.5`" Margin=`"0,4,0,0`"/>" +
    "<Button x:Name=`"TDb`" Style=`"{StaticResource GBtn}`" Margin=`"0,10,0,0`" ToolTip=`"Windows спросит разрешение`"><StackPanel Orientation=`"Horizontal`"><TextBlock Text=`"&#xE7EF;`" FontFamily=`"{StaticResource Ico}`" FontSize=`"13`" Foreground=`"{StaticResource Warm}`" VerticalAlignment=`"Center`" Margin=`"0,0,8,0`"/><TextBlock Text=`"Почистить`"/></StackPanel></Button>")) +
  (TileX 'TN' 'Интернет' ("<StackPanel x:Name=`"TNon`" Margin=`"0,-4,0,0`">$(NetX 'TNr' '↓ приём')$(NetX 'TNs' '↑ отправка')</StackPanel><TextBlock x:Name=`"TNoff`" Text=`"нет связи`" FontSize=`"15`" FontWeight=`"SemiBold`" Visibility=`"Collapsed`"/>")) + '</StackPanel></Border>' }
# Значение не изменилось — без анимации: в «Скорости» окно не перерисовывается зря
function TRing($n, $v) { $t = Tl "${n}v"; if ($t.Text -eq "$v %") { return }; $e = Tl "${n}r"; Tw $e $DP.D (24.5 * (1 - $v / 100)) 700; $e.Stroke = T $(if ($v -ge 80) { 'Warm' } else { 'Acc' }); $t.Text = "$v %" }
function TBar($n, $f) { $s = (Tl $n).RenderTransform; if ([math]::Abs($s.ScaleX - $f) -ge 0.005) { Tw $s $DP.SX $f 700 } }
# Список работающих адаптеров — при входе и раз в 10 с (перебор ~3 мс), байты — каждый тик
function NetNow { if ($null -eq $script:nics -or $script:tickN % 5 -eq 0) { $script:nics = @(foreach ($a in [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) { if ($a.OperationalStatus -eq 'Up' -and $a.NetworkInterfaceType -ne 'Loopback') { $a } }) }
  $r = 0L; $s = 0L; $n = 0; foreach ($a in $script:nics) { try { $st = $a.GetIPStatistics(); $r += $st.BytesReceived; $s += $st.BytesSent; $n++ } catch {} }
  @{ R = $r; S = $s; N = $n; T = Get-Date } }
function Tiles { TRing 'TC' ([int]$script:cpuV)
  $m = [PCT.Sys]::Mem(); $c = [math]::Max([long]0, $m[2]); (Tl 'TMh').Text = 'Память · ' + (Gb $m[0]); TBar 'TMu' ($m[1] / $m[0]); TBar 'TMc' (($m[1] + $c) / $m[0])
  (Tl 'TMu').Background = T $(if ($m[1] / $m[0] -ge 0.8) { 'Warm' } else { 'Acc' }); (Tl 'TMut').Text = 'занято ' + (Gb $m[1]); (Tl 'TMct').Text = $(if ($m[2] -lt 0) { 'кэш: не знаю' } else { 'кэш ' + (Gb $m[2]) }); (Tl 'TMft').Text = 'свободно ' + (Gb $m[3])
  try { $d = New-Object IO.DriveInfo $env:SystemDrive; (Tl 'TDh').Text = "Диск $($env:SystemDrive) · " + (Gb $d.TotalSize); TRing 'TD' ([int][math]::Round(100 * (1 - $d.TotalFreeSpace / $d.TotalSize))); (Tl 'TDf').Text = 'свободно ' + (Gb $d.TotalFreeSpace) }
  catch { (Tl 'TDv').Text = 'не знаю'; (Tl 'TDf').Text = '' }
  $n = NetNow; $p = $script:netPrev; $script:netPrev = $n; (Tl 'TNon').Visibility = $(if ($n.N) { 'Visible' } else { 'Collapsed' }); (Tl 'TNoff').Visibility = $(if ($n.N) { 'Collapsed' } else { 'Visible' })
  if ($n.N -and $p -and $p.N -eq $n.N) { $sec = ($n.T - $p.T).TotalSeconds; if ($sec -ge 0.3) { (Tl 'TNr').Text = Mbit ($n.R - $p.R) $sec; (Tl 'TNs').Text = Mbit ($n.S - $p.S) $sec } } }
# Подсчёт уже идёт — не начинаю второй; результат смотрю раз в 0,3 с, пока раздел на экране
function JunkStart { if (-not $script:jt -or $script:jt.IsCompleted) { $script:jt = [PCT.Sys]::Junk($env:TEMP, $env:SystemDrive + '\') }; (Tl 'TDj').Text = 'мусор: считаю…'; JunkPoll }
function JunkPoll { if (-not $script:jt.IsCompleted) { if (-not $script:noTimer) { Later 300 { if (TilesOn -and $script:jt) { JunkPoll } } }; return }
  (Tl 'TDj').Text = $(if ($script:jt.IsFaulted) { 'мусор: не знаю' } else { 'мусор ~' + (Gb $script:jt.Result) }) }
function TilesOpen { if (-not $script:tl) { $script:tl = Frag (TilesX); (G 'VTiles').Content = $script:tl; $b = Tl 'TDb'; $b.Add_Click({ param($s, $e) CardClick (@($tools.speed | Where-Object { $_[3] -like '*\clean-junk.ps1' })[0]) $s }); Press $b }
  $script:nics = $null; $script:netPrev = NetNow; (Tl 'TNr').Text = 'меряю…'; (Tl 'TNs').Text = 'меряю…'; Tiles; JunkStart; Later 500 { if (TilesOn) { Tiles } }; Rise $script:tl 0 400 }

# ---------- Автообновление: updater.ps1 в фоне, ход — из update-status.json в живой строке ----------
$script:updTimer = New-Object Windows.Threading.DispatcherTimer; $script:updTimer.Interval = [TimeSpan]::FromMilliseconds(250)
function UpdLater($ms) { Later $ms { $script:upd = $null; LiveRefresh } }
$script:updTimer.Add_Tick({
  $j = $null; try { $j = [IO.File]::ReadAllText("$Hd\update-status.json") | ConvertFrom-Json } catch {}
  if (-not $j) { if (((Get-Date) - $script:updT0).TotalSeconds -gt 90) { $script:updTimer.Stop(); $script:upd = $null; LiveRefresh }; return }
  switch ($j.state) {
    'checking'    { $script:upd = @{ Msg = "Обновление: $(Low $j.msg)"; Busy = $true } }
    'downloading' { $script:upd = @{ Msg = "Обновление: $(Low $j.msg) — $([int]$j.pct) %"; Busy = $true } }
    'installing'  { $script:upd = @{ Msg = "Обновление: $(Low $j.msg)"; Busy = $true } }
    'done'        { $script:updTimer.Stop(); $script:upd = @{ Msg = "Обновлено до $($j.ver). Перезапусти Помощник, чтобы увидеть новое."; Busy = $false; Done = $true } }
    'uptodate'    { $script:updTimer.Stop(); $script:upd = @{ Msg = "$($j.msg)"; Busy = $false }; UpdLater 2500 }
    'error'       { $script:updTimer.Stop(); $script:upd = @{ Msg = "$($j.msg)"; Busy = $false }; UpdLater 4000 } }
  LiveRefresh })
function StartUpdate { if (-not (Test-Path "$Hd\updater.ps1")) { return }
  Remove-Item "$Hd\update-status.json" -Force; $script:updT0 = Get-Date; $script:upd = @{ Msg = 'Обновление Помощника: спрашиваю GitHub о новой версии…'; Busy = $true }; LiveRefresh
  Start-Process $con -ArgumentList "--headless $ps -NoProfile -ExecutionPolicy Bypass -File `"$Hd\updater.ps1`""; $script:updTimer.Start() }

# ---------- Фоновые дела: run\bg-*.json (PctBg в pct-core.ps1) — живая строка, точка у «Сторожей», строка сторожа; итог — снеком один раз ----------
# Читаем в общем таймере: в покое раз в 2 с, при деле раз в 1 с. Дело свежее, если процесс жив и запись не старше 2 мин; итог показываем 10 мин, старые файлы убираем
$script:bg = $null; $script:bgKey = ''; $script:bgSeen = @{}; $script:bgWait = $false; $script:bgM = 0L
# В покое — только время изменения папки run (PctBg пишет через переименование): полный разбор, лишь когда папка изменилась, дело идёт или итог ждёт показа
function BgPoll { $m = 0L; try { $m = [IO.Directory]::GetLastWriteTimeUtc($RunDir).Ticks } catch {}; if ($script:bg -or $script:bgWait -or $m -ne $script:bgM) { $script:bgM = $m; BgScan } }
function BgScan { if ($script:demo) { return }; $script:bgWait = $false; $now = Get-Date; $cur = $null; $fs = @(); try { $fs = [IO.Directory]::GetFiles($RunDir, 'bg-*.json') } catch {}
  foreach ($f in $fs) { $j = $null; $age = 1e9; try { $j = [IO.File]::ReadAllText($f) | ConvertFrom-Json; $age = ($now - [datetime]$j.t).TotalSeconds } catch {}; if (-not $j) { continue }
    if ($null -ne $j.end) { $k = "$($j.name)|$($j.t)"
      if ($age -gt 600) { try { [IO.File]::Delete($f) } catch {} }
      elseif ($script:bgSeen[$k]) { }
      elseif (($script:R -or $script:upd -or $script:tgBusy -or $null -ne $script:gBusy -or ($script:run -and $script:runTimer.IsEnabled))) { $script:bgWait = $true }
      else { $script:bgSeen[$k] = 1
        $g = $guards | Where-Object { $_.Bg -eq $j.name } | Select-Object -First 1; (G 'LiveBtn').Visibility = 'Collapsed'; LiveBusy $false; Snack ("{0}: {1}" -f $(if ($g) { $g.N } else { 'Фоновое дело' }), $j.end) 6000 }; continue }
    $live = $false; if ($age -le 120) { try { $p = [Diagnostics.Process]::GetProcessById([int]$j.pid); $p.Dispose(); $live = $true } catch {} }
    if ($live) { if (-not $cur -or [datetime]$j.t -gt [datetime]$cur.t) { $cur = $j } } elseif ($age -gt 600) { try { [IO.File]::Delete($f) } catch {} } }
  $key = $(if ($cur) { "$($cur.name)|$($cur.step)|$($cur.hint)" } else { '' }); if ($key -eq $script:bgKey) { return }
  $script:bgKey = $key; $script:bg = $cur; $timer.Interval = [TimeSpan]::FromSeconds($(if ($cur) { 1 } else { 2 })); LiveRefresh; BadgeSync; for ($i = 0; $i -lt $guards.Count; $i++) { if ($guards[$i].Bg) { GPaint $i } } }
# ---------- Что нового: whats-new.json от updater.ps1; сама — один раз на версию, по щелчку на «Версия» — всегда ----------
function WnItems($a) { @(@($a) | Where-Object { $_ -is [string] -and $_.Trim() -and $_.Length -le 120 -and $_ -notmatch '[\r\n]' } | ForEach-Object { $_.Trim() } | Select-Object -First 8) }
function WnData { $v = "$(Get-Content "$Hd\version.txt" -TotalCount 1 -Encoding UTF8)".Trim(); $j = $null
  try { $j = [IO.File]::ReadAllText("$Hd\whats-new.json", [Text.Encoding]::UTF8) | ConvertFrom-Json } catch {}
  if ($j -and "$($j.ver)" -ne $v) { $j = $null }; @{ Ver = $v; J = $j } }
function ShowWn($d) { $l = G 'SideBody'; $l.Children.Clear(); $n = 0; $script:wnVer = $d.Ver
  $t = Tx $(if ($d.Ver) { "Что нового в версии $($d.Ver)" } else { 'Что нового' }) 18 'Text' 'SemiBold'; $t.Margin = '0,6,30,0'; [void]$l.Children.Add($t); $dt = [datetime]::MinValue
  if ($d.J -and [datetime]::TryParseExact("$($d.J.date)", 'yyyy-MM-dd', $null, 'None', [ref]$dt)) { [void]$l.Children.Add((Tx ('Вышла ' + $dt.ToString('dd.MM.yyyy')) 13 'Dim')) }
  foreach ($s in @(@('new', 'НОВОЕ', 'Acc'), @('fixed', 'ИСПРАВЛЕНО', 'Warm'), @('improved', 'УЛУЧШЕНО', 'Text'))) {
    $it = @(); if ($d.J) { $it = @(WnItems $d.J.($s[0])) }; if (-not $it.Count) { continue }
    $h = Tx $s[1] 12 $s[2] 'SemiBold'; $h.Margin = '0,16,0,6'; [void]$l.Children.Add($h)
    foreach ($x in $it) { $p = Tx "•  $x" 13.5 'Text'; $p.LineHeight = 20; $p.Margin = '0,0,0,4'; [void]$l.Children.Add($p) }; $n++ }
  if (-not $n) { $e = Tx 'Для этой версии описания нет' 13.5 'Text'; $e.Margin = '0,16,0,0'; [void]$l.Children.Add($e) }
  $ok = Btn 'Понятно' { SideClose; try { [IO.File]::WriteAllText("$Hd\whats-new-seen.txt", "$script:wnVer", (New-Object Text.UTF8Encoding $false)) } catch {} }; $ok.HorizontalAlignment = 'Left'; $ok.Margin = '0,20,0,0'; [void]$l.Children.Add($ok); SideOpen }
function WnAuto { $d = WnData; if ($d.J -and @('new', 'fixed', 'improved' | ForEach-Object { WnItems $d.J.$_ }).Count -and "$(Get-Content "$Hd\whats-new-seen.txt" -TotalCount 1 -Encoding UTF8)".Trim() -ne $d.Ver) { ShowWn $d } }

# ---------- Кнопки, клавиатура ----------
for ($q = 0; $q -lt $quick.Count; $q++) { DCard (G "Q$q") $quick[$q] }
# Без образца — настоящая проверка (system-health.ps1 через run.ps1, как в main), ход — на главной. Остановить её нельзя, как в main
(G 'Pb').Add_Click({ if ($script:R -and $script:R.P -eq 'h') { StopRun } elseif ($script:R) { Snack 'Сначала дождись конца или останови текущее дело.' } elseif ($script:demo) { HomeRun ($script:out -eq 'fail') }
  elseif ($script:run.P -eq 'h' -and $script:runTimer.IsEnabled) { Snack 'Проверка идёт — итог появится здесь.' } else { RunInApp $hero 'h' } })
Press (G 'Pb'); (G 'Pb').Add_MouseEnter({ Shine 1 }); (G 'Pb').Add_GotKeyboardFocus({ Shine 1 })
(G 'HLogT').Add_Click({ LogToggle 'h' }); (G 'ALogT').Add_Click({ LogToggle 'a' }); (G 'ABack').Add_Click({ BackFromAct })
(G 'LiveBtn').Add_Click({ param($s, $e) if ($s.Tag -eq 'restart') { $script:quit = $true; MtxFree; Start-Process $con -ArgumentList "--headless $ps -NoProfile -STA -ExecutionPolicy Bypass -File `"$Hd\helper-app.ps1`""; $win.Close() } elseif ($s.Tag -eq 'guards') { Go 'guards' } else { ShowRealAct } })
(G 'Live').Add_MouseLeftButtonUp({ $b = G 'LiveBtn'; if ($b.Tag -eq 'guards' -and $b.Visibility -eq 'Visible') { Go 'guards' } })
(G 'BtnMenu').Add_Click({ DrawerSet (-not $script:drawerOpen) })
(G 'TopBar').Add_MouseLeftButtonDown({ $win.DragMove() }); (G 'Brand').Add_MouseLeftButtonDown({ param($s, $e) if ($e.OriginalSource -is [Windows.Controls.TextBlock] -or [object]::ReferenceEquals($e.OriginalSource, $s)) { $win.DragMove() } })
(G 'BtnClose').Add_Click({ $win.Close() }); (G 'BtnMin').Add_Click({ $win.WindowState = 'Minimized' })
$v = "$(Get-Content "$Hd\version.txt" -TotalCount 1 -Encoding UTF8)".Trim(); if ($v) { (G 'VerRun').Text = "Версия $v" } else { (G 'VerSep').Text = '' }
(G 'VerBtn').Add_Click({ ShowWn (WnData) })
# Esc закрывает окно подтверждения и панель; Enter нажимает кнопку в фокусе; F2 в образце меняет исход
$win.Add_PreviewKeyDown({ param($s, $e)
  if ($e.Key -eq 'Escape') { if ((G 'Cfm').Visibility -eq 'Visible') { CfmClose; $e.Handled = $true } elseif ((G 'Hlp').Visibility -eq 'Visible') { HelpClose; $e.Handled = $true } elseif ($script:sideOn) { SideClose; $e.Handled = $true } }
  elseif ($e.Key -eq 'Return' -and [Windows.Input.Keyboard]::FocusedElement -is [Windows.Controls.Button]) { $b = [Windows.Input.Keyboard]::FocusedElement; (New-Object Windows.Automation.Peers.ButtonAutomationPeer($b)).GetPattern('Invoke').Invoke(); $e.Handled = $true }
  elseif ($e.Key -eq 'F2' -and $script:demo) { $o = @('ok', 'deny', 'fail'); $script:out = $o[([array]::IndexOf($o, $script:out) + 1) % 3]
    Snack ('Образец: исход инструментов — ' + @{ ok = 'успех'; deny = '«нажала Нет»'; fail = 'сбой' }[$script:out]) } })
# Переключение сторожа (GuardFlip): итог — по таймеру, обновляется только этот сторож
$script:tgTimer = New-Object Windows.Threading.DispatcherTimer; $script:tgTimer.Interval = [TimeSpan]::FromMilliseconds(250)
# Если состояние процесса не читается — ждём не дольше 15 с
$script:tgTimer.Add_Tick({ $t = $script:tg; $done = ((Get-Date) - $t.T0).TotalSeconds -gt 15; try { $done = $t.P.HasExited } catch {}; if (-not $done) { return }
  $script:tgTimer.Stop(); GuardOne $t.G; GuardDone })
# Закрытие во время работы — спросить (кроме перезапуска после обновления)
$win.Add_Closing({ param($s, $e) if ($script:quit -or -not ($script:run -and $script:runTimer.IsEnabled)) { return }
  # Открыт вопрос — отвечаем «Нет», иначе run.ps1 ждёт ответа до 30 минут
  $q = $(if ($script:asking) { "Сейчас «$($script:run.Title)» ждёт твой ответ. Если закрыть, я отвечу «Нет». Закрыть?" } else { "Сейчас идёт «$($script:run.Title)». Оно доработает само, но итог ты не увидишь. Закрыть?" })
  if ([Windows.MessageBox]::Show($win, $q, 'Помощник', 'YesNo', 'Question') -ne 'Yes') { $e.Cancel = $true } elseif ($script:asking) { Answer '' } })
if ($script:wake) { $wt = New-Object Windows.Threading.DispatcherTimer; $wt.Interval = [TimeSpan]::FromMilliseconds(300)
  $wt.Add_Tick({ if ($script:wake.WaitOne(0)) { if ($win.WindowState -eq 'Minimized') { $win.WindowState = 'Normal' }; [void]$win.Activate(); $win.Topmost = $true; $win.Topmost = $false } }); $wt.Start() }

$win.Add_SourceInitialized({ $h = (New-Object Windows.Interop.WindowInteropHelper($win)).Handle; $v = 2; [void][PCT.Sys]::DwmSetWindowAttribute($h, 33, [ref]$v, 4); $d = 1; [void][PCT.Sys]::DwmSetWindowAttribute($h, 20, [ref]$d, 4) })
[void](Cpu); $script:page = 'home'
# Общий таймер: в покое раз в 2 с; пока идёт фоновое дело — раз в 1 с (показатели всё так же раз в 2 с)
$timer = New-Object Windows.Threading.DispatcherTimer; $timer.Interval = [TimeSpan]::FromSeconds(2); $timer.Add_Tick({ $script:odd = $script:bg -and -not $script:odd; if (-not $script:odd) { Tick }; BgPoll }); $timer.Start()
# Подготовка главной — здесь, а не до показа: первый кадр раньше (9c-2). Затем появление по очереди и блик кнопки 3 прохода
$win.Add_Loaded({ HomeReset; NavMark 'home'; LiveText $script:idle; Tick; BgScan; $pb = G 'Pb'; $in = $pb.Template.FindName('inner', $pb); $clip = { param($s, $e) $s.Clip = New-Object Windows.Media.RectangleGeometry((New-Object Windows.Rect(0, 0, $s.ActualWidth, $s.ActualHeight)), 14, 14) }; $in.Add_SizeChanged($clip); & $clip $in $null
  $n = 0; foreach ($el in @((G 'Hello'), (G 'HSub'), (G 'Chips'), $pb, (G 'Cap'))) { Rise $el (250 + 120 * $n) 500; $n++ }
  $n = 0; foreach ($c in (G 'Quick').Children) { Rise $c (850 + 70 * $n) 500; $n++ }; Rise (G 'LastRow') 1120 500; Rise (G 'Live') 1100 500; Later 1300 { Shine 3 }
  if (-not $env:PCT_RENDER) { WnAuto; try { $m = PctMigrate; if ($m) { Snack $m 5000 } } catch { PctProfileLog "миграция не удалась: $($_.Exception.Message)" }; StartUpdate } })

if ($env:PCT_RENDER) { $win.Show(); $rdir = $env:PCT_RENDER
  # PNG при 100 % и, с -All, при 125 и 150 % (тот же макет, плотность пикселей как у масштаба Windows)
  function Snap($name, [switch]$All) { $win.UpdateLayout(); $win.Dispatcher.Invoke([Action] {}, 'Render'); Start-Sleep -Milliseconds 120; $win.Dispatcher.Invoke([Action] {}, 'ApplicationIdle'); $win.UpdateLayout()
    $root = G 'Root'; foreach ($k in $(if ($All) { @(1, 1.25, 1.5) } else { @(1) })) { $rt = New-Object Windows.Media.Imaging.RenderTargetBitmap([int]($root.ActualWidth * $k), [int]($root.ActualHeight * $k), (96 * $k), (96 * $k), 'Pbgra32'); $rt.Render($root)
      $en = New-Object Windows.Media.Imaging.PngBitmapEncoder; $en.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rt)); $sfx = $(if ($k -eq 1) { '' } else { '@' + [int]($k * 100) }); $fs = [IO.File]::Create("$rdir\$name$sfx.png"); $en.Save($fs); $fs.Close() } }
  function RClock($tot, $st) { $script:R.T0 = (Get-Date).AddSeconds(-$tot); $script:R.St0 = (Get-Date).AddSeconds(-$st); Clock $script:R }
  Snap 'home-idle' -All
  # «Скорость»: настоящие плитки — сеть за 1 с, мусор досчитан
  foreach ($k in @($pages.Keys)) { Go $k; if ($k -eq 'speed') { Start-Sleep 1; [void]$script:jt.Wait(60000); JunkPoll; Tick }; Snap "page-$k" -All }
  Go 'guards'; GuardSide 0; Snap 'guard-side' -All; Snap 'detail'; GuardFlip 0; Snap 'guard-off-confirm' -All; CfmClose; SideClose
  Go 'help'; HelpOpen; Snap 'help-anydesk' -All; HelpCopy; Snap 'help-copied' -All; HelpClose
  Go 'home'; $qt = $tools.net[0]; CardClick $qt $null; RClock 1 1; Snap 'act-from-home' -All; StopRun
  HomeRun $false; StepStart 1; StepStart 2; RClock 7 2; Snap 'home-run' -All
  StepStart 3; StepStart 4; RClock 13 3; Finish; Snap 'home-done' -All
  LogToggle 'h'; Snap 'log-open' -All; LogToggle 'h'
  HomeReset; HomeRun $true; foreach ($i in 1..4) { StepStart $i }; RClock 13 3; Finish; Snap 'home-error' -All
  HomeReset; HomeRun $false; StepStart 1; RClock 4 1; StopRun; Snap 'home-stopped' -All
  $yt = $tools.net[0]; $script:out = 'ok'; OpenAct $yt (DemoTool $yt[1]); RClock 1 1; Snap 'act-uac' -All
  StepStart 1; StepStart 2; RClock 6 1; Snap 'act-run' -All
  foreach ($i in 3..5) { StepStart $i }; RClock 12 1; Finish; Snap 'act-ok' -All
  $script:out = 'deny'; OpenAct $yt (DemoTool $yt[1]); Finish; Snap 'act-deny' -All
  $script:out = 'fail'; OpenAct $yt (DemoTool $yt[1]); StepStart 1; StepStart 2; RClock 6 2; Finish; Snap 'act-fail' -All
  $script:out = 'ok'; $sc = $tools.protect[0]; OpenAct $sc (DemoTool $sc[1]); StepStart 1; RClock 4 2; Snap 'act-ask' -All; Snap 'activity'
  LogToggle 'a'; Snap 'act-log' -All; LogToggle 'a'; StopRun
  $ni = $tools.net[5]; AskAct $ni (DemoTool $ni[1]); Snap 'confirm' -All; CfmClose
  Go 'home'; HomeReset; DrawerSet $false; Snap 'drawer-closed' -All; DrawerSet $true
  # «Что нового» с данными-образцом: 2 «Новое», 1 «Исправлено», 0 «Улучшено»
  ShowWn @{ Ver = '1.0.10'; J = [pscustomobject]@{ ver = '1.0.10'; date = '2026-10-28'; new = @('В запасном меню можно проверить обновления.', 'В запасном меню появились «Что тормозит», «Камера и микрофон», «Не открываются файлы».'); fixed = @('Ошибки инструментов записываются в журнал — помощнику легче понять, что случилось.'); improved = @() } }; Snap 'whats-new' -All; SideClose
  # Порядок Tab: 60 шагов от кнопки шторки
  $win.Activate() | Out-Null; [void](G 'BtnMenu').Focus(); $fo = New-Object Collections.ArrayList
  for ($i = 0; $i -lt 60; $i++) { $f = [Windows.Input.Keyboard]::FocusedElement; if (-not $f) { break }; $tx = ''
    if ($f -is [Windows.Controls.ContentControl]) { $c = $f.Content; if ($c -is [string]) { $tx = $c } elseif ($c -is [Windows.Controls.TextBlock]) { $tx = $c.Text } elseif ($c) { $tx = (@([Windows.LogicalTreeHelper]::GetChildren($c)) + @($c.Children) | Where-Object { $_ -is [Windows.Controls.TextBlock] } | Select-Object -First 3 | ForEach-Object { $_.Text }) -join ' ' } }
    [void]$fo.Add("$i`t$($f.GetType().Name)`t$($f.Name)`t$tx"); [void]$f.MoveFocus((New-Object Windows.Input.TraversalRequest('Next'))) }
  [IO.File]::WriteAllLines("$rdir\focus-order.txt", $fo, (New-Object Text.UTF8Encoding $false))
  # Настоящий ход по строкам run.ps1 (без процесса): шаги во время и после, сбой шага, итог и сбой на главной
  function RTool($f) { foreach ($k in $tools.Keys) { foreach ($t in $tools[$k]) { if ($t[3] -like "*\$f") { return ,$t } } } }
  $script:snackOn = $false; RunShow (RTool 'perf-now.ps1') 'a' 'render' $null
  foreach ($ln in @('S|plan|Проверяю зарядку|Смотрю 5 секунд, что грузит ноутбук|Готовлю советы', 'S|now|Проверяю зарядку|', 'S|done|от зарядки', 'S|now|Смотрю 5 секунд, что грузит ноутбук|Ничего не трогай', 'L|DarkGray|Смотрю 5 секунд — ничего не трогай...')) { RunLine $ln }; $script:run.Sec.Text = '2 с'; Snap 'real-run' -All
  foreach ($ln in @('S|done|процессор 12 %, память 48 %', 'S|now|Готовлю советы|', 'L|Green|  Сейчас ничего не тормозит. Если тормозит одна программа — закрой её и открой заново.', 'S|done|ничего не тормозит', 'E|Gray|7')) { RunLine $ln }; (G 'ABox').Visibility = 'Visible'; Snap 'real-done' -All
  $script:snackOn = $false; RunShow (RTool 'site-fix.ps1') 'a' 'render' $null
  foreach ($ln in @('S|safe|', 'S|plan|Жду адрес сайта|Проверяю интернет|Проверяю сайт напрямую и через Happ', 'S|now|Жду адрес сайта|Напиши его ниже', 'A|White|instagram.com', 'S|done|instagram.com', 'S|now|Проверяю интернет|', 'S|fail|интернета нет|Нажми «Интернет совсем не работает».', 'L|Red|Интернета нет совсем. В Помощнике нажми «Интернет совсем не работает».', 'E|Gray|3')) { RunLine $ln }; Snap 'real-fail-step' -All
  $script:snackOn = $false; RunShow $hero 'h' 'render' $null; RunLine 'L|Gray|Всё в порядке'; RunLine 'E|Gray|42'; Snap 'home-real-done' -All
  $script:snackOn = $false; RunShow $hero 'h' 'render' $null; RunLine 'L|Gray|Смотрю диск...'; RealEnd 'bad' 3; Snap 'home-real-fail' -All
  $win.Close(); return }
[void]$win.ShowDialog()
} catch {
  $rp = if (Test-Path function:PctDir) { PctDir 'reports' } else { 'C:\PC-Tweaks-Laptop\reports' }
  New-Item -ItemType Directory -Force $rp | Out-Null; [IO.File]::AppendAllText("$rp\helper-app-error.txt", "$(Get-Date -f s) $($_.Exception.Message)`r`n", (New-Object Text.UTF8Encoding $false))
  if ($env:PCT_RENDER) { throw }
  MtxFree; & "$Hd\helper-menu.ps1" }
