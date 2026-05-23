using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Clawix.Core;

namespace Clawix.App.Services;

/// <summary>
/// Windows projection for the canonical ClawJS Secrets service. This deliberately
/// avoids a Windows-local secrets database so the governed ClawJS service remains
/// the authority, matching macOS' ownership boundary.
/// </summary>
public sealed class WindowsSecretsVaultService : IDisposable
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly HttpClient _http = new();

    public bool IsUnlocked => ReadState().Unlocked;

    public string RecoveryPhrase => "Recovery phrase is managed by ClawJS Secrets setup and recovery flows.";

    public IReadOnlyList<string> List()
    {
        var state = ReadState();
        if (!state.Initialized) return [];
        if (!state.Unlocked) return [];
        var token = AdminToken();
        if (string.IsNullOrWhiteSpace(token))
            throw new InvalidOperationException("Set CLAW_SECRETS_ADMIN_TOKEN to list Windows-projected ClawJS Secrets.");

        using var request = new HttpRequestMessage(HttpMethod.Get, WindowsSecretsProjectionRoutes.Secrets(BaseUri()));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        using var response = _http.Send(request);
        var body = response.Content.ReadAsStringAsync().GetAwaiter().GetResult();
        if (!response.IsSuccessStatusCode)
            throw new InvalidOperationException(ErrorMessage(response.StatusCode, body));

        using var doc = JsonDocument.Parse(body);
        if (!doc.RootElement.TryGetProperty("secrets", out var secrets) || secrets.ValueKind != JsonValueKind.Array)
            return [];

        var list = new List<string>();
        foreach (var secret in secrets.EnumerateArray())
        {
            var title = ReadString(secret, "title") ?? ReadString(secret, "internalName") ?? "Secret";
            var internalName = ReadString(secret, "internalName");
            list.Add(internalName is null || title == internalName ? title : $"{title} - {internalName}");
        }
        return list;
    }

    public void Add(string label, string kind, string value)
    {
        var token = AdminToken();
        if (string.IsNullOrWhiteSpace(token))
            throw new InvalidOperationException("Set CLAW_SECRETS_ADMIN_TOKEN to add Windows-projected ClawJS Secrets.");

        var normalizedLabel = label.Trim();
        if (normalizedLabel.Length == 0)
            throw new ArgumentException("Secret label is required.", nameof(label));
        if (string.IsNullOrEmpty(value))
            throw new ArgumentException("Secret value is required.", nameof(value));

        var fieldName = kind switch
        {
            "api_key" => "api_key",
            "token" => "token",
            _ => "value",
        };
        var draft = new
        {
            draft = new
            {
                internalName = WindowsSecretsProjectionRoutes.InternalNameFromLabel(normalizedLabel),
                title = normalizedLabel,
                fields = new[]
                {
                    new
                    {
                        fieldName,
                        fieldKind = "password",
                        placement = kind == "token" || kind == "api_key" ? "header" : "none",
                        isSecret = true,
                        isConcealed = true,
                        secretValue = value,
                    },
                },
            },
        };
        var json = JsonSerializer.Serialize(draft, JsonOptions);
        using var request = new HttpRequestMessage(HttpMethod.Post, WindowsSecretsProjectionRoutes.Secrets(BaseUri()))
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json"),
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        using var response = _http.Send(request);
        var body = response.Content.ReadAsStringAsync().GetAwaiter().GetResult();
        if (!response.IsSuccessStatusCode)
            throw new InvalidOperationException(ErrorMessage(response.StatusCode, body));
    }

    public void Lock()
    {
        using var response = _http.PostAsync(WindowsSecretsProjectionRoutes.Lock(BaseUri()), new StringContent("{}")).GetAwaiter().GetResult();
        if (!response.IsSuccessStatusCode)
        {
            var body = response.Content.ReadAsStringAsync().GetAwaiter().GetResult();
            throw new InvalidOperationException(ErrorMessage(response.StatusCode, body));
        }
    }

    public string StatusText()
    {
        try
        {
            var state = ReadState();
            if (!state.Initialized) return "ClawJS Secrets is reachable but not initialized.";
            if (!state.Unlocked) return "ClawJS Secrets is initialized but locked.";
            if (string.IsNullOrWhiteSpace(AdminToken())) return "ClawJS Secrets is unlocked. Set CLAW_SECRETS_ADMIN_TOKEN to list or add secrets from Windows.";
            return "ClawJS Secrets is unlocked and projected into Windows.";
        }
        catch (Exception ex)
        {
            return $"ClawJS Secrets is not reachable on Windows: {ex.Message}";
        }
    }

    public void Dispose() => _http.Dispose();

    private static Uri BaseUri()
    {
        var raw = Environment.GetEnvironmentVariable("CLAW_SECRETS_BASE_URL");
        return Uri.TryCreate(raw, UriKind.Absolute, out var uri)
            ? uri
            : WindowsSecretsProjectionRoutes.DefaultBaseUri();
    }

    private static string? AdminToken()
    {
        return Environment.GetEnvironmentVariable("CLAW_SECRETS_ADMIN_TOKEN")
            ?? Environment.GetEnvironmentVariable("CLAW_SECRETS_TOKEN");
    }

    private SecretsState ReadState()
    {
        using var response = _http.GetAsync(WindowsSecretsProjectionRoutes.State(BaseUri())).GetAwaiter().GetResult();
        var body = response.Content.ReadAsStringAsync().GetAwaiter().GetResult();
        if (!response.IsSuccessStatusCode)
            throw new InvalidOperationException(ErrorMessage(response.StatusCode, body));
        return JsonSerializer.Deserialize<SecretsState>(body, JsonOptions) ?? new SecretsState();
    }

    private static string ErrorMessage(HttpStatusCode statusCode, string body)
    {
        try
        {
            using var doc = JsonDocument.Parse(body);
            if (doc.RootElement.TryGetProperty("error", out var error) && error.GetString() is { Length: > 0 } message)
                return message;
        }
        catch { /* fall through */ }
        return $"ClawJS Secrets HTTP {(int)statusCode}.";
    }

    private static string? ReadString(JsonElement element, string propertyName)
    {
        return element.TryGetProperty(propertyName, out var property) ? property.GetString() : null;
    }

    private sealed record SecretsState
    {
        public bool Initialized { get; init; }
        public bool Unlocked { get; init; }
    }
}
