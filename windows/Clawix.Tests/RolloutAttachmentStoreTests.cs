using Clawix.Bridged;
using Clawix.Core.Models;
using Xunit;

namespace Clawix.Tests;

public sealed class RolloutAttachmentStoreTests
{
    [Fact]
    public void RegisterAndRead_ReturnsKnownAttachmentBytesOnly()
    {
        var root = Path.Combine(Path.GetTempPath(), $"clawix-rollout-{Guid.NewGuid():N}");
        var store = new RolloutAttachmentStore(root);
        try
        {
            store.Register([
                new WireAttachment
                {
                    Id = "attachment-1",
                    MimeType = "image/png",
                    Filename = "screen.png",
                    DataBase64 = "ZmFrZUltYWdl",
                },
            ]);

            var read = store.Read("attachment-1");
            Assert.Null(read.Error);
            Assert.Equal("ZmFrZUltYWdl", read.DataBase64);
            Assert.Equal("image/png", read.MimeType);

            var missing = store.Read("missing");
            Assert.Null(missing.DataBase64);
            Assert.Equal("Attachment no longer available", missing.Error);
        }
        finally
        {
            try { Directory.Delete(root, recursive: true); } catch { }
        }
    }
}
