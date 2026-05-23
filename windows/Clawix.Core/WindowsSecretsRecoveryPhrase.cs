using System.Security.Cryptography;

namespace Clawix.Core;

public static class WindowsSecretsRecoveryPhrase
{
    private const int WordCount = 24;

    private static readonly string[] Words =
    [
        "able", "anchor", "april", "artist", "atlas", "basic", "beacon", "binary",
        "border", "cactus", "candle", "carbon", "cedar", "census", "circle", "copper",
        "cotton", "delta", "doctor", "domain", "eagle", "ember", "engine", "fabric",
        "falcon", "forest", "garden", "harbor", "hazel", "honest", "island", "jacket",
        "kernel", "ladder", "lantern", "magnet", "marble", "matrix", "meadow", "meteor",
        "native", "nectar", "orange", "packet", "pencil", "planet", "quartz", "radar",
        "rocket", "saddle", "signal", "silver", "summit", "temple", "timber", "velvet",
        "violet", "window", "winter", "yellow", "zephyr", "zinc", "zone", "zonal",
    ];

    public static string Generate()
    {
        Span<byte> bytes = stackalloc byte[WordCount];
        RandomNumberGenerator.Fill(bytes);
        return FromBytes(bytes);
    }

    public static string FromBytes(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length < WordCount)
            throw new ArgumentException($"Recovery phrase entropy must contain at least {WordCount} bytes.", nameof(bytes));

        var words = new string[WordCount];
        for (var i = 0; i < words.Length; i++)
            words[i] = Words[bytes[i] % Words.Length];
        return string.Join(" ", words);
    }
}
