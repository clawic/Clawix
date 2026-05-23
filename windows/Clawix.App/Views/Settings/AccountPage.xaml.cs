using System.Diagnostics;
using System.Text.Json;
using Clawix.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views.Settings;

public sealed partial class AccountPage : Page
{
    private string _authPath = WindowsBackendAuthReader.DefaultAuthPath();
    private WindowsBackendAccountProfile _profile = WindowsBackendAccountProfile.Empty;

    public AccountPage()
    {
        InitializeComponent();
        Loaded += (_, _) => RefreshAccount();
    }

    private void RefreshAccount()
    {
        _authPath = WindowsBackendAuthReader.DefaultAuthPath();
        _profile = WindowsBackendAuthReader.Read(_authPath);
        if (_profile.IsSignedIn)
        {
            AccountInfo.Severity = InfoBarSeverity.Success;
            AccountInfo.Title = "Signed in";
            AccountInfo.Message = _profile.Email ?? "Connected account";
            ProfileText.Text = string.Join(Environment.NewLine, new[]
            {
                _profile.Name,
                _profile.AccountLabel,
                _profile.PlanType is null ? null : $"Plan: {_profile.PlanType}",
                $"Auth file: {_authPath}",
            }.Where(line => !string.IsNullOrWhiteSpace(line)));
            AuthActionButton.Content = "Sign out";
        }
        else
        {
            AccountInfo.Severity = InfoBarSeverity.Warning;
            AccountInfo.Title = "Signed out";
            AccountInfo.Message = "Run sign in to create the local auth file.";
            ProfileText.Text = $"Auth file: {_authPath}";
            AuthActionButton.Content = "Sign in";
        }
    }

    private async void AuthAction_Click(object sender, RoutedEventArgs e)
    {
        if (_profile.IsSignedIn)
            await SignOutAsync();
        else
            StartLogin();
    }

    private async void ViewTokens_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "Access tokens",
            PrimaryButtonText = "Done",
            Content = new TextBlock
            {
                Text = TokenSummary(),
                TextWrapping = TextWrapping.Wrap,
                FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Cascadia Mono"),
            },
        };
        await dlg.ShowAsync();
    }

    private async void RotateRefreshToken_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new ConfirmationDialog { XamlRoot = XamlRoot };
        dlg.Configure(
            "Rotate refresh token",
            "The local auth file will be removed, then the backend sign-in flow will start so the runtime can issue fresh tokens.");
        if (await dlg.ShowAsync() != ContentDialogResult.Primary) return;

        DeleteAuthFile();
        RefreshAccount();
        StartLogin();
    }

    private async Task SignOutAsync()
    {
        var dlg = new ConfirmationDialog { XamlRoot = XamlRoot };
        dlg.Configure("Sign out", "The local auth file will be removed from this Windows account.");
        if (await dlg.ShowAsync() != ContentDialogResult.Primary) return;

        DeleteAuthFile();
        StatusText.Text = "Signed out.";
        RefreshAccount();
    }

    private void StartLogin()
    {
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "codex",
                Arguments = "login",
                UseShellExecute = true,
            });
            StatusText.Text = "Sign-in flow started. Refresh this page after the browser flow finishes.";
        }
        catch (Exception ex)
        {
            StatusText.Text = $"Could not start sign-in flow: {ex.Message}";
        }
    }

    private void DeleteAuthFile()
    {
        try
        {
            if (File.Exists(_authPath))
                File.Delete(_authPath);
        }
        catch (Exception ex)
        {
            StatusText.Text = $"Could not remove auth file: {ex.Message}";
        }
    }

    private string TokenSummary()
    {
        if (!File.Exists(_authPath))
            return "No local auth file found.";

        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(_authPath));
            if (!doc.RootElement.TryGetProperty("tokens", out var tokens)
                || tokens.ValueKind != JsonValueKind.Object)
                return "No token object found.";

            var names = tokens.EnumerateObject()
                .Select(property => $"{property.Name}: [stored]")
                .Order(StringComparer.OrdinalIgnoreCase)
                .ToArray();
            return names.Length == 0
                ? "No tokens found."
                : string.Join(Environment.NewLine, names);
        }
        catch (Exception ex)
        {
            return $"Could not read token metadata: {ex.Message}";
        }
    }
}
