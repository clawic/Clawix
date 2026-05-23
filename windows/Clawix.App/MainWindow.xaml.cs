using Clawix.App.Services;
using Clawix.App.Views;
using Clawix.Core;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using WinRT.Interop;

namespace Clawix.App;

public sealed partial class MainWindow : Window
{
    private IntPtr _hwnd;
    private HotkeyHook? _hotkeyHook;
    private int? _quickAskHotkeyId;

    public MainWindow()
    {
        InitializeComponent();
        ApplyThemePreference();
        ApplyBackdropPreference();
        ExtendsContentIntoTitleBar = true;
        LoginGate.SignInRequested += StartBackendLogin;
        LoginGate.ContinueRequested += ShowShell;
        Activated += OnActivated;
        App.Services.Preferences.Changed += OnPreferenceChanged;
        Closed += (_, _) =>
        {
            App.Services.Preferences.Changed -= OnPreferenceChanged;
            _hotkeyHook?.Dispose();
        };
        DispatcherQueue.TryEnqueue(BootShellAsync);
    }

    private void OnActivated(object sender, WindowActivatedEventArgs e)
    {
        if (_hwnd != IntPtr.Zero) return;
        _hwnd = WindowNative.GetWindowHandle(this);
        _hotkeyHook = new HotkeyHook(_hwnd, App.Services.Hotkeys);
        SyncQuickAskHotkey();
        App.Services.Hotkeys.Register(GlobalHotkeyService.Modifiers.Ctrl | GlobalHotkeyService.Modifiers.Shift, 0x50 /* P */, OpenCommandPalette);
        WireSystemTray();
    }

    private void OnPreferenceChanged(string key)
    {
        if (key is WindowsPreferenceKeys.QuickAskEnabled or "*")
            DispatcherQueue.TryEnqueue(SyncQuickAskHotkey);
        if (key is WindowsPreferenceKeys.Theme or "*")
            DispatcherQueue.TryEnqueue(ApplyThemePreference);
        if (key is WindowsPreferenceKeys.UseDevMicaBackdrop or "*")
            DispatcherQueue.TryEnqueue(ApplyBackdropPreference);
    }

    private void SyncQuickAskHotkey()
    {
        var enabled = App.Services.Preferences.Get(
            WindowsPreferenceKeys.QuickAskEnabled,
            QuickAskSettingsDefaults.Enabled);

        if (enabled && _quickAskHotkeyId is null)
        {
            _quickAskHotkeyId = App.Services.Hotkeys.Register(GlobalHotkeyService.Modifiers.Ctrl, 0x4B /* K */, OpenQuickAsk);
        }
        else if (!enabled && _quickAskHotkeyId is int id)
        {
            App.Services.Hotkeys.Unregister(id);
            _quickAskHotkeyId = null;
        }
    }

    private async void BootShellAsync()
    {
        await Task.Delay(150);
        var bridge = App.Services.Bridge.Probe();
        if (!bridge.Alive)
        {
            Splash.Visibility = Visibility.Collapsed;
            LoginGate.Visibility = Visibility.Visible;
            return;
        }
        ShowShell();
    }

    private void ShowShell()
    {
        Splash.Visibility = Visibility.Collapsed;
        LoginGate.Visibility = Visibility.Collapsed;
        Shell.Visibility = Visibility.Visible;
    }

    private void OpenAccountSettings()
    {
        var win = new SettingsWindow("account");
        win.Activate();
    }

    private void StartBackendLogin()
    {
        try
        {
            LoginGate.SetStatus(App.Services.Auth.StartLogin());
            OpenAccountSettings();
        }
        catch (Exception ex)
        {
            LoginGate.SetStatus($"Could not start sign-in flow: {ex.Message}");
        }
    }

    private void WireSystemTray()
    {
        var tray = App.Services.Tray;
        tray.OpenRequested += () => DispatcherQueue.TryEnqueue(() => Activate());
        tray.PairRequested += () => DispatcherQueue.TryEnqueue(() =>
        {
            Activate();
            var win = new SettingsWindow("pairing");
            win.Activate();
        });
        tray.QuitRequested += () => DispatcherQueue.TryEnqueue(Close);
        if (App.Services.Preferences.Get(WindowsPreferenceKeys.ShowInTray, true))
            tray.Show();
        else
            tray.Hide();
    }

    private void OpenQuickAsk() => DispatcherQueue.TryEnqueue(QuickAskWindow.ShowOrFocus);
    private void OpenCommandPalette() => DispatcherQueue.TryEnqueue(CommandPaletteWindow.ShowOrFocus);

    private void ApplyThemePreference()
    {
        if (Content is not FrameworkElement root) return;

        root.RequestedTheme = WindowsGeneralSettingsDefaults.NormalizeTheme(App.Services.Preferences.Get(
            WindowsPreferenceKeys.Theme,
            WindowsGeneralSettingsDefaults.ThemeSystem)) switch
        {
            WindowsGeneralSettingsDefaults.ThemeLight => ElementTheme.Light,
            WindowsGeneralSettingsDefaults.ThemeDark => ElementTheme.Dark,
            _ => ElementTheme.Default,
        };
    }

    private void ApplyBackdropPreference()
    {
        if (App.Services.Preferences.Get(WindowsPreferenceKeys.UseDevMicaBackdrop, true))
            TrySetMicaBackdrop();
        else
            SystemBackdrop = new DesktopAcrylicBackdrop();
    }

    private void TrySetMicaBackdrop()
    {
        try
        {
            if (MicaController.IsSupported())
                SystemBackdrop = new MicaBackdrop { Kind = MicaKind.Base };
            else
                SystemBackdrop = new DesktopAcrylicBackdrop();
        }
        catch { /* fallback to default chrome */ }
    }
}
