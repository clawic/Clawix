using Clawix.Bridged;
using Clawix.Core.Models;
using Xunit;

namespace Clawix.Tests;

public sealed class AudioCatalogStoreTests
{
    [Fact]
    public void RegisterGetListTranscriptAndDelete_RoundTripAudioCatalog()
    {
        var root = Path.Combine(Path.GetTempPath(), $"clawix-audio-{Guid.NewGuid():N}");
        var store = new AudioCatalogStore(root);
        try
        {
            var registered = store.Register(new WireAudioRegisterRequest
            {
                Id = "audio-1",
                Kind = WireAudioKind.UserMessage,
                AppId = "clawix",
                OriginActor = WireAudioOriginActor.User,
                MimeType = "audio/m4a",
                BytesBase64 = "ZmFrZUF1ZGlv",
                DurationMs = 2400,
                DeviceId = "device-win",
                SessionId = "session-1",
                ThreadId = "thread-1",
                LinkedMessageId = "message-1",
                MetadataJson = "{\"source\":\"test\"}",
                Transcript = new WireAudioRegisterTranscript
                {
                    Text = "hello audio",
                    Role = WireAudioTranscriptRole.Transcription,
                    Provider = "local",
                    Language = "en",
                },
            });

            Assert.Null(registered.Error);
            Assert.NotNull(registered.Asset);
            Assert.Equal("audio-1", registered.Asset.Asset.Id);
            Assert.Single(registered.Asset.Transcripts);

            var bytes = store.GetBytes("audio-1", "clawix");
            Assert.Null(bytes.Error);
            Assert.Equal("ZmFrZUF1ZGlv", bytes.AudioBase64);
            Assert.Equal("audio/m4a", bytes.MimeType);
            Assert.Equal(2400, bytes.DurationMs);

            var transcript = store.AttachTranscript("audio-1", new WireAudioAttachTranscriptInput
            {
                Text = "better transcript",
                Role = WireAudioTranscriptRole.Transcription,
                Provider = "local",
                Language = "en",
                MarkAsPrimary = true,
            });
            Assert.Null(transcript.Error);
            Assert.True(transcript.Transcript?.IsPrimary == true);

            var fetched = store.Get("audio-1", "clawix");
            Assert.Null(fetched.Error);
            Assert.Equal(2, fetched.Asset?.Transcripts.Count);
            Assert.Single(fetched.Asset!.Transcripts.Where(item => item.IsPrimary));

            var list = store.List(new WireAudioListFilter { AppId = "clawix", ThreadId = "thread-1" });
            Assert.Null(list.Error);
            Assert.Equal(1, list.List?.Total);
            Assert.Single(list.List!.Items);

            var deleted = store.Delete("audio-1", "clawix");
            Assert.True(deleted.Deleted);
            Assert.Null(deleted.Error);
            Assert.Equal("Audio no longer available", store.Get("audio-1", "clawix").Error);
        }
        finally
        {
            try { Directory.Delete(root, recursive: true); } catch { }
        }
    }
}
