# Помощник 1.0.1 (WPF): все инструменты ноутбука в одной программе. Шторка с категориями, живые картинки,
# ход каждого действия внутри окна (без окон PowerShell, через run.ps1), сторожа с объяснениями, автообновление.
# При ошибке загрузки окна открывается простое меню helper-menu.ps1.
$ErrorActionPreference = 'SilentlyContinue'
$Hd = 'C:\PC-Tweaks-Laptop\helpers'; $Gd = 'C:\PC-Tweaks-Laptop\guard'; $RunDir = 'C:\PC-Tweaks-Laptop\run'
$ps = "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"; $con = "$env:windir\System32\conhost.exe"
$Tools = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Мои инструменты'
try {
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -Namespace PCT -Name Sys -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
[StructLayout(LayoutKind.Sequential)] public struct MEM { public uint len; public uint load; public ulong tot; public ulong av; public ulong tp; public ulong ap; public ulong tv; public ulong avv; public ulong ext; }
[DllImport("kernel32.dll")] public static extern bool GlobalMemoryStatusEx(ref MEM m);
public static uint MemLoad() { MEM m = new MEM(); m.len = (uint)System.Runtime.InteropServices.Marshal.SizeOf(typeof(MEM)); GlobalMemoryStatusEx(ref m); return m.load; }
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

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Помощник" Width="980" Height="700" WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize" WindowStyle="SingleBorderWindow"
        FontFamily="Segoe UI Variable Text, Segoe UI" UseLayoutRounding="True" Background="#0E1126">
  <WindowChrome.WindowChrome><WindowChrome CaptionHeight="0" ResizeBorderThickness="0" GlassFrameThickness="0,0,0,1" UseAeroCaptionButtons="False"/></WindowChrome.WindowChrome>
  <Window.Resources>
    <FontFamily x:Key="Ico">Segoe Fluent Icons, Segoe MDL2 Assets</FontFamily>
    <LinearGradientBrush x:Key="Accent" StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#7C5CFF" Offset="0"/><GradientStop Color="#00C2FF" Offset="1"/></LinearGradientBrush>
    <Style x:Key="Chrome" TargetType="Button">
      <Setter Property="Foreground" Value="#B8C0E0"/><Setter Property="Width" Value="40"/><Setter Property="Height" Value="32"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="b" CornerRadius="8" Background="Transparent"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
        <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#22FFFFFF"/></Trigger></ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="Card" TargetType="Button">
      <Setter Property="Foreground" Value="White"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Margin" Value="5"/><Setter Property="Height" Value="70"/>
      <Setter Property="RenderTransformOrigin" Value="0.5,0.5"/>
      <Setter Property="RenderTransform"><Setter.Value><TransformGroup><ScaleTransform/><TranslateTransform/></TransformGroup></Setter.Value></Setter>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="bd" CornerRadius="16" Background="#1A2042" BorderBrush="#2A3262" BorderThickness="1" Padding="14,8">
          <Border.Effect><DropShadowEffect x:Name="sh" BlurRadius="0" ShadowDepth="0" Color="#7C5CFF" Opacity="0.55"/></Border.Effect>
          <ContentPresenter VerticalAlignment="Center"/>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="bd" Property="Background" Value="#232A58"/><Setter TargetName="bd" Property="BorderBrush" Value="#7C5CFF"/>
            <Trigger.EnterActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="sh" Storyboard.TargetProperty="BlurRadius" To="22" Duration="0:0:0.2"/></Storyboard></BeginStoryboard></Trigger.EnterActions>
            <Trigger.ExitActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="sh" Storyboard.TargetProperty="BlurRadius" To="0" Duration="0:0:0.25"/></Storyboard></BeginStoryboard></Trigger.ExitActions>
          </Trigger>
          <Trigger Property="IsEnabled" Value="False"><Setter TargetName="bd" Property="Opacity" Value="0.45"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
      <Style.Triggers>
        <EventTrigger RoutedEvent="MouseEnter"><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[1].(TranslateTransform.Y)" To="-3" Duration="0:0:0.18"><DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation></Storyboard></BeginStoryboard></EventTrigger>
        <EventTrigger RoutedEvent="MouseLeave"><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[1].(TranslateTransform.Y)" To="0" Duration="0:0:0.25"/></Storyboard></BeginStoryboard></EventTrigger>
        <EventTrigger RoutedEvent="PreviewMouseLeftButtonDown"><BeginStoryboard><Storyboard>
          <DoubleAnimation Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleX)" To="0.96" Duration="0:0:0.08"/>
          <DoubleAnimation Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleY)" To="0.96" Duration="0:0:0.08"/></Storyboard></BeginStoryboard></EventTrigger>
        <EventTrigger RoutedEvent="PreviewMouseLeftButtonUp"><BeginStoryboard><Storyboard>
          <DoubleAnimation Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleX)" To="1" Duration="0:0:0.35"><DoubleAnimation.EasingFunction><ElasticEase Oscillations="1" Springiness="5"/></DoubleAnimation.EasingFunction></DoubleAnimation>
          <DoubleAnimation Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleY)" To="1" Duration="0:0:0.35"><DoubleAnimation.EasingFunction><ElasticEase Oscillations="1" Springiness="5"/></DoubleAnimation.EasingFunction></DoubleAnimation></Storyboard></BeginStoryboard></EventTrigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="Hero" TargetType="Button" BasedOn="{StaticResource Card}">
      <Setter Property="Height" Value="84"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="bd" CornerRadius="20" Background="{StaticResource Accent}" Padding="20,10">
          <Border.Effect><DropShadowEffect x:Name="sh" BlurRadius="14" ShadowDepth="0" Color="#7C5CFF" Opacity="0.6"/></Border.Effect>
          <ContentPresenter VerticalAlignment="Center"/>
        </Border>
        <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True">
          <Trigger.EnterActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="sh" Storyboard.TargetProperty="BlurRadius" To="36" Duration="0:0:0.25"/></Storyboard></BeginStoryboard></Trigger.EnterActions>
          <Trigger.ExitActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="sh" Storyboard.TargetProperty="BlurRadius" To="14" Duration="0:0:0.3"/></Storyboard></BeginStoryboard></Trigger.ExitActions>
        </Trigger></ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="Nav" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#AEB7DD"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Height" Value="46"/><Setter Property="Margin" Value="10,3"/><Setter Property="GroupName" Value="nav"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RadioButton">
        <Grid>
          <Border x:Name="bg" CornerRadius="12" Background="Transparent"/>
          <Border x:Name="bar" Width="4" Height="22" CornerRadius="2" HorizontalAlignment="Left" Margin="2,0,0,0" Background="{StaticResource Accent}" RenderTransformOrigin="0.5,0.5">
            <Border.RenderTransform><ScaleTransform ScaleY="0"/></Border.RenderTransform></Border>
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
            <TextBlock Text="{TemplateBinding Tag}" FontFamily="{StaticResource Ico}" FontSize="17" Width="52" TextAlignment="Center" VerticalAlignment="Center"/>
            <ContentPresenter VerticalAlignment="Center"/>
          </StackPanel>
        </Grid>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bg" Property="Background" Value="#141A3A"/></Trigger>
          <Trigger Property="IsChecked" Value="True">
            <Setter TargetName="bg" Property="Background" Value="#1E2552"/><Setter Property="Foreground" Value="White"/>
            <Trigger.EnterActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="bar" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1" Duration="0:0:0.3"><DoubleAnimation.EasingFunction><BackEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation></Storyboard></BeginStoryboard></Trigger.EnterActions>
            <Trigger.ExitActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="bar" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="0" Duration="0:0:0.18"/></Storyboard></BeginStoryboard></Trigger.ExitActions>
          </Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="Chip" TargetType="Border"><Setter Property="CornerRadius" Value="14"/><Setter Property="Background" Value="#151A37"/><Setter Property="BorderBrush" Value="#262D58"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="12,6"/><Setter Property="Margin" Value="0,0,8,8"/></Style>
    <Style x:Key="Dot" TargetType="Ellipse"><Setter Property="Width" Value="9"/><Setter Property="Height" Value="9"/><Setter Property="Margin" Value="0,0,8,0"/><Setter Property="VerticalAlignment" Value="Center"/>
      <Style.Triggers><EventTrigger RoutedEvent="Loaded"><BeginStoryboard><Storyboard RepeatBehavior="Forever" AutoReverse="True" Timeline.DesiredFrameRate="20"><DoubleAnimation Storyboard.TargetProperty="Opacity" From="1" To="0.35" Duration="0:0:0.9"/></Storyboard></BeginStoryboard></EventTrigger></Style.Triggers></Style>
    <Style x:Key="Meter" TargetType="ProgressBar"><Setter Property="Height" Value="6"/><Setter Property="Width" Value="64"/><Setter Property="Maximum" Value="100"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ProgressBar">
        <Grid><Border CornerRadius="3" Background="#2A315E"/><Border x:Name="PART_Track"/><Border x:Name="PART_Indicator" CornerRadius="3" HorizontalAlignment="Left" Background="{StaticResource Accent}"/></Grid>
      </ControlTemplate></Setter.Value></Setter></Style>
    <Style x:Key="Small" TargetType="Button" BasedOn="{StaticResource Card}"><Setter Property="Height" Value="40"/><Setter Property="Margin" Value="0,0,8,0"/></Style>
  </Window.Resources>

  <Grid x:Name="Root">
    <Grid.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#0E1126" Offset="0"/><GradientStop Color="#141938" Offset="0.6"/><GradientStop Color="#1D1537" Offset="1"/></LinearGradientBrush></Grid.Background>
    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>

    <Border x:Name="Drawer" Grid.Column="0" Width="214" Background="#0A0D20" BorderBrush="#1C2248" BorderThickness="0,0,1,0" ClipToBounds="True">
      <Grid>
        <Grid.RowDefinitions><RowDefinition Height="64"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <StackPanel x:Name="DrawerHead" Orientation="Horizontal" Margin="14,0,0,0" VerticalAlignment="Center" Background="Transparent">
          <Button x:Name="BtnMenu" Style="{StaticResource Chrome}" Width="44" Height="40"><TextBlock Text="&#xE700;" FontFamily="{StaticResource Ico}" FontSize="16" Foreground="White"/></Button>
          <TextBlock Text="Помощник" Foreground="White" FontSize="17" FontWeight="SemiBold" Margin="8,0,0,0" VerticalAlignment="Center"/>
        </StackPanel>
        <StackPanel x:Name="Nav" Grid.Row="1" Margin="0,6,0,0"/>
        <StackPanel Grid.Row="2" Margin="18,0,0,16">
          <TextBlock x:Name="Ver" Foreground="#5D6796" FontSize="12"/>
          <TextBlock Text="Сделано с любовью" Foreground="#454E7C" FontSize="11.5" Margin="0,2,0,0"/>
        </StackPanel>
      </Grid>
    </Border>

    <Grid Grid.Column="1">
      <Grid.RowDefinitions><RowDefinition Height="46"/><RowDefinition Height="*"/><RowDefinition Height="38"/></Grid.RowDefinitions>
      <Grid x:Name="TitleBar" Background="Transparent">
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,0,8,0">
          <Border CornerRadius="10" Background="#141935" Padding="10,4" Margin="0,0,6,0" VerticalAlignment="Center"><StackPanel Orientation="Horizontal"><TextBlock Text="Процессор" Foreground="#98A2C8" FontSize="12" Margin="0,0,8,0" VerticalAlignment="Center"/><ProgressBar x:Name="BarC" Style="{StaticResource Meter}" VerticalAlignment="Center"/><TextBlock x:Name="TxtC" Foreground="#DDE3FF" FontSize="12" Width="36" TextAlignment="Right" VerticalAlignment="Center"/></StackPanel></Border>
          <Border CornerRadius="10" Background="#141935" Padding="10,4" Margin="0,0,10,0" VerticalAlignment="Center"><StackPanel Orientation="Horizontal"><TextBlock Text="Память" Foreground="#98A2C8" FontSize="12" Margin="0,0,8,0" VerticalAlignment="Center"/><ProgressBar x:Name="BarM" Style="{StaticResource Meter}" VerticalAlignment="Center"/><TextBlock x:Name="TxtM" Foreground="#DDE3FF" FontSize="12" Width="36" TextAlignment="Right" VerticalAlignment="Center"/></StackPanel></Border>
          <Button x:Name="BtnMin" Style="{StaticResource Chrome}"><TextBlock Text="&#xE921;" FontFamily="{StaticResource Ico}" FontSize="11"/></Button>
          <Button x:Name="BtnClose" Style="{StaticResource Chrome}"><TextBlock Text="&#xE8BB;" FontFamily="{StaticResource Ico}" FontSize="11"/></Button>
        </StackPanel>
      </Grid>

      <Grid Grid.Row="1" Margin="24,0,24,0">
        <Grid x:Name="Page"><Grid.RenderTransform><TranslateTransform x:Name="PageShift"/></Grid.RenderTransform>
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <Grid Margin="0,0,0,10">
            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <ContentControl x:Name="Art" Width="120" Height="90"/>
            <StackPanel Grid.Column="1" Margin="16,0,0,0" VerticalAlignment="Center">
              <TextBlock x:Name="PTitle" Foreground="White" FontSize="25" FontWeight="SemiBold"/>
              <TextBlock x:Name="PSub" Foreground="#98A2C8" FontSize="13.5" Margin="0,4,0,0" TextWrapping="Wrap"/>
            </StackPanel>
          </Grid>
          <StackPanel x:Name="Body" Grid.Row="1"/>
        </Grid>

        <Border x:Name="Detail" Visibility="Collapsed" CornerRadius="18" Background="#131837" BorderBrush="#3A4380" BorderThickness="1" Padding="26,20" Margin="0,0,0,8">
          <Border.RenderTransform><TranslateTransform x:Name="DetailShift"/></Border.RenderTransform>
          <StackPanel>
            <StackPanel Orientation="Horizontal">
              <Border Width="50" Height="50" CornerRadius="16" Background="{StaticResource Accent}"><TextBlock x:Name="DIcon" FontFamily="{StaticResource Ico}" FontSize="22" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
              <StackPanel Margin="16,0,0,0" VerticalAlignment="Center"><TextBlock x:Name="DTitle" Foreground="White" FontSize="21" FontWeight="SemiBold"/><TextBlock x:Name="DState" FontSize="13.5" Margin="0,3,0,0"/></StackPanel>
            </StackPanel>
            <Border x:Name="DRecBox" CornerRadius="12" Padding="14,10" Margin="0,16,0,0"><TextBlock x:Name="DRec" Foreground="White" FontSize="14.5" FontWeight="SemiBold" TextWrapping="Wrap"/></Border>
            <TextBlock Text="ЧТО ДЕЛАЕТ" Foreground="#8FA3FF" FontSize="12" FontWeight="SemiBold" Margin="0,16,0,4"/>
            <TextBlock x:Name="DWhat" Foreground="#DDE3FF" FontSize="14" TextWrapping="Wrap"/>
            <TextBlock Text="ЕСЛИ ВЫКЛЮЧИТЬ" Foreground="#FF9DB0" FontSize="12" FontWeight="SemiBold" Margin="0,12,0,4"/>
            <TextBlock x:Name="DRisk" Foreground="#DDE3FF" FontSize="14" TextWrapping="Wrap"/>
            <TextBlock Text="НАГРУЗКА НА НОУТБУК" Foreground="#7FE0C0" FontSize="12" FontWeight="SemiBold" Margin="0,12,0,4"/>
            <TextBlock x:Name="DLoad" Foreground="#DDE3FF" FontSize="14" TextWrapping="Wrap"/>
            <StackPanel Orientation="Horizontal" Margin="0,20,0,0">
              <Button x:Name="DToggle" Style="{StaticResource Card}" Width="240" Height="48"><TextBlock x:Name="DToggleTxt" Foreground="White" FontSize="15" FontWeight="SemiBold" HorizontalAlignment="Center"/></Button>
              <Button x:Name="DBack" Style="{StaticResource Card}" Width="150" Height="48"><TextBlock Text="Назад" Foreground="White" FontSize="15" HorizontalAlignment="Center"/></Button>
            </StackPanel>
          </StackPanel>
        </Border>

        <Border x:Name="Act" Visibility="Collapsed" CornerRadius="18" Background="#10142E" BorderBrush="#3A4380" BorderThickness="1" Padding="20,16" Margin="0,0,0,8">
          <Border.RenderTransform><TranslateTransform x:Name="ActShift"/></Border.RenderTransform>
          <Grid>
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <Grid>
              <StackPanel Orientation="Horizontal">
                <Border Width="44" Height="44" CornerRadius="14" Background="{StaticResource Accent}">
                  <TextBlock x:Name="ActIco" Text="&#xE895;" FontFamily="{StaticResource Ico}" FontSize="19" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center" RenderTransformOrigin="0.5,0.5"><TextBlock.RenderTransform><RotateTransform x:Name="ActRot"/></TextBlock.RenderTransform></TextBlock></Border>
                <StackPanel Margin="14,0,0,0" VerticalAlignment="Center"><TextBlock x:Name="ActTitle" Foreground="White" FontSize="19" FontWeight="SemiBold"/><TextBlock x:Name="ActSub" Foreground="#98A2C8" FontSize="13" Margin="0,2,0,0"/></StackPanel>
              </StackPanel>
              <Button x:Name="ActClose" Style="{StaticResource Small}" Width="130" HorizontalAlignment="Right" Margin="0"><TextBlock x:Name="ActCloseTxt" Text="Свернуть" Foreground="White" FontSize="14" HorizontalAlignment="Center"/></Button>
            </Grid>
            <Border Grid.Row="1" CornerRadius="12" Background="#0B0E22" Margin="0,12,0,10" Padding="12,8">
              <ScrollViewer x:Name="ActScroll" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="ActLines"/></ScrollViewer>
            </Border>
            <Border x:Name="AskBox" Grid.Row="2" Visibility="Collapsed" CornerRadius="12" Background="#1D2452" BorderBrush="#7C5CFF" BorderThickness="1" Padding="14,10">
              <StackPanel>
                <TextBlock x:Name="AskTxt" Foreground="White" FontSize="14" TextWrapping="Wrap" Margin="0,0,0,8"/>
                <StackPanel Orientation="Horizontal">
                  <Button x:Name="AskYes" Style="{StaticResource Small}" Width="90"><TextBlock Text="Да" Foreground="White" FontSize="14" FontWeight="SemiBold" HorizontalAlignment="Center"/></Button>
                  <Button x:Name="AskNo" Style="{StaticResource Small}" Width="90"><TextBlock Text="Нет" Foreground="White" FontSize="14" HorizontalAlignment="Center"/></Button>
                  <TextBox x:Name="AskIn" Width="250" Height="36" Margin="0,0,8,0" FontSize="14" Background="#0B0E22" Foreground="White" BorderBrush="#3A4380" CaretBrush="White" VerticalContentAlignment="Center" Padding="8,0"/>
                  <Button x:Name="AskOk" Style="{StaticResource Small}" Width="120"><TextBlock Text="Ответить" Foreground="White" FontSize="14" HorizontalAlignment="Center"/></Button>
                </StackPanel>
              </StackPanel>
            </Border>
          </Grid>
        </Border>
      </Grid>

      <Grid Grid.Row="2" Margin="24,0,24,8">
        <TextBlock x:Name="Hint" Text="Windows спросит разрешение — нажми «Да». Не получается — «Помощь» → «Позвать помощь»." Foreground="#6F79A6" FontSize="12.5" VerticalAlignment="Center"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Left" VerticalAlignment="Center">
        <Button x:Name="RunPill" Style="{StaticResource Chrome}" Width="Auto" Height="30" Margin="0,0,8,0" Visibility="Collapsed">
          <Border CornerRadius="12" Background="#2B3470" Padding="12,4"><StackPanel Orientation="Horizontal"><TextBlock x:Name="PillIco" Text="&#xE895;" FontFamily="{StaticResource Ico}" Foreground="#8FE3FF" FontSize="12" VerticalAlignment="Center" Margin="0,0,8,0"/><TextBlock x:Name="PillTxt" Foreground="White" FontSize="14" VerticalAlignment="Center"/></StackPanel></Border>
        </Button>
        <Border x:Name="UpdBox" CornerRadius="12" Background="#1B2350" BorderBrush="#3A4380" BorderThickness="1" Padding="12,3" HorizontalAlignment="Left" VerticalAlignment="Center" Visibility="Collapsed">
          <StackPanel Orientation="Horizontal">
            <TextBlock x:Name="UpdIco" Text="&#xE895;" FontFamily="{StaticResource Ico}" Foreground="#8FE3FF" FontSize="13" VerticalAlignment="Center" Margin="0,0,8,0" RenderTransformOrigin="0.5,0.5"><TextBlock.RenderTransform><RotateTransform x:Name="UpdRot"/></TextBlock.RenderTransform></TextBlock>
            <TextBlock x:Name="UpdTxt" Foreground="White" FontSize="12.5" VerticalAlignment="Center" MaxWidth="380" TextTrimming="CharacterEllipsis"/>
            <ProgressBar x:Name="UpdBar" Style="{StaticResource Meter}" Width="120" Margin="10,0,0,0" VerticalAlignment="Center"/>
            <Button x:Name="UpdBtn" Style="{StaticResource Chrome}" Width="Auto" Height="24" Margin="10,0,0,0" Visibility="Collapsed"><TextBlock Text="Перезапустить" Foreground="#8FE3FF" FontSize="12.5" Margin="8,0"/></Button>
          </StackPanel>
        </Border>
        </StackPanel>
        <Border x:Name="Snack" CornerRadius="12" Background="#2B3470" Padding="14,6" HorizontalAlignment="Right" VerticalAlignment="Center" Opacity="0">
          <Border.RenderTransform><TranslateTransform x:Name="SnackShift" Y="12"/></Border.RenderTransform>
          <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE768;" FontFamily="{StaticResource Ico}" Foreground="#8FE3FF" FontSize="12" VerticalAlignment="Center" Margin="0,0,8,0"/><TextBlock x:Name="SnackTxt" Foreground="White" FontSize="13"/></StackPanel>
        </Border>
      </Grid>
    </Grid>
  </Grid>
</Window>
'@
$win = [Windows.Markup.XamlReader]::Parse($xaml)
function G($n) { $win.FindName($n) }

# ---------- Живые картинки категорий (XAML, анимации 30 кадров/с) ----------
$artNS = 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
$arts = @{
 home = @"
<Canvas $artNS Width="120" Height="90">
  <Ellipse Canvas.Left="10" Canvas.Top="4" Width="100" Height="82" Fill="#7C5CFF" Opacity="0.12"/>
  <Border Canvas.Left="22" Canvas.Top="14" Width="76" Height="50" CornerRadius="7" BorderThickness="3" Background="#151B44"><Border.BorderBrush><LinearGradientBrush><GradientStop Color="#7C5CFF"/><GradientStop Color="#00C2FF" Offset="1"/></LinearGradientBrush></Border.BorderBrush></Border>
  <Rectangle Canvas.Left="12" Canvas.Top="66" Width="96" Height="8" RadiusX="4" RadiusY="4" Fill="#00C2FF"/>
  <Path Canvas.Left="30" Canvas.Top="24" Data="M0,16 L16,16 L22,4 L30,28 L36,10 L42,16 L60,16" Stroke="#3DDC97" StrokeThickness="2.5" StrokeLineJoin="Round" StrokeDashArray="34 34" StrokeDashOffset="34">
    <Path.Triggers><EventTrigger RoutedEvent="Loaded"><BeginStoryboard><Storyboard RepeatBehavior="Forever" Timeline.DesiredFrameRate="30"><DoubleAnimation Storyboard.TargetProperty="StrokeDashOffset" From="34" To="-34" Duration="0:0:1.8"/></Storyboard></BeginStoryboard></EventTrigger></Path.Triggers></Path>
  <Path Canvas.Left="92" Canvas.Top="2" Data="M7,0 L9,5 L14,7 L9,9 L7,14 L5,9 L0,7 L5,5 Z" Fill="#FFD166" RenderTransformOrigin="0.5,0.5"><Path.RenderTransform><ScaleTransform/></Path.RenderTransform>
    <Path.Triggers><EventTrigger RoutedEvent="Loaded"><BeginStoryboard><Storyboard RepeatBehavior="Forever" AutoReverse="True" Timeline.DesiredFrameRate="30"><DoubleAnimation Storyboard.TargetProperty="RenderTransform.ScaleX" From="0.5" To="1.2" Duration="0:0:0.8"/><DoubleAnimation Storyboard.TargetProperty="RenderTransform.ScaleY" From="0.5" To="1.2" Duration="0:0:0.8"/></Storyboard></BeginStoryboard></EventTrigger></Path.Triggers></Path>
</Canvas>
"@
 net = @"
<Canvas $artNS Width="120" Height="90">
  <Ellipse Canvas.Left="10" Canvas.Top="4" Width="100" Height="82" Fill="#00C2FF" Opacity="0.10"/>
  <Ellipse Canvas.Left="33" Canvas.Top="18" Width="54" Height="54" Stroke="#00C2FF" StrokeThickness="3" Fill="#122248"/>
  <Line X1="33" Y1="45" X2="87" Y2="45" Stroke="#00C2FF" StrokeThickness="2" Opacity="0.7"/>
  <Ellipse Canvas.Left="33" Canvas.Top="18" Width="54" Height="54" Stroke="#7C5CFF" StrokeThickness="2.5" RenderTransformOrigin="0.5,0.5"><Ellipse.RenderTransform><ScaleTransform ScaleX="1"/></Ellipse.RenderTransform>
    <Ellipse.Triggers><EventTrigger RoutedEvent="Loaded"><BeginStoryboard><Storyboard RepeatBehavior="Forever" AutoReverse="True" Timeline.DesiredFrameRate="30"><DoubleAnimation Storyboard.TargetProperty="RenderTransform.ScaleX" From="1" To="0.08" Duration="0:0:1.4"/></Storyboard></BeginStoryboard></EventTrigger></Ellipse.Triggers></Ellipse>
  <Grid Canvas.Left="20" Canvas.Top="5" Width="80" Height="80" RenderTransformOrigin="0.5,0.5"><Grid.RenderTransform><RotateTransform/></Grid.RenderTransform>
    <Ellipse Width="10" Height="10" Fill="#3DDC97" VerticalAlignment="Top" HorizontalAlignment="Center"/>
    <Grid.Triggers><EventTrigger RoutedEvent="Loaded"><BeginStoryboard><Storyboard RepeatBehavior="Forever" Timeline.DesiredFrameRate="30"><DoubleAnimation Storyboard.TargetProperty="RenderTransform.Angle" From="0" To="360" Duration="0:0:3"/></Storyboard></BeginStoryboard></EventTrigger></Grid.Triggers></Grid>
</Canvas>
"@
 speed = @"
<Canvas $artNS Width="120" Height="90">
  <Ellipse Canvas.Left="10" Canvas.Top="4" Width="100" Height="82" Fill="#FFD166" Opacity="0.08"/>
  <Path Data="M20,70 A40,40 0 0 1 100,70" StrokeThickness="9" StrokeStartLineCap="Round" StrokeEndLineCap="Round"><Path.Stroke><LinearGradientBrush StartPoint="0,0" EndPoint="1,0"><GradientStop Color="#3DDC97"/><GradientStop Color="#FFD166" Offset="0.55"/><GradientStop Color="#FF5C7A" Offset="1"/></LinearGradientBrush></Path.Stroke></Path>
  <Rectangle Canvas.Left="58" Canvas.Top="34" Width="4" Height="36" RadiusX="2" RadiusY="2" Fill="White" RenderTransformOrigin="0.5,1"><Rectangle.RenderTransform><RotateTransform Angle="-60"/></Rectangle.RenderTransform>
    <Rectangle.Triggers><EventTrigger RoutedEvent="Loaded"><BeginStoryboard><Storyboard RepeatBehavior="Forever" AutoReverse="True" Timeline.DesiredFrameRate="30"><DoubleAnimation Storyboard.TargetProperty="RenderTransform.Angle" From="-65" To="55" Duration="0:0:1.6"><DoubleAnimation.EasingFunction><BackEase EasingMode="EaseInOut" Amplitude="0.4"/></DoubleAnimation.EasingFunction></DoubleAnimation></Storyboard></BeginStoryboard></EventTrigger></Rectangle.Triggers></Rectangle>
  <Ellipse Canvas.Left="53" Canvas.Top="63" Width="14" Height="14" Fill="#7C5CFF"/>
</Canvas>
"@
 protect = @"
<Canvas $artNS Width="120" Height="90">
  <Ellipse Canvas.Left="10" Canvas.Top="4" Width="100" Height="82" Fill="#3DDC97" Opacity="0.08"/>
  <Path Data="M60,6 L92,18 L92,42 C92,62 78,77 60,84 C42,77 28,62 28,42 L28,18 Z"><Path.Fill><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#7C5CFF"/><GradientStop Color="#00C2FF" Offset="1"/></LinearGradientBrush></Path.Fill></Path>
  <Canvas Width="120" Height="90"><Canvas.Clip><PathGeometry Figures="M60,6 L92,18 L92,42 C92,62 78,77 60,84 C42,77 28,62 28,42 L28,18 Z"/></Canvas.Clip>
    <Rectangle Canvas.Top="0" Width="22" Height="90" Opacity="0.35" Fill="White"><Rectangle.RenderTransform><TransformGroup><SkewTransform AngleX="-20"/><TranslateTransform X="0"/></TransformGroup></Rectangle.RenderTransform>
      <Rectangle.Triggers><EventTrigger RoutedEvent="Loaded"><BeginStoryboard><Storyboard RepeatBehavior="Forever" Timeline.DesiredFrameRate="30"><DoubleAnimation Storyboard.TargetProperty="RenderTransform.Children[1].X" From="0" To="130" Duration="0:0:1.2" BeginTime="0:0:0.6"/></Storyboard></BeginStoryboard></EventTrigger></Rectangle.Triggers></Rectangle></Canvas>
  <Path Data="M45,45 L56,56 L77,33" Stroke="White" StrokeThickness="6" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" StrokeDashArray="10 10" StrokeDashOffset="10">
    <Path.Triggers><EventTrigger RoutedEvent="Loaded"><BeginStoryboard><Storyboard RepeatBehavior="Forever" Timeline.DesiredFrameRate="30"><DoubleAnimationUsingKeyFrames Storyboard.TargetProperty="StrokeDashOffset" Duration="0:0:2.4"><LinearDoubleKeyFrame Value="10" KeyTime="0:0:0"/><EasingDoubleKeyFrame Value="0" KeyTime="0:0:0.5"/><LinearDoubleKeyFrame Value="0" KeyTime="0:0:2.4"/></DoubleAnimationUsingKeyFrames></Storyboard></BeginStoryboard></EventTrigger></Path.Triggers></Path>
</Canvas>
"@
 guards = @"
<Canvas $artNS Width="120" Height="90">
  <Ellipse Canvas.Left="22" Canvas.Top="7" Width="76" Height="76" Stroke="#2E3A7A" StrokeThickness="2" Fill="#0F1735"/>
  <Ellipse Canvas.Left="37" Canvas.Top="22" Width="46" Height="46" Stroke="#2E3A7A" StrokeThickness="2"/>
  <Ellipse Canvas.Left="52" Canvas.Top="37" Width="16" Height="16" Stroke="#2E3A7A" StrokeThickness="2"/>
  <Path Data="M60,45 L60,7 A38,38 0 0 1 93,26 Z" RenderTransformOrigin="0,0"><Path.Fill><LinearGradientBrush StartPoint="0,0" EndPoint="1,0"><GradientStop Color="#003DDC97" Offset="0"/><GradientStop Color="#AA3DDC97" Offset="1"/></LinearGradientBrush></Path.Fill>
    <Path.RenderTransform><RotateTransform CenterX="60" CenterY="45"/></Path.RenderTransform>
    <Path.Triggers><EventTrigger RoutedEvent="Loaded"><BeginStoryboard><Storyboard RepeatBehavior="Forever" Timeline.DesiredFrameRate="30"><DoubleAnimation Storyboard.TargetProperty="RenderTransform.Angle" From="0" To="360" Duration="0:0:2.6"/></Storyboard></BeginStoryboard></EventTrigger></Path.Triggers></Path>
  <Ellipse Canvas.Left="74" Canvas.Top="24" Width="8" Height="8" Fill="#3DDC97"><Ellipse.Triggers><EventTrigger RoutedEvent="Loaded"><BeginStoryboard><Storyboard RepeatBehavior="Forever" AutoReverse="True" Timeline.DesiredFrameRate="20"><DoubleAnimation Storyboard.TargetProperty="Opacity" From="1" To="0.1" Duration="0:0:0.9"/></Storyboard></BeginStoryboard></EventTrigger></Ellipse.Triggers></Ellipse>
  <Ellipse Canvas.Left="40" Canvas.Top="56" Width="7" Height="7" Fill="#FFD166"><Ellipse.Triggers><EventTrigger RoutedEvent="Loaded"><BeginStoryboard><Storyboard RepeatBehavior="Forever" AutoReverse="True" BeginTime="0:0:0.5" Timeline.DesiredFrameRate="20"><DoubleAnimation Storyboard.TargetProperty="Opacity" From="1" To="0.1" Duration="0:0:0.9"/></Storyboard></BeginStoryboard></EventTrigger></Ellipse.Triggers></Ellipse>
</Canvas>
"@
 help = @"
<Canvas $artNS Width="120" Height="90">
  <Ellipse Canvas.Left="10" Canvas.Top="4" Width="100" Height="82" Fill="#FF9DB0" Opacity="0.08"/>
  <Border Canvas.Left="18" Canvas.Top="16" Width="84" Height="48" CornerRadius="18"><Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#7C5CFF"/><GradientStop Color="#00C2FF" Offset="1"/></LinearGradientBrush></Border.Background></Border>
  <Path Data="M34,62 L30,76 L46,63 Z" Fill="#5F79FF"/>
  <StackPanel Canvas.Left="38" Canvas.Top="36" Orientation="Horizontal">
    <Ellipse Width="10" Height="10" Fill="White" Margin="0,0,7,0"><Ellipse.RenderTransform><TranslateTransform/></Ellipse.RenderTransform><Ellipse.Triggers><EventTrigger RoutedEvent="Loaded"><BeginStoryboard><Storyboard RepeatBehavior="Forever" Timeline.DesiredFrameRate="30"><DoubleAnimationUsingKeyFrames Storyboard.TargetProperty="RenderTransform.Y" Duration="0:0:1.2"><EasingDoubleKeyFrame Value="-6" KeyTime="0:0:0.2"/><EasingDoubleKeyFrame Value="0" KeyTime="0:0:0.4"/></DoubleAnimationUsingKeyFrames></Storyboard></BeginStoryboard></EventTrigger></Ellipse.Triggers></Ellipse>
    <Ellipse Width="10" Height="10" Fill="White" Margin="0,0,7,0"><Ellipse.RenderTransform><TranslateTransform/></Ellipse.RenderTransform><Ellipse.Triggers><EventTrigger RoutedEvent="Loaded"><BeginStoryboard><Storyboard RepeatBehavior="Forever" Timeline.DesiredFrameRate="30"><DoubleAnimationUsingKeyFrames Storyboard.TargetProperty="RenderTransform.Y" Duration="0:0:1.2"><EasingDoubleKeyFrame Value="0" KeyTime="0:0:0.15"/><EasingDoubleKeyFrame Value="-6" KeyTime="0:0:0.35"/><EasingDoubleKeyFrame Value="0" KeyTime="0:0:0.55"/></DoubleAnimationUsingKeyFrames></Storyboard></BeginStoryboard></EventTrigger></Ellipse.Triggers></Ellipse>
    <Ellipse Width="10" Height="10" Fill="White"><Ellipse.RenderTransform><TranslateTransform/></Ellipse.RenderTransform><Ellipse.Triggers><EventTrigger RoutedEvent="Loaded"><BeginStoryboard><Storyboard RepeatBehavior="Forever" Timeline.DesiredFrameRate="30"><DoubleAnimationUsingKeyFrames Storyboard.TargetProperty="RenderTransform.Y" Duration="0:0:1.2"><EasingDoubleKeyFrame Value="0" KeyTime="0:0:0.3"/><EasingDoubleKeyFrame Value="-6" KeyTime="0:0:0.5"/><EasingDoubleKeyFrame Value="0" KeyTime="0:0:0.7"/></DoubleAnimationUsingKeyFrames></Storyboard></BeginStoryboard></EventTrigger></Ellipse.Triggers></Ellipse>
  </StackPanel>
</Canvas>
"@ }

# ---------- Разделы и инструменты ----------
# Тип: admin — от администратора внутри окна; user — внутри окна; gui — своё окно; exe/note/folder — открыть; toggle — переключатель.
$tools = @{
  net = @(
    @('&#xE714;', 'Не работает YouTube или Discord', 'Подберу новый способ обхода сам', "$Hd\zapret-repick.ps1", 'admin'),
    @('&#xE774;', 'Сайт не открывается', 'Проверю сайт и открою через VPN', "$Hd\site-fix.ps1", 'user'),
    @('&#xE72E;', 'Заблокированные сайты', '', "$Hd\smart-proxy.ps1", 'toggle'),
    @('&#xE724;', 'Не работает Telegram', 'Переподключу Happ — прокси для Telegram', "$Hd\happ-connect.ps1", 'user'),
    @('&#xE909;', 'Какие сайты открываются', 'YouTube, Discord, Telegram, Instagram и другие', "$Hd\check-sites.ps1", 'user'),
    @('&#xE701;', 'Интернет совсем не работает', 'Сброшу сеть и перезапущу Wi-Fi', "$Gd\fix-internet.ps1", 'admin'))
  speed = @(
    @('&#xEC4A;', 'Что тормозит сейчас', 'Покажу, что грузит ноутбук, и что делать', "$Hd\perf-now.ps1", 'user'),
    @('&#xE74D;', 'Почистить мусор', 'Временные файлы, Корзина — по слову', "$Hd\clean-junk.ps1", 'admin'),
    @('&#xE7E8;', 'Что запускается с Windows', 'Список и отключение лишнего', "$Hd\startup-all.ps1", 'admin'),
    @('&#xEDA2;', 'Что занимает место', 'Самые большие папки, ничего не удаляю', "$Hd\disk-space.ps1", 'user'),
    @('&#xE896;', 'Разобрать Загрузки', 'Картинки, видео, документы — по папкам', "$Hd\sort-downloads.ps1", 'user'),
    @('&#xE7A7;', 'Вернуть Загрузки как было', 'Отменю разбор Загрузок', "$Hd\undo-sort-downloads.ps1", 'user'),
    @('&#xE895;', 'Обновить программы', 'Найду и поставлю новые версии', "$Hd\update-apps.ps1", 'admin'),
    @('&#xE90F;', 'Не открываются файлы или меню', 'Найду и исправлю причину', "$Hd\file-repair.ps1", 'admin'))
  protect = @(
    @('&#xEA18;', 'Проверка безопасности', 'Нет ли вирусов в автозапуске и Загрузках', "$Gd\check-now.ps1", 'user'),
    @('&#xE88E;', 'Резервная копия', 'Документы и фото на флешку', "$Hd\backup.ps1", 'admin'),
    @('&#xE714;', 'Кто включал камеру и микрофон', 'Какие программы и когда снимали или слушали', "$Hd\privacy-check.ps1", 'user'),
    @('&#xE83F;', 'Отчёт о батарее', 'Износ и состояние батареи', "$Gd\battery-report.ps1", 'user'),
    @('&#xE721;', 'Найти файл', 'Мгновенный поиск любого файла (Everything)', 'C:\Program Files\Everything\Everything.exe', 'exe'))
  help = @(
    @('&#xE77B;', 'Позвать помощь', 'Покажу номер AnyDesk и скопирую его', "$Hd\call-help.ps1", 'gui'),
    @('&#xE8A5;', 'Прочитать подсказки', 'Что делает каждая кнопка', (Join-Path $Tools 'ПРОЧИТАЙ МЕНЯ.txt'), 'note'),
    @('&#xE838;', 'Все инструменты', 'Папка со всеми ярлыками', $Tools, 'folder'),
    @('&#xE895;', 'Проверить обновления Помощника', 'Скачаю новую версию, если она вышла', '', 'update')) }
$pages = [ordered]@{
  home    = @('&#xE80F;', 'Главная', '', '')
  net     = @('&#xE774;', 'Интернет', 'Интернет и блокировки', 'YouTube, Discord, Telegram и заблокированные сайты — всё чинится здесь.')
  speed   = @('&#xEC4A;', 'Скорость', 'Скорость и порядок', 'Что тормозит, что лишнее и где место на диске.')
  protect = @('&#xEA18;', 'Защита', 'Защита и копии', 'Вирусы, камера, батарея и резервная копия.')
  guards  = @('&#xE7B3;', 'Сторожа', 'Сторожа', 'Что работает в фоне, зачем оно нужно и что можно выключить.')
  help    = @('&#xE77B;', 'Помощь', 'Помощь', 'Если что-то непонятно или не работает — позови человека.') }
$quick = @($tools.net[0], $tools.net[1], $tools.speed[0], $tools.help[0])

$guards = @(
  @{ T = 'PCT-Guard-Autoruns'; I = '&#xEA18;'; N = 'Сторож автозапуска'; S = 'Раз в день ищет новое в автозагрузке'; Rec = 2
     W = 'Раз в день сравнивает автозагрузку со снимком «как было». Если появилась новая программа — присылает уведомление. Так ловятся вирусы, майнеры и программы-«прилипалы», которые прописываются сами.'
     R = 'Новый вирус в автозапуске останется незамеченным. Антивируса на этом ноутбуке нет — этот сторож один из главных способов защиты.'; L = 'Несколько секунд раз в день — незаметно.' },
  @{ T = 'PCT-Guard-Downloads'; I = '&#xE896;'; N = 'Сторож Загрузок'; S = 'Предупреждает об опасных скачанных файлах'; Rec = 2
     W = 'Каждые 15 минут смотрит новые файлы в «Загрузках». Если скачан файл без цифровой подписи или скрипт — предупреждает, прежде чем ты его откроешь.'
     R = 'Можно случайно открыть вредный файл без предупреждения. Именно так в прошлый раз попали два вируса.'; L = 'Доли секунды раз в 15 минут — незаметно.' },
  @{ T = 'PCT-Sites-Watch'; I = '&#xE714;'; N = 'Сторож YouTube и Discord'; S = 'Сам чинит обход блокировок'; Rec = 2
     W = 'При входе и каждые 3 часа проверяет YouTube и Discord. Если провайдер сменил блокировку — сам подбирает новый способ обхода и пишет уведомление. Заодно возвращает обход заблокированных сайтов, если его сбросили.'
     R = 'Когда YouTube или Discord сломаются, придётся заметить это самой и нажать «Не работает YouTube или Discord».'; L = 'Пара секунд раз в 3 часа. Подбор (до 10 минут) — только когда сайты уже не работают.' },
  @{ T = 'PCT-Zapret'; I = '&#xE785;'; N = 'Обход блокировок при входе'; S = 'Включает zapret после перезагрузки'; Rec = 2
     W = 'Когда ты входишь в Windows, включает zapret — программу, благодаря которой YouTube и Discord работают без VPN.'
     R = 'После каждой перезагрузки YouTube и Discord перестанут работать, пока не включишь обход вручную.'; L = 'Один запуск при входе. Сам zapret почти не тратит ресурсы.' },
  @{ T = 'PCT-Happ-Connect'; I = '&#xE724;'; N = 'Подключение Happ при входе'; S = 'Telegram и заблокированные сайты без VPN'; Rec = 2
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
  @{ T = 'PCT-Clean-Temp'; I = '&#xE74D;'; N = 'Уборка временных файлов'; S = 'По воскресеньям удаляет старый мусор'; Rec = 0
     W = 'По воскресеньям удаляет из папок Temp файлы старше 7 дней — то, что программы оставили и забыли. Твои файлы не трогает.'
     R = 'Ничего не сломается. Мусор будет копиться (за несколько месяцев — гигабайты); его можно убрать кнопкой «Почистить мусор».'; L = 'Около минуты раз в неделю.' })
$script:gs = @{}
$script:gp = @{}
# Состояние сторожей: один обход всех папок планировщика через COM (~140 мс вместо ~4 с у Get-ScheduledTask)
function TaskSvc { if (-not $script:svc) { $script:svc = New-Object -ComObject Schedule.Service; $script:svc.Connect() }; $script:svc }
function GuardScan { $m = @{}; $p = @{}
  try { $q = New-Object Collections.Queue; $q.Enqueue((TaskSvc).GetFolder('\'))
    while ($q.Count) { $f = $q.Dequeue()
      try { foreach ($t in $f.GetTasks(1)) { if (-not $m.ContainsKey($t.Name)) { $m[$t.Name] = $(if ($t.Enabled) { 'on' } else { 'off' }); $p[$t.Name] = $t.Path } } } catch {}
      try { foreach ($s in $f.GetFolders(0)) { $q.Enqueue($s) } } catch {} } } catch {}
  foreach ($g in $guards) { $script:gs[$g.T] = $(if ($m.ContainsKey($g.T)) { $m[$g.T] } else { '?' }); $script:gp[$g.T] = $p[$g.T] } }
function GuardOne($g) { try { $t = (TaskSvc).GetFolder('\').GetTask($script:gp[$g.T]); $script:gs[$g.T] = $(if ($t.Enabled) { 'on' } else { 'off' }) } catch { $script:gs[$g.T] = '?' } }
$recTxt = @{ 2 = 'Рекомендую держать включённым'; 1 = 'Лучше держать включённым'; 0 = 'Можно выключить — на защиту не влияет' }
$recCol = @{ 2 = '#1F7A55'; 1 = '#2B5DA8'; 0 = '#8A6A1E' }

$bc = New-Object Windows.Media.BrushConverter
function Br($c) { $bc.ConvertFromString($c) }
function PacOn { Test-Path "$Hd\smart-proxy-on.txt" }
function Glyph($code) { [string][char][Convert]::ToInt32(($code -replace '&#x|;', ''), 16) }
function Ease($from, $to, $ms) { if ($env:PCT_RENDER) { $ms = 1; $from = $to }; $a = New-Object Windows.Media.Animation.DoubleAnimation($from, $to, [TimeSpan]::FromMilliseconds($ms)); $a.EasingFunction = New-Object Windows.Media.Animation.CubicEase; $a }
function SlideIn($el, $shift, $dy) { $el.BeginAnimation([Windows.UIElement]::OpacityProperty, (Ease 0 1 260)); $shift.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, (Ease $dy 0 320)) }
function Snack($t) { (G 'SnackTxt').Text = $t; $sn = G 'Snack'
  $a1 = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames; foreach ($kf in @(@(0, 0), @(250, 1), @(2600, 1), @(3000, 0))) { [void]$a1.KeyFrames.Add((New-Object Windows.Media.Animation.LinearDoubleKeyFrame($kf[1], [TimeSpan]::FromMilliseconds($kf[0])))) }
  $sn.BeginAnimation([Windows.UIElement]::OpacityProperty, $a1); (G 'SnackShift').BeginAnimation([Windows.Media.TranslateTransform]::YProperty, (Ease 12 0 300)) }

function CardContent($it) {
  $g = New-Object Windows.Controls.Grid; [void]$g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{ Width = 'Auto' })); [void]$g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
  $ib = New-Object Windows.Controls.Border -Property @{ Width = 42; Height = 42; CornerRadius = 13; Background = (Br '#28306A') }
  if ($it[4] -eq 'toggle') { $ib.Background = $(if (PacOn) { $win.Resources['Accent'] } else { Br '#3A2F4F' }) }
  $ib.Child = New-Object Windows.Controls.TextBlock -Property @{ Text = (Glyph $it[0]); FontFamily = $win.Resources['Ico']; FontSize = 18; Foreground = (Br '#BFD4FF'); HorizontalAlignment = 'Center'; VerticalAlignment = 'Center' }
  $sp = New-Object Windows.Controls.StackPanel -Property @{ Margin = '13,0,0,0'; VerticalAlignment = 'Center' }; [Windows.Controls.Grid]::SetColumn($sp, 1)
  $title = $it[1]; $sub = $it[2]
  if ($it[4] -eq 'toggle') { if (PacOn) { $title = 'Заблокированные сайты: ВКЛ'; $sub = 'Instagram, X, ChatGPT… открываются сами' } else { $title = 'Заблокированные сайты: ВЫКЛ'; $sub = 'Нажми, чтобы Instagram, X… открывались сами' } }
  [void]$sp.Children.Add((New-Object Windows.Controls.TextBlock -Property @{ Text = $title; FontSize = 15; FontWeight = 'SemiBold'; Foreground = (Br '#FFFFFF'); TextTrimming = 'CharacterEllipsis' }))
  [void]$sp.Children.Add((New-Object Windows.Controls.TextBlock -Property @{ Text = $sub; FontSize = 12.5; Foreground = (Br '#98A2C8'); Margin = '0,3,0,0'; TextTrimming = 'CharacterEllipsis' }))
  [void]$g.Children.Add($ib); [void]$g.Children.Add($sp); $g }
function NewCard($it, $onClick) { $b = New-Object Windows.Controls.Button; $b.Style = $win.Resources['Card']; $b.Content = CardContent $it; $b.Tag = $it; $b.Add_Click($onClick); $b }
function Grid2($items) { $u = New-Object Windows.Controls.Primitives.UniformGrid -Property @{ Columns = 2; VerticalAlignment = 'Top' }; foreach ($c in $items) { [void]$u.Children.Add($c) }; $u }

# ---------- Ход работы внутри окна ----------
$colors = @{ Green = '#3DDC97'; DarkGreen = '#3DDC97'; Red = '#FF5C7A'; DarkRed = '#FF5C7A'; Yellow = '#FFD166'; DarkYellow = '#FFD166'; Cyan = '#8FE3FF'; DarkCyan = '#8FE3FF'; White = '#FFFFFF'; Gray = '#C9D0F0'; DarkGray = '#7F89B3'; Magenta = '#E59CFF'; Blue = '#8FA3FF' }
$script:run = $null
$script:runTimer = New-Object Windows.Threading.DispatcherTimer; $script:runTimer.Interval = [TimeSpan]::FromMilliseconds(150)
function Spin($rot, $on) { if ($on) { $ra = New-Object Windows.Media.Animation.DoubleAnimation(0, 360, [TimeSpan]::FromSeconds(1.1)); $ra.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever; $rot.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $ra) } else { $rot.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $null) } }
function AddLine($color, $text) {
  if (-not $text.Trim()) { [void](G 'ActLines').Children.Add((New-Object Windows.Controls.Border -Property @{ Height = 6 })); return }
  $tb = New-Object Windows.Controls.TextBlock -Property @{ Text = $text; FontFamily = (New-Object Windows.Media.FontFamily('Cascadia Mono, Consolas')); FontSize = 12.5; TextWrapping = 'Wrap'; Margin = '0,1,0,1' }
  $hex = $colors[$color]; if (-not $hex) { $hex = '#C9D0F0' }; $tb.Foreground = Br $hex
  if ($text -match '^\s*(===|—)') { $tb.FontWeight = 'Bold'; $tb.Foreground = Br '#8FA3FF'; $tb.Margin = '0,6,0,2' }
  $tt = New-Object Windows.Media.TranslateTransform(10, 0); $tb.RenderTransform = $tt
  [void](G 'ActLines').Children.Add($tb); $tb.BeginAnimation([Windows.UIElement]::OpacityProperty, (Ease 0 1 220)); $tt.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, (Ease 10 0 260))
  if ($text -match '^\s*\[!!\]') { $script:run.Bad++ }; if ($text -match '^\s*\[OK\]') { $script:run.Ok++ }
  (G 'ActScroll').ScrollToEnd() }
function Answer($a) { if (-not $script:run) { return }; [IO.File]::WriteAllText($script:run.Ans, "$a", (New-Object Text.UTF8Encoding $false)); (G 'AskBox').Visibility = 'Collapsed'; (G 'AskIn').Text = ''; PillSync }
function Ask($prompt) { $ctx = @((G 'ActLines').Children | Where-Object { $_ -is [Windows.Controls.TextBlock] } | Select-Object -Last 2 | ForEach-Object { $_.Text.Trim() })
  $q = (@($ctx) + @("$prompt".Trim()) | Where-Object { $_ }) -join "`n"; if (-not $q) { $q = 'Ответь и нажми «Ответить».' }
  (G 'AskTxt').Text = $q; $yn = $q -match 'д и |Напиши д|\(д/н\)|\[д/н\]|1 и Enter'
  (G 'AskYes').Visibility = $(if ($yn) { 'Visible' } else { 'Collapsed' }); (G 'AskNo').Visibility = (G 'AskYes').Visibility
  $ab = G 'AskBox'; $ab.Visibility = 'Visible'; $ab.BeginAnimation([Windows.UIElement]::OpacityProperty, (Ease 0 1 250)); (G 'AskIn').Focus() | Out-Null
  (G 'ActSub').Text = 'Нужен твой ответ — внизу'; Snack 'Нужен твой ответ'; PillSync }
# Процесс завершился, а строки E нет — действие прервалось
function RunAborted { $script:runTimer.Stop(); Spin (G 'ActRot') $false; (G 'ActIco').Text = [string][char]0xE783; (G 'AskBox').Visibility = 'Collapsed'
  $script:run.Res = 'bad'; $script:run.Seen = (G 'Act').Visibility -eq 'Visible'
  (G 'ActSub').Text = 'Действие прервалось. Попробуй ещё раз или позови помощь.'; (G 'ActCloseTxt').Text = 'Закрыть'; Snack 'Действие прервалось'; PillSync }
$script:runTimer.Add_Tick({
  $r = $script:run; if (-not $r) { $script:runTimer.Stop(); return }
  # Выход замечен на прошлом тике, лог после него уже дочитан
  if ($r.Gone) { RunAborted; return }; if ($r.Proc) { try { $r.Gone = $r.Proc.HasExited } catch {} }
  if (-not (Test-Path -LiteralPath $r.Log)) { if (((Get-Date) - $r.T0).TotalSeconds -gt 25) { $script:runTimer.Stop(); Spin (G 'ActRot') $false; (G 'ActSub').Text = 'Не удалось запустить. Попробуй ещё раз или позови помощь.'; PillSync }; return }
  if ((G 'AskBox').Visibility -ne 'Visible') { (G 'ActSub').Text = "Работаю… {0:N0} с" -f ((Get-Date) - $r.T0).TotalSeconds }
  try { $fs = [IO.File]::Open($r.Log, 'Open', 'Read', 'ReadWrite'); $len = $fs.Length - $r.Pos
    if ($len -le 0) { $fs.Close(); return }; [void]$fs.Seek($r.Pos, 'Begin'); $buf = New-Object byte[] $len; $n = $fs.Read($buf, 0, $len); $fs.Close()
    $last = [Array]::LastIndexOf($buf, [byte]10, $n - 1); if ($last -lt 0) { return }; $r.Pos += $last + 1
    foreach ($ln in ([Text.Encoding]::UTF8.GetString($buf, 0, $last) -split "`n")) { $p = $ln -split '\|', 3; if ($p.Count -lt 3) { continue }
      switch ($p[0]) {
        'L' { AddLine $p[1] $p[2] }
        'P' { Ask $p[2] }
        'A' { AddLine 'Cyan' ("→ твой ответ: " + $(if ($p[2]) { $p[2] } else { '(пусто)' })) }
        'E' { $script:runTimer.Stop(); Spin (G 'ActRot') $false; (G 'ActIco').Text = [string][char]0xE73E; (G 'AskBox').Visibility = 'Collapsed'; $r.Res = 'ok'; $r.Seen = (G 'Act').Visibility -eq 'Visible'
              (G 'ActSub').Text = "Готово за $($p[2]) с" + $(if ($r.Bad) { " · замечаний: $($r.Bad) (строки [!!])" } elseif ($r.Ok) { ' · всё в порядке' } else { '' })
              (G 'ActCloseTxt').Text = 'Закрыть'; Snack "Готово: $($r.Title)"; PillSync; Tick } } } } catch {} })
function RunInApp($it) {
  if ($script:run -and $script:runTimer.IsEnabled) { ShowAct; Snack 'Сначала дождись, пока закончится текущее действие'; return }
  $id = [guid]::NewGuid().ToString('N').Substring(0, 10)
  $a = "-NoProfile -ExecutionPolicy Bypass -File `"$Hd\run.ps1`" -Script `"$($it[3])`" -Id $id"
  try { if ($it[4] -eq 'admin') { $p = Start-Process $ps -ArgumentList $a -Verb RunAs -WindowStyle Hidden -PassThru -ErrorAction Stop } else { $p = Start-Process $ps -ArgumentList $a -WindowStyle Hidden -PassThru -ErrorAction Stop } }
  catch { Snack 'Отменено'; return }
  $script:run = @{ Id = $id; Log = "$RunDir\$id.log"; Ans = "$RunDir\$id.ans"; Pos = 0; T0 = Get-Date; Title = $it[1]; Bad = 0; Ok = 0; Proc = $p; Gone = $false }
  (G 'ActLines').Children.Clear(); (G 'ActTitle').Text = $it[1]; (G 'ActSub').Text = 'Запускаю…'; (G 'ActIco').Text = [string][char]0xE895; (G 'ActCloseTxt').Text = 'Свернуть'; (G 'AskBox').Visibility = 'Collapsed'
  Spin (G 'ActRot') $true; ShowAct; $script:runTimer.Start() }
function ShowAct { (G 'Detail').Visibility = 'Collapsed'; $a = G 'Act'; $a.Visibility = 'Visible'; SlideIn $a (G 'ActShift') 24; if ($script:run) { $script:run.Seen = $true }; PillSync }
# Метка внизу: работа идёт или итог ещё не увиден, а панель хода скрыта
function HintSync { (G 'Hint').Visibility = $(if ((G 'UpdBox').Visibility -eq 'Visible' -or (G 'RunPill').Visibility -eq 'Visible') { 'Collapsed' } else { 'Visible' }) }
function PillSync($force) { $r = $script:run; $busy = $force -or ($r -and $script:runTimer.IsEnabled)
  $on = $busy -or ($r -and $r.Res -and -not $r.Seen); if ((G 'Act').Visibility -eq 'Visible' -and -not $force) { $on = $false }
  if ($on) { $ico = G 'PillIco'
    if ($busy) { $ico.Text = [string][char]0xE895; $ico.Foreground = Br '#8FE3FF'; (G 'PillTxt').Text = $(if ((G 'AskBox').Visibility -eq 'Visible') { 'Ждёт твой ответ — показать' } else { "Идёт: $($r.Title) — показать" }) }
    elseif ($r.Res -eq 'ok') { $ico.Text = [string][char]0xE73E; $ico.Foreground = Br '#3DDC97'; (G 'PillTxt').Text = "Готово: $($r.Title) — показать" }
    else { $ico.Text = [string][char]0xE783; $ico.Foreground = Br '#FFB86B'; (G 'PillTxt').Text = "Прервалось: $($r.Title) — показать" } }
  (G 'RunPill').Visibility = $(if ($on) { 'Visible' } else { 'Collapsed' }); HintSync }

function Run($it, $btn) {
  try { switch ($it[4]) {
      'admin'  { RunInApp $it }
      'user'   { RunInApp $it }
      'gui'    { Start-Process $con -ArgumentList "--headless $ps -NoProfile -ExecutionPolicy Bypass -File `"$($it[3])`""; Snack "Открываю: $($it[1])" }
      'exe'    { Start-Process $it[3]; Snack "Открываю: $($it[1])" }
      'note'   { Start-Process notepad.exe -ArgumentList "`"$($it[3])`"" }
      'folder' { Start-Process explorer.exe -ArgumentList "`"$($it[3])`"" }
      'update' { StartUpdate }
      'toggle' { if (PacOn) { & $it[3] -Off; Snack 'Заблокированные сайты: выключено' } else { & $it[3] -On; Snack 'Заблокированные сайты: включено — обнови страницу' }; $btn.Content = CardContent $it; Tick } } }
  catch { Snack 'Отменено' } }
$onCard = { param($s, $e) Run $s.Tag $s }

# ---------- Сторожа ----------
function GuardCard($g) { $st = $script:gs[$g.T]
  $cc = CardContent @($g.I, $g.N, ("{0} · {1}" -f $(if ($st -eq 'on') { 'ВКЛ' } elseif ($st -eq 'off') { 'ВЫКЛ' } else { 'нет задачи' }), $g.S), '', 'guard')
  $cc.Children[0].Background = $(if ($st -eq 'on') { $win.Resources['Accent'] } else { Br '#3A2F4F' }); $cc }
function ShowDetail($g) { $st = $script:gs[$g.T]; $script:cur = $g
  (G 'DIcon').Text = Glyph $g.I; (G 'DTitle').Text = $g.N
  (G 'DState').Text = $(if ($st -eq 'on') { '● Сейчас включён' } elseif ($st -eq 'off') { '● Сейчас выключен' } else { '● Задача не найдена' }); (G 'DState').Foreground = Br $(if ($st -eq 'on') { '#3DDC97' } else { '#FF5C7A' })
  (G 'DRec').Text = $recTxt[$g.Rec]; (G 'DRecBox').Background = Br $recCol[$g.Rec]
  (G 'DWhat').Text = $g.W; (G 'DRisk').Text = $g.R; (G 'DLoad').Text = $g.L
  (G 'DToggleTxt').Text = $(if ($st -eq 'on') { 'Выключить' } else { 'Включить' }); (G 'DToggle').IsEnabled = $st -ne '?' -and -not $script:tgTimer.IsEnabled
  $d = G 'Detail'; $d.Visibility = 'Visible'; SlideIn $d (G 'DetailShift') 30 }

# ---------- Страницы ----------
function Chip($ok, $tOk, $tBad) { $b = New-Object Windows.Controls.Border; $b.Style = $win.Resources['Chip']; $sp = New-Object Windows.Controls.StackPanel -Property @{ Orientation = 'Horizontal' }
  $dot = New-Object Windows.Shapes.Ellipse; $dot.Style = $win.Resources['Dot']; $dot.Fill = Br $(if ($ok) { '#3DDC97' } else { '#FF5C7A' })
  [void]$sp.Children.Add($dot); [void]$sp.Children.Add((New-Object Windows.Controls.TextBlock -Property @{ Text = $(if ($ok) { $tOk } else { $tBad }); Foreground = (Br '#DDE3FF'); FontSize = 13 })); $b.Child = $sp; $b }
function Hello { $h = (Get-Date).Hour; if ($h -lt 5) { 'Доброй ночи!' } elseif ($h -lt 12) { 'Доброе утро!' } elseif ($h -lt 18) { 'Добрый день!' } else { 'Добрый вечер!' } }
function ShowPage($key) { $script:page = $key; $b = G 'Body'; $b.Children.Clear(); (G 'Detail').Visibility = 'Collapsed'
  (G 'Act').Visibility = 'Collapsed'; PillSync
  (G 'Art').Content = [Windows.Markup.XamlReader]::Parse($arts[$key])
  if ($key -eq 'home') { (G 'PTitle').Text = Hello; (G 'PSub').Text = 'Всё для ноутбука в одном месте. Нажми нужную карточку — остальное я сделаю сам и покажу каждый шаг.'
    $wp = New-Object Windows.Controls.WrapPanel -Property @{ Margin = '0,2,0,6' }; $script:chipPanel = $wp; [void]$b.Children.Add($wp); FillChips
    $hero = New-Object Windows.Controls.Button; $hero.Style = $win.Resources['Hero']; $hero.Margin = '5,2,5,14'
    $hero.Content = [Windows.Markup.XamlReader]::Parse("<StackPanel $artNS Orientation=`"Horizontal`"><Border Width=`"46`" Height=`"46`" CornerRadius=`"15`" Background=`"#33FFFFFF`"><TextBlock Text=`"&#xE9D9;`" FontFamily=`"Segoe Fluent Icons, Segoe MDL2 Assets`" FontSize=`"22`" Foreground=`"White`" HorizontalAlignment=`"Center`" VerticalAlignment=`"Center`"/></Border><StackPanel Margin=`"16,0,0,0`" VerticalAlignment=`"Center`"><TextBlock Text=`"Проверить ноутбук`" Foreground=`"White`" FontSize=`"19`" FontWeight=`"SemiBold`"/><TextBlock Text=`"Найдёт, что не так, и скажет, что делать. Каждый шаг — прямо здесь.`" Foreground=`"#E8ECFF`" FontSize=`"13.5`" Margin=`"0,2,0,0`"/></StackPanel></StackPanel>")
    $hero.Tag = @('', 'Проверить ноутбук', '', "$Hd\system-health.ps1", 'admin'); $hero.Add_Click($onCard); [void]$b.Children.Add($hero)
    [void]$b.Children.Add((New-Object Windows.Controls.TextBlock -Property @{ Text = 'ЧАСТО НУЖНО'; Foreground = (Br '#7F89B3'); FontSize = 12; FontWeight = 'SemiBold'; Margin = '6,0,0,4' }))
    [void]$b.Children.Add((Grid2 @($quick | ForEach-Object { NewCard $_ $onCard }))) }
  else { $pg = $pages[$key]; (G 'PTitle').Text = $pg[2]; (G 'PSub').Text = $pg[3]
    if ($key -eq 'guards') { GuardScan
      [void]$b.Children.Add((Grid2 @($guards | ForEach-Object { $c = New-Object Windows.Controls.Button; $c.Style = $win.Resources['Card']; $c.Content = GuardCard $_; $c.Tag = $_; $c.Add_Click({ param($s, $e) ShowDetail $s.Tag }); $c }))) }
    else { [void]$b.Children.Add((Grid2 @($tools[$key] | ForEach-Object { NewCard $_ $onCard }))) } }
  SlideIn (G 'Page') (G 'PageShift') 18 }

# ---------- Живые показатели ----------
$script:prev = $null
function Cpu { $i = 0L; $k = 0L; $u = 0L; [void][PCT.Sys]::GetSystemTimes([ref]$i, [ref]$k, [ref]$u); $now = @($i, ($k + $u))
  $v = 0; if ($script:prev) { $di = $now[0] - $script:prev[0]; $dt = $now[1] - $script:prev[1]; if ($dt -gt 0) { $v = [math]::Round(100 * (1 - $di / $dt)) } }; $script:prev = $now; [math]::Max(0, [math]::Min(100, $v)) }
function Anim($bar, $v) { $bar.BeginAnimation([Windows.Controls.Primitives.RangeBase]::ValueProperty, (New-Object Windows.Media.Animation.DoubleAnimation($v, [TimeSpan]::FromMilliseconds(700)))) }
function FillChips { $wp = $script:chipPanel; if (-not $wp) { return }; $wp.Children.Clear()
  $hp = [bool]([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() | Where-Object Port -eq 10808)
  [void]$wp.Children.Add((Chip ([bool](Get-Process winws)) 'YouTube и Discord: работают' 'YouTube и Discord: обход выключен'))
  [void]$wp.Children.Add((Chip $hp 'Happ подключён' 'Happ не подключён'))
  [void]$wp.Children.Add((Chip (PacOn) 'Заблокированные сайты открываются' 'Заблокированные сайты: выкл')) }
$script:tickN = 0
function Tick { $c = Cpu; $m = [PCT.Sys]::MemLoad(); Anim (G 'BarC') $c; Anim (G 'BarM') $m; (G 'TxtC').Text = "$c%"; (G 'TxtM').Text = "$m%"
  $script:tickN++; if ($script:page -eq 'home' -and ($script:tickN % 5 -eq 0)) { FillChips } }

# ---------- Автообновление: updater.ps1 в фоне, ход — из update-status.json ----------
$script:updTimer = New-Object Windows.Threading.DispatcherTimer; $script:updTimer.Interval = [TimeSpan]::FromMilliseconds(250)
function UpdShow($on) { (G 'UpdBox').Visibility = $(if ($on) { 'Visible' } else { 'Collapsed' }); HintSync }
function UpdLater($ms) { $h = New-Object Windows.Threading.DispatcherTimer; $h.Interval = [TimeSpan]::FromMilliseconds($ms); $h.Add_Tick({ param($s, $e) $s.Stop(); UpdShow $false }); $h.Start() }
$script:updTimer.Add_Tick({
  $j = $null; try { $j = [IO.File]::ReadAllText("$Hd\update-status.json") | ConvertFrom-Json } catch {}
  if (-not $j) { if (((Get-Date) - $script:updT0).TotalSeconds -gt 90) { $script:updTimer.Stop(); Spin (G 'UpdRot') $false; UpdShow $false }; return }
  (G 'UpdTxt').Text = $j.msg
  switch ($j.state) {
    'checking'    { UpdShow $true; (G 'UpdBar').Visibility = 'Collapsed' }
    'downloading' { UpdShow $true; (G 'UpdBar').Visibility = 'Visible'; Anim (G 'UpdBar') ([double]$j.pct) }
    'installing'  { UpdShow $true; Anim (G 'UpdBar') 100 }
    'done'        { $script:updTimer.Stop(); Spin (G 'UpdRot') $false; UpdShow $true; (G 'UpdIco').Text = [string][char]0xE73E; (G 'UpdIco').Foreground = Br '#3DDC97'; (G 'UpdBar').Visibility = 'Collapsed'
                    (G 'UpdTxt').Text = "Обновлено до $($j.ver)" + $(if ($j.notes) { " — $($j.notes)" }); (G 'UpdBtn').Visibility = 'Visible'; Snack "Помощник обновлён до $($j.ver)" }
    'uptodate'    { $script:updTimer.Stop(); Spin (G 'UpdRot') $false; UpdShow $true; (G 'UpdIco').Text = [string][char]0xE73E; (G 'UpdIco').Foreground = Br '#3DDC97'; (G 'UpdBar').Visibility = 'Collapsed'; UpdLater 2500 }
    'error'       { $script:updTimer.Stop(); Spin (G 'UpdRot') $false; UpdShow $true; (G 'UpdIco').Text = [string][char]0xE783; (G 'UpdIco').Foreground = Br '#FFB86B'; (G 'UpdBar').Visibility = 'Collapsed'; UpdLater 4000 } } })
function StartUpdate { if (-not (Test-Path "$Hd\updater.ps1")) { return }
  Remove-Item "$Hd\update-status.json" -Force; $script:updT0 = Get-Date; (G 'UpdIco').Text = [string][char]0xE895; (G 'UpdIco').Foreground = Br '#8FE3FF'; Spin (G 'UpdRot') $true
  Start-Process $con -ArgumentList "--headless $ps -NoProfile -ExecutionPolicy Bypass -File `"$Hd\updater.ps1`""; $script:updTimer.Start() }

# ---------- Шторка ----------
foreach ($k in $pages.Keys) { $r = New-Object Windows.Controls.RadioButton; $r.Style = $win.Resources['Nav']; $r.Tag = (Glyph $pages[$k][0])
  $r.Content = New-Object Windows.Controls.TextBlock -Property @{ Text = $pages[$k][1]; FontSize = 14.5; VerticalAlignment = 'Center' }
  $r.Name = "nav_$k"; $r.Add_Checked({ param($s, $e) ShowPage ($s.Name -replace '^nav_', '') }); [void](G 'Nav').Children.Add($r) }
$script:drawerOpen = $true
(G 'BtnMenu').Add_Click({ $script:drawerOpen = -not $script:drawerOpen; $to = $(if ($script:drawerOpen) { 214 } else { 72 })
  (G 'Drawer').BeginAnimation([Windows.FrameworkElement]::WidthProperty, (Ease (G 'Drawer').ActualWidth $to 320)) })

# ---------- Кнопки окна ----------
(G 'TitleBar').Add_MouseLeftButtonDown({ $win.DragMove() }); (G 'DrawerHead').Add_MouseLeftButtonDown({ $win.DragMove() })
(G 'BtnClose').Add_Click({ $win.Close() }); (G 'BtnMin').Add_Click({ $win.WindowState = 'Minimized' })
(G 'DBack').Add_Click({ (G 'Detail').Visibility = 'Collapsed' })
# Переключение сторожа: окно не ждёт процесс, итог — по таймеру, обновляется только этот сторож
(G 'DToggle').Add_Click({ $g = $script:cur; $on = $script:gs[$g.T] -ne 'on'
  try { $p = Start-Process $ps -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"$Hd\guard-toggle.ps1`" -Task `"$($g.T)`"" + $(if ($on) { ' -On' } else { '' })) -Verb RunAs -WindowStyle Hidden -PassThru -ErrorAction Stop }
  catch { Snack 'Отменено'; return }
  $script:tg = @{ G = $g; P = $p; T0 = Get-Date }; $script:tgTimer.Start(); (G 'DToggle').IsEnabled = $false })
$script:tgTimer = New-Object Windows.Threading.DispatcherTimer; $script:tgTimer.Interval = [TimeSpan]::FromMilliseconds(250)
# Если состояние процесса не читается — ждём не дольше 15 с
$script:tgTimer.Add_Tick({ $t = $script:tg; $done = ((Get-Date) - $t.T0).TotalSeconds -gt 15; try { $done = $t.P.HasExited } catch {}; if (-not $done) { return }
  $script:tgTimer.Stop(); $g = $t.G; GuardOne $g; Snack ("{0}: {1}" -f $g.N, $(if ($script:gs[$g.T] -eq 'on') { 'включён' } else { 'выключен' }))
  if ($script:page -eq 'guards') { foreach ($u in (G 'Body').Children) { foreach ($c in $u.Children) { if ([object]::ReferenceEquals($c.Tag, $g)) { $c.Content = GuardCard $g } } } }
  if ((G 'Detail').Visibility -eq 'Visible') { ShowDetail $script:cur } })
(G 'ActClose').Add_Click({ (G 'Act').Visibility = 'Collapsed'; PillSync
  if ($script:runTimer.IsEnabled) { Snack 'Работает в фоне — итог покажу здесь' } })
(G 'RunPill').Add_Click({ ShowAct })
# Закрытие во время работы — спросить (кроме перезапуска после обновления)
$win.Add_Closing({ param($s, $e) if ($script:quit -or -not ($script:run -and $script:runTimer.IsEnabled)) { return }
  # Открыт вопрос — отвечаем «Нет», иначе run.ps1 ждёт ответа до 30 минут
  $ask = (G 'AskBox').Visibility -eq 'Visible'
  $q = $(if ($ask) { "Сейчас «$($script:run.Title)» ждёт твой ответ. Если закрыть, я отвечу «Нет». Закрыть?" } else { "Сейчас идёт «$($script:run.Title)». Оно доработает само, но итог ты не увидишь. Закрыть?" })
  if ([Windows.MessageBox]::Show($win, $q, 'Помощник', 'YesNo', 'Question') -ne 'Yes') { $e.Cancel = $true } elseif ($ask) { Answer '' } })
if ($script:wake) { $wt = New-Object Windows.Threading.DispatcherTimer; $wt.Interval = [TimeSpan]::FromMilliseconds(300)
  $wt.Add_Tick({ if ($script:wake.WaitOne(0)) { if ($win.WindowState -eq 'Minimized') { $win.WindowState = 'Normal' }; [void]$win.Activate(); $win.Topmost = $true; $win.Topmost = $false } }); $wt.Start() }
(G 'AskYes').Add_Click({ Answer 'д' }); (G 'AskNo').Add_Click({ Answer '' }); (G 'AskOk').Add_Click({ Answer (G 'AskIn').Text })
(G 'AskIn').Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { Answer (G 'AskIn').Text } })
(G 'UpdBtn').Add_Click({ $script:quit = $true; MtxFree; Start-Process $con -ArgumentList "--headless $ps -NoProfile -STA -ExecutionPolicy Bypass -File `"$Hd\helper-app.ps1`""; $win.Close() })
(G 'Ver').Text = 'Версия ' + "$(Get-Content "$Hd\version.txt" -TotalCount 1 -Encoding UTF8)".Trim()

$win.Add_SourceInitialized({ $h = (New-Object Windows.Interop.WindowInteropHelper($win)).Handle; $v = 2; [void][PCT.Sys]::DwmSetWindowAttribute($h, 33, [ref]$v, 4); $d = 1; [void][PCT.Sys]::DwmSetWindowAttribute($h, 20, [ref]$d, 4) })
[void](Cpu); $script:page = 'home'; (G 'Nav').Children[0].IsChecked = $true; Tick
$timer = New-Object Windows.Threading.DispatcherTimer; $timer.Interval = [TimeSpan]::FromSeconds(2); $timer.Add_Tick({ Tick }); $timer.Start()
$win.Add_Loaded({ if (-not $env:PCT_RENDER) { StartUpdate } })

if ($env:PCT_RENDER) { $win.Show(); $i = 0
  function Snap($name) { $win.Dispatcher.Invoke([Action] {}, 'Render'); Start-Sleep -Milliseconds 400; $win.Dispatcher.Invoke([Action] {}, 'Render'); $win.UpdateLayout()
    foreach ($el in @((G 'Page'), (G 'Act'), (G 'Detail'))) { $el.BeginAnimation([Windows.UIElement]::OpacityProperty, $null); $el.Opacity = 1 }
    (G 'PageShift').BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $null); (G 'ActShift').BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $null); (G 'DetailShift').BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $null)
    $root = G 'Root'; $rt = New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$root.ActualWidth, [int]$root.ActualHeight, 96, 96, 'Pbgra32'); $rt.Render($root)
    $en = New-Object Windows.Media.Imaging.PngBitmapEncoder; $en.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rt)); $fs = [IO.File]::Create("$env:PCT_RENDER\$name.png"); $en.Save($fs); $fs.Close() }
  foreach ($k in @($pages.Keys)) { (G 'Nav').Children[$i].IsChecked = $true; Snap "page-$k"; $i++ }
  (G 'Nav').Children[4].IsChecked = $true; ShowDetail $guards[0]; Snap 'detail'
  (G 'Detail').Visibility = 'Collapsed'; $script:run = @{ Bad = 0; Ok = 0; Title = 'Проверить ноутбук' }; (G 'ActTitle').Text = 'Проверить ноутбук'; (G 'ActSub').Text = 'Работаю… 7 с'; (G 'Act').Visibility = 'Visible'
  foreach ($l in @(@('Cyan', '— Система'), @('Green', '  [OK] Windows                  11 Home 25H2'), @('Green', '  [OK] Память                   свободно 2,4 ГБ из 8'), @('Yellow', '  [..] Батарея                  891 цикл'), @('Red', '  [!!] Резервная копия           ни разу не делалась'), @('Yellow', '       Что сделать: вставь флешку и нажми «Резервная копия».'))) { AddLine $l[0] $l[1] }
  Ask ''; Snap 'activity'
  (G 'AskBox').Visibility = 'Collapsed'; (G 'Act').Visibility = 'Collapsed'; PillSync $true; Snap 'running-pill'
  (G 'Act').Visibility = 'Visible'; RunAborted; Snap 'aborted'; (G 'SnackTxt').Text = 'Нужен твой ответ'
  (G 'Act').Visibility = 'Collapsed'; $script:run.Res = 'ok'; $script:run.Seen = $false; PillSync; Snap 'done-pill'; $script:run.Seen = $true; PillSync
  $script:drawerOpen = $false; (G 'Drawer').Width = 72; (G 'Act').Visibility = 'Collapsed'; (G 'Nav').Children[0].IsChecked = $true; Snap 'drawer-closed'
  $win.Close(); return }
[void]$win.ShowDialog()
} catch {
  New-Item -ItemType Directory -Force 'C:\PC-Tweaks-Laptop\reports' | Out-Null; "$(Get-Date -f s) $($_.Exception.Message)" | Add-Content 'C:\PC-Tweaks-Laptop\reports\helper-app-error.txt'
  if ($env:PCT_RENDER) { throw }
  MtxFree; & "$Hd\helper-menu.ps1" }
