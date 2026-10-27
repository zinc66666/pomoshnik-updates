# Помощник (WPF): все инструменты ноутбука в одной программе, по категориям. Живые индикаторы, анимированные карточки.
# При ошибке загрузки окна открывается простое меню helper-menu.ps1.
$ErrorActionPreference = 'SilentlyContinue'
$Hd = 'C:\PC-Tweaks-Laptop\helpers'; $Gd = 'C:\PC-Tweaks-Laptop\guard'; $ps = "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
$Tools = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Мои инструменты'
try {
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -Namespace PCT -Name Sys -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
[StructLayout(LayoutKind.Sequential)] public struct MEM { public uint len; public uint load; public ulong tot; public ulong av; public ulong tp; public ulong ap; public ulong tv; public ulong avv; public ulong ext; }
[DllImport("kernel32.dll")] public static extern bool GlobalMemoryStatusEx(ref MEM m);
public static uint MemLoad() { MEM m = new MEM(); m.len = (uint)System.Runtime.InteropServices.Marshal.SizeOf(typeof(MEM)); GlobalMemoryStatusEx(ref m); return m.load; }
'@

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Помощник" Width="900" SizeToContent="Height" WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" FontFamily="Segoe UI Variable Text, Segoe UI" UseLayoutRounding="True">
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
      <Setter Property="Foreground" Value="White"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Margin" Value="5"/><Setter Property="Height" Value="68"/>
      <Setter Property="RenderTransformOrigin" Value="0.5,0.5"/>
      <Setter Property="RenderTransform"><Setter.Value><TransformGroup><ScaleTransform/><TranslateTransform/></TransformGroup></Setter.Value></Setter>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="bd" CornerRadius="16" Background="#1C2244" BorderBrush="#2C3463" BorderThickness="1" Padding="14,10">
          <Border.Effect><DropShadowEffect x:Name="sh" BlurRadius="0" ShadowDepth="0" Color="#7C5CFF" Opacity="0.55"/></Border.Effect>
          <ContentPresenter VerticalAlignment="Center"/>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="bd" Property="Background" Value="#252C5A"/><Setter TargetName="bd" Property="BorderBrush" Value="#7C5CFF"/>
            <Trigger.EnterActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="sh" Storyboard.TargetProperty="BlurRadius" To="22" Duration="0:0:0.2"/></Storyboard></BeginStoryboard></Trigger.EnterActions>
            <Trigger.ExitActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="sh" Storyboard.TargetProperty="BlurRadius" To="0" Duration="0:0:0.25"/></Storyboard></BeginStoryboard></Trigger.ExitActions>
          </Trigger>
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
      <Setter Property="Height" Value="80"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="bd" CornerRadius="20" Background="{StaticResource Accent}" Padding="20,12">
          <Border.Effect><DropShadowEffect x:Name="sh" BlurRadius="14" ShadowDepth="0" Color="#7C5CFF" Opacity="0.6"/></Border.Effect>
          <ContentPresenter VerticalAlignment="Center"/>
        </Border>
        <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True">
          <Trigger.EnterActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="sh" Storyboard.TargetProperty="BlurRadius" To="36" Duration="0:0:0.25"/></Storyboard></BeginStoryboard></Trigger.EnterActions>
          <Trigger.ExitActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="sh" Storyboard.TargetProperty="BlurRadius" To="14" Duration="0:0:0.3"/></Storyboard></BeginStoryboard></Trigger.ExitActions>
        </Trigger></ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="Pill" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#C9D0F0"/><Setter Property="Margin" Value="0,0,8,0"/><Setter Property="Cursor" Value="Hand"/><Setter Property="FontSize" Value="14"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RadioButton">
        <Border x:Name="b" CornerRadius="18" Padding="16,8" Background="#141935" BorderBrush="#2C3463" BorderThickness="1"><ContentPresenter/></Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#7C5CFF"/></Trigger>
          <Trigger Property="IsChecked" Value="True"><Setter TargetName="b" Property="Background" Value="{StaticResource Accent}"/><Setter TargetName="b" Property="BorderBrush" Value="Transparent"/><Setter Property="Foreground" Value="White"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="Chip" TargetType="Border"><Setter Property="CornerRadius" Value="14"/><Setter Property="Background" Value="#161B38"/><Setter Property="BorderBrush" Value="#262D58"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="12,7"/><Setter Property="Margin" Value="0,0,8,8"/></Style>
    <Style x:Key="Dot" TargetType="Ellipse"><Setter Property="Width" Value="9"/><Setter Property="Height" Value="9"/><Setter Property="Margin" Value="0,0,8,0"/><Setter Property="VerticalAlignment" Value="Center"/>
      <Style.Triggers><EventTrigger RoutedEvent="Loaded"><BeginStoryboard><Storyboard RepeatBehavior="Forever" AutoReverse="True"><DoubleAnimation Storyboard.TargetProperty="Opacity" From="1" To="0.35" Duration="0:0:0.9"/></Storyboard></BeginStoryboard></EventTrigger></Style.Triggers></Style>
    <Style x:Key="Meter" TargetType="ProgressBar"><Setter Property="Height" Value="6"/><Setter Property="Width" Value="90"/><Setter Property="Maximum" Value="100"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ProgressBar">
        <Grid><Border CornerRadius="3" Background="#2A315E"/><Border x:Name="PART_Track"/><Border x:Name="PART_Indicator" CornerRadius="3" HorizontalAlignment="Left" Background="{StaticResource Accent}"/></Grid>
      </ControlTemplate></Setter.Value></Setter></Style>
  </Window.Resources>

  <Border x:Name="Root" CornerRadius="22" Margin="14" BorderBrush="#33FFFFFF" BorderThickness="1">
    <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#0E1126" Offset="0"/><GradientStop Color="#151A38" Offset="0.55"/><GradientStop Color="#1E1638" Offset="1"/></LinearGradientBrush></Border.Background>
    <Border.Effect><DropShadowEffect BlurRadius="24" ShadowDepth="0" Opacity="0.55" Color="#000000"/></Border.Effect>
    <Grid Margin="22,10,22,18">
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <Grid x:Name="TitleBar" Grid.Row="0" Background="Transparent" Height="36">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <Border Width="22" Height="22" CornerRadius="7" Background="{StaticResource Accent}"><TextBlock Text="&#xE9D9;" FontFamily="{StaticResource Ico}" Foreground="White" FontSize="12" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
          <TextBlock Text="Помощник" Foreground="#C9D0F0" FontSize="13" Margin="10,0,0,0" VerticalAlignment="Center"/><TextBlock x:Name="Ver" Foreground="#6B76A6" FontSize="12" Margin="8,0,0,0" VerticalAlignment="Center"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,10,0">
        <Border CornerRadius="10" Background="#141935" Padding="10,4" Margin="0,0,6,0"><StackPanel Orientation="Horizontal"><TextBlock Text="Процессор" Foreground="#98A2C8" FontSize="12.5" Margin="0,0,8,0" VerticalAlignment="Center"/><ProgressBar x:Name="BarC" Style="{StaticResource Meter}" VerticalAlignment="Center"/><TextBlock x:Name="TxtC" Foreground="#DDE3FF" FontSize="12.5" Width="38" TextAlignment="Right" VerticalAlignment="Center"/></StackPanel></Border>
        <Border CornerRadius="10" Background="#141935" Padding="10,4" Margin="0,0,6,0"><StackPanel Orientation="Horizontal"><TextBlock Text="Память" Foreground="#98A2C8" FontSize="12.5" Margin="0,0,8,0" VerticalAlignment="Center"/><ProgressBar x:Name="BarM" Style="{StaticResource Meter}" VerticalAlignment="Center"/><TextBlock x:Name="TxtM" Foreground="#DDE3FF" FontSize="12.5" Width="38" TextAlignment="Right" VerticalAlignment="Center"/></StackPanel></Border>
      </StackPanel>
          <Button x:Name="BtnMin" Style="{StaticResource Chrome}"><TextBlock Text="&#xE921;" FontFamily="{StaticResource Ico}" FontSize="11"/></Button>
          <Button x:Name="BtnClose" Style="{StaticResource Chrome}"><TextBlock Text="&#xE8BB;" FontFamily="{StaticResource Ico}" FontSize="11"/></Button>
        </StackPanel>
      </Grid>
      <StackPanel Grid.Row="1" Margin="2,2,0,10">
        <TextBlock x:Name="Hello" Foreground="White" FontSize="23" FontWeight="SemiBold"/>
        <TextBlock Text="Всё для ноутбука в одном месте. Нажми нужную карточку — остальное я сделаю сам." Foreground="#98A2C8" FontSize="13.5" Margin="0,4,0,0"/>
      </StackPanel>
      <WrapPanel Grid.Row="2" Margin="0,0,0,6">
        <Border Style="{StaticResource Chip}"><StackPanel Orientation="Horizontal"><Ellipse x:Name="DotZ" Style="{StaticResource Dot}"/><TextBlock x:Name="TxtZ" Foreground="#DDE3FF" FontSize="13"/></StackPanel></Border>
        <Border Style="{StaticResource Chip}"><StackPanel Orientation="Horizontal"><Ellipse x:Name="DotH" Style="{StaticResource Dot}"/><TextBlock x:Name="TxtH" Foreground="#DDE3FF" FontSize="13"/></StackPanel></Border>
        <Border Style="{StaticResource Chip}"><StackPanel Orientation="Horizontal"><Ellipse x:Name="DotP" Style="{StaticResource Dot}"/><TextBlock x:Name="TxtP" Foreground="#DDE3FF" FontSize="13"/></StackPanel></Border>
</WrapPanel>
      <Button x:Name="BtnHero" Grid.Row="3" Style="{StaticResource Hero}" Margin="5,2,5,12">
        <StackPanel Orientation="Horizontal">
          <Border Width="46" Height="46" CornerRadius="15" Background="#33FFFFFF"><TextBlock Text="&#xE9D9;" FontFamily="{StaticResource Ico}" FontSize="22" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
          <StackPanel Margin="16,0,0,0" VerticalAlignment="Center">
            <TextBlock Text="Проверить ноутбук" Foreground="White" FontSize="19" FontWeight="SemiBold"/>
            <TextBlock Text="Найдёт, что не так, и скажет, что делать. Начни отсюда." Foreground="#E8ECFF" FontSize="13.5" Margin="0,2,0,0"/>
          </StackPanel>
        </StackPanel>
      </Button>
      <StackPanel x:Name="Tabs" Grid.Row="4" Orientation="Horizontal" Margin="6,0,0,10"/>
      <UniformGrid x:Name="Cards" Grid.Row="5" Columns="2" Rows="4" VerticalAlignment="Top" Height="312">
        <UniformGrid.RenderTransform><TranslateTransform x:Name="CardsShift"/></UniformGrid.RenderTransform>
      </UniformGrid>
      <Grid Grid.Row="6" Margin="6,6,6,0" Height="30">
        <TextBlock x:Name="Hint" Text="Windows спросит разрешение — нажми «Да». Не получается — «Помощь» → «Позвать помощь»." Foreground="#7F89B3" FontSize="12.5" VerticalAlignment="Center"/>
        <Border x:Name="UpdBox" CornerRadius="12" Background="#1B2350" BorderBrush="#3A4380" BorderThickness="1" Padding="12,3" HorizontalAlignment="Left" Visibility="Collapsed">
          <StackPanel Orientation="Horizontal">
            <TextBlock x:Name="UpdIco" Text="&#xE895;" FontFamily="{StaticResource Ico}" Foreground="#8FE3FF" FontSize="13" VerticalAlignment="Center" Margin="0,0,8,0" RenderTransformOrigin="0.5,0.5"><TextBlock.RenderTransform><RotateTransform x:Name="UpdRot"/></TextBlock.RenderTransform></TextBlock>
            <TextBlock x:Name="UpdTxt" Foreground="White" FontSize="12.5" VerticalAlignment="Center" MaxWidth="360" TextTrimming="CharacterEllipsis"/>
            <ProgressBar x:Name="UpdBar" Style="{StaticResource Meter}" Width="120" Margin="10,0,0,0" VerticalAlignment="Center"/>
            <Button x:Name="UpdBtn" Style="{StaticResource Chrome}" Width="Auto" Height="24" Margin="10,0,0,0" Visibility="Collapsed"><TextBlock Text="Перезапустить" Foreground="#8FE3FF" FontSize="12.5" Margin="8,0"/></Button>
          </StackPanel>
        </Border>
        <Border x:Name="Snack" CornerRadius="12" Background="#2B3470" Padding="14,6" HorizontalAlignment="Right" Opacity="0">
          <Border.RenderTransform><TranslateTransform x:Name="SnackShift" Y="12"/></Border.RenderTransform>
          <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE768;" FontFamily="{StaticResource Ico}" Foreground="#8FE3FF" FontSize="12" VerticalAlignment="Center" Margin="0,0,8,0"/><TextBlock x:Name="SnackTxt" Foreground="White" FontSize="13"/></StackPanel>
        </Border>
      </Grid>
      <Border x:Name="Detail" Grid.Row="0" Grid.RowSpan="7" Visibility="Collapsed" CornerRadius="18" Background="#131837" BorderBrush="#3A4380" BorderThickness="1" Padding="28,22" Margin="0,40,0,0">
        <Border.RenderTransform><TranslateTransform x:Name="DetailShift"/></Border.RenderTransform>
        <StackPanel>
          <StackPanel Orientation="Horizontal">
            <Border Width="50" Height="50" CornerRadius="16" Background="{StaticResource Accent}"><TextBlock x:Name="DIcon" FontFamily="{StaticResource Ico}" FontSize="22" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
            <StackPanel Margin="16,0,0,0" VerticalAlignment="Center"><TextBlock x:Name="DTitle" Foreground="White" FontSize="21" FontWeight="SemiBold"/><TextBlock x:Name="DState" FontSize="13.5" Margin="0,3,0,0"/></StackPanel>
          </StackPanel>
          <Border x:Name="DRecBox" CornerRadius="12" Padding="14,10" Margin="0,18,0,0"><TextBlock x:Name="DRec" Foreground="White" FontSize="14.5" FontWeight="SemiBold" TextWrapping="Wrap"/></Border>
          <TextBlock Text="ЧТО ДЕЛАЕТ" Foreground="#8FA3FF" FontSize="12" FontWeight="SemiBold" Margin="0,18,0,4"/>
          <TextBlock x:Name="DWhat" Foreground="#DDE3FF" FontSize="14" TextWrapping="Wrap"/>
          <TextBlock Text="ЕСЛИ ВЫКЛЮЧИТЬ" Foreground="#FF9DB0" FontSize="12" FontWeight="SemiBold" Margin="0,14,0,4"/>
          <TextBlock x:Name="DRisk" Foreground="#DDE3FF" FontSize="14" TextWrapping="Wrap"/>
          <TextBlock Text="НАГРУЗКА НА НОУТБУК" Foreground="#7FE0C0" FontSize="12" FontWeight="SemiBold" Margin="0,14,0,4"/>
          <TextBlock x:Name="DLoad" Foreground="#DDE3FF" FontSize="14" TextWrapping="Wrap"/>
          <StackPanel Orientation="Horizontal" Margin="0,22,0,0">
            <Button x:Name="DToggle" Style="{StaticResource Card}" Width="250" Height="50"><TextBlock x:Name="DToggleTxt" Foreground="White" FontSize="15" FontWeight="SemiBold" HorizontalAlignment="Center"/></Button>
            <Button x:Name="DBack" Style="{StaticResource Card}" Width="150" Height="50"><TextBlock Text="Назад" Foreground="White" FontSize="15" HorizontalAlignment="Center"/></Button>
          </StackPanel>
        </StackPanel>
      </Border>
    </Grid>
  </Border>
</Window>
'@
$win = [Windows.Markup.XamlReader]::Parse($xaml)
function G($n) { $win.FindName($n) }
$tabs = [ordered]@{
  'Интернет и блокировки' = @(
    @('&#xE714;', 'Не работает YouTube или Discord', 'Подберу новый способ обхода сам (до 10 мин)', "$Hd\zapret-repick.ps1", 'admin'),
    @('&#xE774;', 'Сайт не открывается', 'Проверю любой сайт и открою его через VPN', "$Hd\site-fix.ps1", 'user'),
    @('&#xE72E;', 'Заблокированные сайты', '', "$Hd\smart-proxy.ps1", 'toggle'),
    @('&#xE724;', 'Не работает Telegram', 'Переподключу Happ — прокси для Telegram', "$Hd\happ-connect.ps1", 'gui'),
    @('&#xE909;', 'Какие сайты открываются', 'YouTube, Discord, Telegram, Instagram и другие', "$Hd\check-sites.ps1", 'user'),
    @('&#xE701;', 'Интернет совсем не работает', 'Сброшу сеть и перезапущу Wi-Fi', "$Gd\fix-internet.ps1", 'admin'))
  'Скорость и порядок' = @(
    @('&#xEC4A;', 'Что тормозит сейчас', 'Покажу, что грузит ноутбук, и что с этим делать', "$Hd\perf-now.ps1", 'user'),
    @('&#xE74D;', 'Почистить мусор', 'Временные файлы; Корзину — только по слову', "$Hd\clean-junk.ps1", 'admin'),
    @('&#xE7E8;', 'Что запускается с Windows', 'Список и отключение лишнего', "$Hd\startup-all.ps1", 'admin'),
    @('&#xEDA2;', 'Что занимает место', 'Самые большие папки, ничего не удаляю', "$Hd\disk-space.ps1", 'user'),
    @('&#xE896;', 'Разобрать Загрузки', 'Картинки, видео, документы — по папкам', "$Hd\sort-downloads.ps1", 'user'),
    @('&#xE7A7;', 'Вернуть Загрузки как было', 'Отменю разбор Загрузок', "$Hd\undo-sort-downloads.ps1", 'user'),
    @('&#xE895;', 'Обновить программы', 'Найду и поставлю новые версии', "$Hd\update-apps.ps1", 'admin'),
    @('&#xE90F;', 'Не открываются файлы или меню', 'Найду и исправлю причину', "$Hd\file-repair.ps1", 'admin'))
  'Защита и копии' = @(
    @('&#xEA18;', 'Проверка безопасности', 'Нет ли вирусов в автозапуске и Загрузках', "$Gd\check-now.ps1", 'user'),
    @('&#xE88E;', 'Резервная копия', 'Документы и фото на флешку', "$Hd\backup.ps1", 'admin'),
    @('&#xE714;', 'Кто включал камеру и микрофон', 'Какие программы и когда снимали или слушали', "$Hd\privacy-check.ps1", 'user'),
    @('&#xE83F;', 'Отчёт о батарее', 'Износ и состояние батареи', "$Gd\battery-report.ps1", 'user'),
    @('&#xE721;', 'Найти файл', 'Мгновенный поиск любого файла (Everything)', 'C:\Program Files\Everything\Everything.exe', 'exe'))
  'Сторожа' = @()
  'Помощь' = @(
    @('&#xE77B;', 'Позвать помощь', 'Покажу номер AnyDesk и скопирую его', "$Hd\call-help.ps1", 'gui'),
    @('&#xE8A5;', 'Прочитать подсказки', 'Что делает каждая кнопка', (Join-Path $Tools 'ПРОЧИТАЙ МЕНЯ.txt'), 'note'),
    @('&#xE838;', 'Все инструменты', 'Папка со всеми ярлыками', $Tools, 'folder')) }

# Сторожа: фоновые задачи ноутбука. Rec: 2 — держать обязательно, 1 — лучше держать, 0 — можно выключить.
$guards = @(
  @{ T = 'PCT-Guard-Autoruns'; I = '&#xEA18;'; N = 'Сторож автозапуска'; S = 'Раз в день ищет новое в автозагрузке'; Rec = 2
     W = 'Раз в день сравнивает автозагрузку со снимком «как было». Если появилась новая программа — присылает уведомление. Так ловятся вирусы, майнеры и программы-«прилипалы», которые прописываются сами.'
     R = 'Новый вирус в автозапуске останется незамеченным. Антивируса на этом ноутбуке нет — этот сторож один из главных способов защиты.'; L = 'Несколько секунд раз в день — незаметно.' },
  @{ T = 'PCT-Guard-Downloads'; I = '&#xE896;'; N = 'Сторож Загрузок'; S = 'Предупреждает об опасных скачанных файлах'; Rec = 2
     W = 'Каждые 15 минут смотрит новые файлы в «Загрузках». Если скачан файл без цифровой подписи или скрипт — предупреждает, прежде чем ты его откроешь.'
     R = 'Можно случайно открыть вредный файл без предупреждения. Именно так в прошлый раз попали два вируса.'; L = 'Доли секунды раз в 15 минут — незаметно.' },
  @{ T = 'PCT-Sites-Watch'; I = '&#xE714;'; N = 'Сторож YouTube и Discord'; S = 'Сам чинит обход блокировок'; Rec = 2
     W = 'При входе и каждые 3 часа проверяет YouTube и Discord. Если провайдер сменил блокировку и они перестали открываться — сам подбирает новый способ обхода и пишет уведомление. Заодно возвращает обход заблокированных сайтов, если его сбросили.'
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
  @{ T = 'PCT-Health-Weekly'; I = '&#xE9D9;'; N = 'Проверка раз в неделю'; S = 'По воскресеньям проверяет ноутбук'; Rec = 1
     W = 'По воскресеньям в 18:00 тихо проверяет ноутбук: диск, батарею, обновления, обход блокировок, резервную копию. Уведомление приходит только если что-то не так.'
     R = 'Проблемы (заканчивается место, устарела копия, сломался обход) будут копиться незаметно, пока не нажмёшь «Проверить ноутбук».'; L = 'Около минуты раз в неделю.' },
  @{ T = 'PCT-Clean-Temp'; I = '&#xE74D;'; N = 'Уборка временных файлов'; S = 'По воскресеньям удаляет старый мусор'; Rec = 0
     W = 'По воскресеньям удаляет из папок Temp файлы старше 7 дней — то, что программы оставили и забыли. Твои файлы не трогает.'
     R = 'Ничего не сломается. Мусор будет копиться (за несколько месяцев — гигабайты); его можно убрать кнопкой «Почистить мусор».'; L = 'Около минуты раз в неделю.' })
$script:gs = @{}
function GState($t) { $x = Get-ScheduledTask -TaskName $t; if (-not $x) { '?' } elseif ([string]$x.State -eq 'Disabled') { 'off' } else { 'on' } }
$recTxt = @{ 2 = 'Рекомендую держать включённым'; 1 = 'Лучше держать включённым'; 0 = 'Можно выключить — на защиту не влияет' }
$recCol = @{ 2 = '#1F7A55'; 1 = '#2B5DA8'; 0 = '#8A6A1E' }

$bc = New-Object Windows.Media.BrushConverter
function Br($c) { $bc.ConvertFromString($c) }
function PacOn { Test-Path "$Hd\smart-proxy-on.txt" }
function Glyph($code) { [string][char][Convert]::ToInt32(($code -replace '&#x|;', ''), 16) }
function Snack($t) { (G 'SnackTxt').Text = $t; $sn = G 'Snack'
  $a1 = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames; foreach ($kf in @(@(0, 0), @(250, 1), @(2600, 1), @(3000, 0))) { [void]$a1.KeyFrames.Add((New-Object Windows.Media.Animation.LinearDoubleKeyFrame($kf[1], [TimeSpan]::FromMilliseconds($kf[0])))) }
  $a2 = New-Object Windows.Media.Animation.DoubleAnimation(12, 0, [TimeSpan]::FromMilliseconds(300)); $a2.EasingFunction = New-Object Windows.Media.Animation.CubicEase
  $sn.BeginAnimation([Windows.UIElement]::OpacityProperty, $a1); (G 'SnackShift').BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $a2) }
function CardContent($it) {
  $g = New-Object Windows.Controls.Grid; [void]$g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{ Width = 'Auto' })); [void]$g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
  $ib = New-Object Windows.Controls.Border -Property @{ Width = 44; Height = 44; CornerRadius = 14; Background = (Br '#2A2F66') }
  if ($it[4] -eq 'toggle') { $ib.Background = $(if (PacOn) { $win.Resources['Accent'] } else { Br '#3A2F4F' }) }
  $ib.Child = New-Object Windows.Controls.TextBlock -Property @{ Text = (Glyph $it[0]); FontFamily = $win.Resources['Ico']; FontSize = 19; Foreground = (Br '#BFD4FF'); HorizontalAlignment = 'Center'; VerticalAlignment = 'Center' }
  $sp = New-Object Windows.Controls.StackPanel -Property @{ Margin = '14,0,0,0'; VerticalAlignment = 'Center' }; [Windows.Controls.Grid]::SetColumn($sp, 1)
  $title = $it[1]; $sub = $it[2]
  if ($it[4] -eq 'toggle') { if (PacOn) { $title = 'Заблокированные сайты: ВКЛ'; $sub = 'Instagram, X, ChatGPT… открываются сами через Happ' } else { $title = 'Заблокированные сайты: ВЫКЛ'; $sub = 'Нажми, чтобы Instagram, X… открывались сами' } }
  [void]$sp.Children.Add((New-Object Windows.Controls.TextBlock -Property @{ Text = $title; FontSize = 15.5; FontWeight = 'SemiBold'; Foreground = (Br '#FFFFFF'); TextTrimming = 'CharacterEllipsis' }))
  [void]$sp.Children.Add((New-Object Windows.Controls.TextBlock -Property @{ Text = $sub; FontSize = 12.5; Foreground = (Br '#98A2C8'); Margin = '0,3,0,0'; TextTrimming = 'CharacterEllipsis' }))
  [void]$g.Children.Add($ib); [void]$g.Children.Add($sp); $g }
function Run($it, $btn) {
  $a = "-NoProfile -ExecutionPolicy Bypass -File `"$($it[3])`""
  try { switch ($it[4]) {
      'admin'  { Start-Process $ps -ArgumentList $a -Verb RunAs -ErrorAction Stop; Snack "Запускаю: $($it[1])" }
      'user'   { Start-Process $ps -ArgumentList $a; Snack "Запускаю: $($it[1])" }
      'gui'    { Start-Process "$env:windir\System32\conhost.exe" -ArgumentList "--headless $ps $a"; Snack "Запускаю: $($it[1])" }
      'exe'    { Start-Process $it[3]; Snack "Открываю: $($it[1])" }
      'note'   { Start-Process notepad.exe -ArgumentList "`"$($it[3])`"" }
      'folder' { Start-Process explorer.exe -ArgumentList "`"$($it[3])`"" }
      'toggle' { if (PacOn) { & $it[3] -Off; Snack 'Заблокированные сайты: выключено' } else { & $it[3] -On; Snack 'Заблокированные сайты: включено — обнови страницу' }; $btn.Content = CardContent $it; Tick } } }
  catch { Snack 'Отменено' } }
function GuardCard($g) { $st = $script:gs[$g.T]
  $it = @($g.I, $g.N, ("{0} · {1}" -f $(if ($st -eq 'on') { 'ВКЛ' } elseif ($st -eq 'off') { 'ВЫКЛ' } else { 'нет задачи' }), $g.S), '', 'guard')
  $cc = CardContent $it; $cc.Children[0].Background = $(if ($st -eq 'on') { $win.Resources['Accent'] } else { Br '#3A2F4F' }); $cc }
function ShowDetail($g) { $st = $script:gs[$g.T]; $script:cur = $g
  (G 'DIcon').Text = Glyph $g.I; (G 'DTitle').Text = $g.N
  (G 'DState').Text = $(if ($st -eq 'on') { '● Сейчас включён' } elseif ($st -eq 'off') { '● Сейчас выключен' } else { '● Задача не найдена' }); (G 'DState').Foreground = Br $(if ($st -eq 'on') { '#3DDC97' } else { '#FF5C7A' })
  (G 'DRec').Text = $recTxt[$g.Rec]; (G 'DRecBox').Background = Br $recCol[$g.Rec]
  (G 'DWhat').Text = $g.W; (G 'DRisk').Text = $g.R; (G 'DLoad').Text = $g.L
  (G 'DToggleTxt').Text = $(if ($st -eq 'on') { 'Выключить' } else { 'Включить' }); (G 'DToggle').IsEnabled = $st -ne '?'
  $d = G 'Detail'; $d.Visibility = 'Visible'; $d.BeginAnimation([Windows.UIElement]::OpacityProperty, (New-Object Windows.Media.Animation.DoubleAnimation(0, 1, [TimeSpan]::FromMilliseconds(220))))
  $sa = New-Object Windows.Media.Animation.DoubleAnimation(30, 0, [TimeSpan]::FromMilliseconds(300)); $sa.EasingFunction = New-Object Windows.Media.Animation.CubicEase; (G 'DetailShift').BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $sa) }
function ShowTab($name) { $c = G 'Cards'; $c.Children.Clear()
  if ($name -eq 'Сторожа') { foreach ($g in $guards) { $script:gs[$g.T] = GState $g.T }
    foreach ($g in $guards) { $b = New-Object Windows.Controls.Button; $b.Style = $win.Resources['Card']; $b.Content = GuardCard $g; $b.Tag = $g
      $b.Add_Click({ param($s, $e) ShowDetail $s.Tag }); [void]$c.Children.Add($b) } }
  foreach ($it in $tabs[$name]) { $b = New-Object Windows.Controls.Button; $b.Style = $win.Resources['Card']; $b.Content = CardContent $it; $b.Tag = $it
    $b.Add_Click({ param($s, $e) Run $s.Tag $s }); [void]$c.Children.Add($b) }
  $c.Opacity = 0; $c.BeginAnimation([Windows.UIElement]::OpacityProperty, (New-Object Windows.Media.Animation.DoubleAnimation(0, 1, [TimeSpan]::FromMilliseconds(260))))
  $sa = New-Object Windows.Media.Animation.DoubleAnimation(16, 0, [TimeSpan]::FromMilliseconds(320)); $sa.EasingFunction = New-Object Windows.Media.Animation.CubicEase; (G 'CardsShift').BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $sa) }
foreach ($name in $tabs.Keys) { $r = New-Object Windows.Controls.RadioButton; $r.Style = $win.Resources['Pill']; $r.Content = $name; $r.GroupName = 'tabs'; $r.Tag = $name
  $r.Add_Checked({ param($s, $e) ShowTab $s.Tag }); [void](G 'Tabs').Children.Add($r) }

$script:prev = $null
function Cpu { $i = 0L; $k = 0L; $u = 0L; [void][PCT.Sys]::GetSystemTimes([ref]$i, [ref]$k, [ref]$u); $now = @($i, ($k + $u))
  $v = 0; if ($script:prev) { $di = $now[0] - $script:prev[0]; $dt = $now[1] - $script:prev[1]; if ($dt -gt 0) { $v = [math]::Round(100 * (1 - $di / $dt)) } }; $script:prev = $now; [math]::Max(0, [math]::Min(100, $v)) }
function Anim($bar, $v) { $bar.BeginAnimation([Windows.Controls.Primitives.RangeBase]::ValueProperty, (New-Object Windows.Media.Animation.DoubleAnimation($v, [TimeSpan]::FromMilliseconds(700)))) }
function Chip($dot, $txt, $ok, $tOk, $tBad) { (G $dot).Fill = Br $(if ($ok) { '#3DDC97' } else { '#FF5C7A' }); (G $txt).Text = $(if ($ok) { $tOk } else { $tBad }) }
function Tick {
  Chip 'DotZ' 'TxtZ' ([bool](Get-Process winws)) 'YouTube и Discord: работают' 'YouTube и Discord: обход выключен'
  $hp = [bool]([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() | Where-Object Port -eq 10808)
  Chip 'DotH' 'TxtH' $hp 'Happ подключён' 'Happ не подключён'
  Chip 'DotP' 'TxtP' (PacOn) 'Заблокированные сайты открываются' 'Заблокированные сайты: выкл'
  $c = Cpu; $m = [PCT.Sys]::MemLoad(); Anim (G 'BarC') $c; Anim (G 'BarM') $m; (G 'TxtC').Text = "$c%"; (G 'TxtM').Text = "$m%" }

$h = (Get-Date).Hour; (G 'Hello').Text = $(if ($h -lt 5) { 'Доброй ночи!' } elseif ($h -lt 12) { 'Доброе утро!' } elseif ($h -lt 18) { 'Добрый день!' } else { 'Добрый вечер!' })
(G 'TitleBar').Add_MouseLeftButtonDown({ $win.DragMove() })
(G 'BtnClose').Add_Click({ $win.Close() }); (G 'BtnMin').Add_Click({ $win.WindowState = 'Minimized' })
$heroIt = @('', 'Проверить ноутбук', '', "$Hd\system-health.ps1", 'admin'); (G 'BtnHero').Add_Click({ Run $heroIt $null })
# --- Автообновление: запуск updater.ps1 в фоне и живой показ его хода из update-status.json
(G 'Ver').Text = 'v' + "$(Get-Content "$Hd\version.txt" -TotalCount 1)".Trim()
$script:updTimer = New-Object Windows.Threading.DispatcherTimer; $script:updTimer.Interval = [TimeSpan]::FromMilliseconds(250)
function UpdShow($on) { (G 'UpdBox').Visibility = $(if ($on) { 'Visible' } else { 'Collapsed' }); (G 'Hint').Visibility = $(if ($on) { 'Collapsed' } else { 'Visible' }) }
function UpdSpin($on) { if ($on) { $ra = New-Object Windows.Media.Animation.DoubleAnimation(0, 360, [TimeSpan]::FromSeconds(1.1)); $ra.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever; (G 'UpdRot').BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $ra) } else { (G 'UpdRot').BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $null) } }
function UpdLater($ms) { $h = New-Object Windows.Threading.DispatcherTimer; $h.Interval = [TimeSpan]::FromMilliseconds($ms); $h.Add_Tick({ param($s, $e) $s.Stop(); UpdShow $false }); $h.Start() }
$script:updTimer.Add_Tick({
  $j = $null; try { $j = [IO.File]::ReadAllText("$Hd\update-status.json") | ConvertFrom-Json } catch {}
  if (-not $j) { if (((Get-Date) - $script:updT0).TotalSeconds -gt 90) { $script:updTimer.Stop(); UpdSpin $false; UpdShow $false }; return }
  (G 'UpdTxt').Text = $j.msg
  switch ($j.state) {
    'checking'    { UpdShow $true; (G 'UpdBar').Visibility = 'Collapsed' }
    'downloading' { UpdShow $true; (G 'UpdBar').Visibility = 'Visible'; Anim (G 'UpdBar') ([double]$j.pct) }
    'installing'  { UpdShow $true; Anim (G 'UpdBar') 100 }
    'done'        { $script:updTimer.Stop(); UpdSpin $false; UpdShow $true; (G 'UpdIco').Text = [string][char]0xE73E; (G 'UpdIco').Foreground = Br '#3DDC97'; (G 'UpdBar').Visibility = 'Collapsed'
                    (G 'UpdTxt').Text = "Обновлено до $($j.ver)" + $(if ($j.notes) { " — $($j.notes)" }); (G 'UpdBtn').Visibility = 'Visible'; Snack "Помощник обновлён до $($j.ver)" }
    'uptodate'    { $script:updTimer.Stop(); UpdSpin $false; UpdShow $true; (G 'UpdIco').Text = [string][char]0xE73E; (G 'UpdIco').Foreground = Br '#3DDC97'; (G 'UpdBar').Visibility = 'Collapsed'; UpdLater 2500 }
    'error'       { $script:updTimer.Stop(); UpdSpin $false; UpdShow $true; (G 'UpdIco').Text = [string][char]0xE783; (G 'UpdIco').Foreground = Br '#FFB86B'; (G 'UpdBar').Visibility = 'Collapsed'; UpdLater 4000 } } })
function StartUpdate { if (-not (Test-Path "$Hd\updater.ps1")) { return }
  Remove-Item "$Hd\update-status.json" -Force; $script:updT0 = Get-Date; UpdSpin $true
  Start-Process "$env:windir\System32\conhost.exe" -ArgumentList "--headless $ps -NoProfile -ExecutionPolicy Bypass -File `"$Hd\updater.ps1`""; $script:updTimer.Start() }
(G 'UpdBtn').Add_Click({ Start-Process "$env:windir\System32\conhost.exe" -ArgumentList "--headless $ps -NoProfile -STA -ExecutionPolicy Bypass -File `"$Hd\helper-app.ps1`""; $win.Close() })
(G 'DBack').Add_Click({ (G 'Detail').Visibility = 'Collapsed' })
(G 'DToggle').Add_Click({ $g = $script:cur; $on = $script:gs[$g.T] -ne 'on'
  try { Start-Process $ps -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"$Hd\guard-toggle.ps1`" -Task `"$($g.T)`"" + $(if ($on) { ' -On' } else { '' })) -Verb RunAs -WindowStyle Hidden -Wait -ErrorAction Stop
    $script:gs[$g.T] = GState $g.T; Snack ("{0}: {1}" -f $g.N, $(if ($script:gs[$g.T] -eq 'on') { 'включён' } else { 'выключен' })) } catch { Snack 'Отменено' }
  ShowDetail $g; ShowTab 'Сторожа' })
[void](Cpu); Tick
$timer = New-Object Windows.Threading.DispatcherTimer; $timer.Interval = [TimeSpan]::FromSeconds(2); $timer.Add_Tick({ Tick }); $timer.Start()
(G 'Tabs').Children[0].IsChecked = $true
$win.Opacity = 0; $win.Add_Loaded({ if (-not $env:PCT_RENDER) { StartUpdate }; $win.BeginAnimation([Windows.Window]::OpacityProperty, (New-Object Windows.Media.Animation.DoubleAnimation(0, 1, [TimeSpan]::FromMilliseconds(350)))) })
if ($env:PCT_RENDER) { $win.Show(); foreach ($ti in 0..5) { if ($ti -eq 5) { (G 'Tabs').Children[3].IsChecked = $true; ShowDetail $guards[0]; (G 'Detail').BeginAnimation([Windows.UIElement]::OpacityProperty, $null); (G 'DetailShift').BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $null) } else { (G 'Tabs').Children[$ti].IsChecked = $true }; $win.Opacity = 1; (G 'Cards').BeginAnimation([Windows.UIElement]::OpacityProperty, $null); (G 'Cards').Opacity = 1; (G 'CardsShift').BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $null)
    $win.Dispatcher.Invoke([Action] {}, 'Render'); Start-Sleep -Milliseconds 300; $win.UpdateLayout(); $rt = New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$win.ActualWidth, [int]$win.ActualHeight, 96, 96, 'Pbgra32'); $rt.Render((G 'Root'))
    $en = New-Object Windows.Media.Imaging.PngBitmapEncoder; $en.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rt)); $fs = [IO.File]::Create("$env:PCT_RENDER\app$ti.png"); $en.Save($fs); $fs.Close() }; $win.Close(); return }
[void]$win.ShowDialog()
} catch {
  New-Item -ItemType Directory -Force 'C:\PC-Tweaks-Laptop\reports' | Out-Null; "$(Get-Date -f s) $($_.Exception.Message)" | Add-Content 'C:\PC-Tweaks-Laptop\reports\helper-app-error.txt'
  if ($env:PCT_RENDER) { throw }
  & "$Hd\helper-menu.ps1" }
