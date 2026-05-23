using Clawix.Core;
using Xunit;

namespace Clawix.Tests;

public sealed class LocalModelInventoryTests
{
    [Fact]
    public void Snapshot_ReportsKnownModelInstallStateAndSizes()
    {
        var root = Path.Combine(Path.GetTempPath(), $"clawix-models-{Guid.NewGuid():N}");
        try
        {
            Directory.CreateDirectory(root);
            File.WriteAllBytes(Path.Combine(root, "ggml-base.bin"), new byte[1536]);

            var models = LocalModelInventory.Snapshot(root);
            var baseModel = models.Single(model => model.Name == "base");
            var tinyModel = models.Single(model => model.Name == "tiny");

            Assert.True(baseModel.Installed);
            Assert.Equal("1.5 KB", baseModel.DisplaySize);
            Assert.False(tinyModel.Installed);
            Assert.Equal("", tinyModel.DisplaySize);
        }
        finally
        {
            try { Directory.Delete(root, recursive: true); } catch { }
        }
    }
}
