namespace Clawix.Core;

public static class BrowserAddress
{
    public static bool TryNormalize(string? input, out Uri uri)
    {
        uri = new Uri("about:blank");
        var trimmed = (input ?? "").Trim();
        if (trimmed.Length == 0) return false;

        if (!trimmed.Contains("://", StringComparison.Ordinal) &&
            !trimmed.StartsWith("about:", StringComparison.OrdinalIgnoreCase))
        {
            trimmed = "https://" + trimmed;
        }

        return Uri.TryCreate(trimmed, UriKind.Absolute, out uri!);
    }
}
