using System.Diagnostics;
using System.Text.Json;
using Clawix.Core;

namespace Clawix.App.Services;

public sealed class WindowsBackendAuthService
{
    public string AuthPath => WindowsBackendAuthReader.DefaultAuthPath();

    public WindowsBackendAccountProfile ReadProfile() => WindowsBackendAuthReader.Read(AuthPath);

    public string StartLogin()
    {
        StartBackendCommand("login");
        return "Sign-in flow started. Refresh after the browser flow finishes.";
    }

    public string SignOut()
    {
        try { StartBackendCommand("logout"); }
        catch { /* local auth deletion below still signs this app out */ }
        try
        {
            DeleteAuthFile();
            return "Signed out.";
        }
        catch (Exception ex)
        {
            return $"Could not remove auth file: {ex.Message}";
        }
    }

    public string RotateRefreshToken()
    {
        try { DeleteAuthFile(); }
        catch (Exception ex) { return $"Could not remove auth file: {ex.Message}"; }
        return StartLogin();
    }

    public string TokenSummary()
    {
        if (!File.Exists(AuthPath))
            return "No local auth file found.";

        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(AuthPath));
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

    private static void StartBackendCommand(string command)
    {
        var overridePath = Environment.GetEnvironmentVariable("CLAWIX_BRIDGE_BACKEND_PATH");
        var binary = WindowsBackendBinaryResolver.Resolve(overridePath: overridePath) ?? "codex";
        Process.Start(new ProcessStartInfo
        {
            FileName = binary,
            Arguments = command,
            UseShellExecute = true,
        });
    }

    private void DeleteAuthFile()
    {
        if (File.Exists(AuthPath))
            File.Delete(AuthPath);
    }
}
