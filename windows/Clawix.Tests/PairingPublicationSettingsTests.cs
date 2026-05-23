using Clawix.Core;
using Xunit;

namespace Clawix.Tests;

public sealed class PairingPublicationSettingsTests
{
    [Fact]
    public void ReadBonjourEnabled_DefaultsToPublishing()
    {
        var path = Path.Combine(Path.GetTempPath(), $"pairing-publication-{Guid.NewGuid():N}.json");

        Assert.True(PairingPublicationSettings.ReadBonjourEnabled(path));
    }

    [Fact]
    public void WriteBonjourEnabled_PersistsDisabledState()
    {
        var path = Path.Combine(Path.GetTempPath(), $"pairing-publication-{Guid.NewGuid():N}.json");
        try
        {
            PairingPublicationSettings.WriteBonjourEnabled(false, path);

            Assert.False(PairingPublicationSettings.ReadBonjourEnabled(path));
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void ReadBonjourEnabled_FallsBackToDefaultOnInvalidJson()
    {
        var path = Path.Combine(Path.GetTempPath(), $"pairing-publication-{Guid.NewGuid():N}.json");
        try
        {
            File.WriteAllText(path, "{not json");

            Assert.True(PairingPublicationSettings.ReadBonjourEnabled(path));
        }
        finally
        {
            File.Delete(path);
        }
    }
}
