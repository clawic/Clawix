namespace Clawix.Core;

public static class WindowsSecretsProjectionRoutes
{
    public const string DefaultTenantId = "clawix-local";
    public const string LoopbackHost = "127.0.0.1";

    public static Uri DefaultBaseUri(int port = 24103) => new UriBuilder("http", LoopbackHost, port).Uri;

    public static Uri State(Uri baseUri) => Build(baseUri, "/api/v1/secrets/state");

    public static Uri Lock(Uri baseUri) => Build(baseUri, "/api/v1/secrets/lock");

    public static Uri Secrets(Uri baseUri, string tenantId = DefaultTenantId)
    {
        return Build(baseUri, $"/api/v1/tenants/{Uri.EscapeDataString(tenantId)}/secrets");
    }

    public static string InternalNameFromLabel(string label)
    {
        var chars = label
            .Trim()
            .ToLowerInvariant()
            .Select(ch => char.IsLetterOrDigit(ch) ? ch : '_')
            .ToArray();
        var name = new string(chars);
        while (name.Contains("__", StringComparison.Ordinal))
            name = name.Replace("__", "_", StringComparison.Ordinal);
        name = name.Trim('_');
        return name.Length == 0 ? $"secret_{Guid.NewGuid():N}" : name;
    }

    private static Uri Build(Uri baseUri, string relative)
    {
        return new Uri(baseUri, relative);
    }
}
