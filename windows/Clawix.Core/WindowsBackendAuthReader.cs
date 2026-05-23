using System.Text.Json;

namespace Clawix.Core;

public sealed record WindowsBackendAccountProfile(
    string? Email,
    string? AccountLabel,
    string? PlanType,
    string? Name)
{
    public bool IsSignedIn => !string.IsNullOrWhiteSpace(Email);
    public static WindowsBackendAccountProfile Empty { get; } = new(null, null, null, null);
}

public static class WindowsBackendAuthReader
{
    private const string AuthClaim = "https://api.openai.com/auth";

    public static string DefaultAuthPath(string? userProfile = null)
    {
        var profile = string.IsNullOrWhiteSpace(userProfile)
            ? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
            : userProfile;
        return Path.Combine(profile, ".codex", "auth.json");
    }

    public static WindowsBackendAccountProfile Read(string authPath)
    {
        if (!File.Exists(authPath)) return WindowsBackendAccountProfile.Empty;
        try
        {
            return ReadJson(File.ReadAllText(authPath));
        }
        catch
        {
            return WindowsBackendAccountProfile.Empty;
        }
    }

    public static WindowsBackendAccountProfile ReadJson(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (!doc.RootElement.TryGetProperty("tokens", out var tokens)
                || !tokens.TryGetProperty("id_token", out var idTokenElement)
                || idTokenElement.GetString() is not { Length: > 0 } idToken
                || DecodeJwtPayload(idToken) is not { } payload)
                return WindowsBackendAccountProfile.Empty;

            var email = ReadNonEmptyString(payload.RootElement, "email");
            var name = ReadNonEmptyString(payload.RootElement, "name");
            var planType = ReadPlanType(payload.RootElement);
            var accountLabel = ReadAccountLabel(payload.RootElement);
            return new WindowsBackendAccountProfile(email, accountLabel, planType, name);
        }
        catch
        {
            return WindowsBackendAccountProfile.Empty;
        }
    }

    private static JsonDocument? DecodeJwtPayload(string token)
    {
        var parts = token.Split('.');
        if (parts.Length < 2) return null;
        var payload = Base64UrlDecode(parts[1]);
        return payload is null ? null : JsonDocument.Parse(payload);
    }

    private static string? ReadPlanType(JsonElement payload)
    {
        return payload.TryGetProperty(AuthClaim, out var auth)
            ? ReadNonEmptyString(auth, "chatgpt_plan_type")
            : null;
    }

    private static string? ReadAccountLabel(JsonElement payload)
    {
        if (!payload.TryGetProperty(AuthClaim, out var auth)
            || !auth.TryGetProperty("organizations", out var organizations)
            || organizations.ValueKind != JsonValueKind.Array)
            return null;

        JsonElement? chosen = null;
        foreach (var organization in organizations.EnumerateArray())
        {
            chosen ??= organization;
            if (organization.TryGetProperty("is_default", out var isDefault)
                && isDefault.ValueKind == JsonValueKind.True)
            {
                chosen = organization;
                break;
            }
        }

        if (chosen is not { } org) return null;
        var title = ReadNonEmptyString(org, "title");
        if (title is null) return null;
        return title.Equals("Personal", StringComparison.OrdinalIgnoreCase)
            ? "Personal account"
            : $"Account {title}";
    }

    private static string? ReadNonEmptyString(JsonElement element, string propertyName)
    {
        return element.TryGetProperty(propertyName, out var property)
            && property.GetString() is { Length: > 0 } value
            ? value
            : null;
    }

    private static byte[]? Base64UrlDecode(string value)
    {
        var base64 = value.Replace('-', '+').Replace('_', '/');
        var padding = (4 - base64.Length % 4) % 4;
        if (padding > 0) base64 += new string('=', padding);
        try { return Convert.FromBase64String(base64); }
        catch { return null; }
    }

}
