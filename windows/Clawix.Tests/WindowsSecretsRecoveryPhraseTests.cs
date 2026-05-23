using Clawix.Core;
using Xunit;

namespace Clawix.Tests;

public sealed class WindowsSecretsRecoveryPhraseTests
{
    [Fact]
    public void FromBytes_ProducesTwentyFourWords()
    {
        var bytes = Enumerable.Range(0, 24).Select(i => (byte)i).ToArray();

        var phrase = WindowsSecretsRecoveryPhrase.FromBytes(bytes);

        var words = phrase.Split(' ');
        Assert.Equal(24, words.Length);
        Assert.Equal("able", words[0]);
        Assert.Equal("fabric", words[23]);
    }

    [Fact]
    public void FromBytes_RejectsShortEntropy()
    {
        Assert.Throws<ArgumentException>(() => WindowsSecretsRecoveryPhrase.FromBytes([1, 2, 3]));
    }

    [Fact]
    public void Generate_ProducesPhrase()
    {
        Assert.Equal(24, WindowsSecretsRecoveryPhrase.Generate().Split(' ').Length);
    }
}
