using System.Text.Json;
using Clawix.Core;
using Xunit;

namespace Clawix.Tests;

public sealed class BridgeFixtureParityTests
{
    [Fact]
    public void GeneratedSwiftBridgeFixtures_DecodeAndRoundTrip()
    {
        var root = Path.Combine(AppContext.BaseDirectory, "CanonicalBridgeFixtures");
        var manifestPath = Path.Combine(root, "manifest.json");
        Assert.True(File.Exists(manifestPath), $"expected generated bridge manifest at {manifestPath}");

        using var manifestDoc = JsonDocument.Parse(File.ReadAllText(manifestPath));
        var manifest = manifestDoc.RootElement;
        Assert.Equal("clawix.protocol.bridge.v1", manifest.GetProperty("contractId").GetString());
        Assert.Equal(BridgeConstants.SchemaVersion, manifest.GetProperty("bridgeSchemaVersion").GetInt32());

        var fixtures = manifest.GetProperty("fixtures").EnumerateArray().ToArray();
        Assert.Equal(manifest.GetProperty("fixtureCount").GetInt32(), fixtures.Length);

        Assert.True(fixtures.Length >= 50, $"expected Swift bridge fixtures in {root}");

        var types = new HashSet<string>(StringComparer.Ordinal);
        foreach (var fixture in fixtures)
        {
            var fileName = fixture.GetProperty("file").GetString();
            Assert.False(string.IsNullOrWhiteSpace(fileName), "fixture entry is missing file");
            var file = Path.Combine(root, fileName!);
            var json = File.ReadAllText(file);
            using var doc = JsonDocument.Parse(json);
            var type = doc.RootElement.GetProperty("type").GetString();
            Assert.False(string.IsNullOrWhiteSpace(type), $"{file} is missing type");
            Assert.Equal(fixture.GetProperty("type").GetString(), type);
            types.Add(type!);

            var frame = BridgeCoder.Decode(json);
            Assert.Equal(BridgeConstants.SchemaVersion, frame.SchemaVersion);

            var encoded = BridgeCoder.Encode(frame);
            var roundTrip = BridgeCoder.Decode(encoded);
            Assert.Equal(encoded, BridgeCoder.Encode(roundTrip));
        }

        foreach (var required in new[]
        {
            "auth",
            "sendMessage",
            "pairingPayload",
            "rateLimitsSnapshot",
            "audioRegister",
            "audioAttachTranscript",
            "audioGet",
            "audioGetBytes",
            "audioList",
            "audioDelete",
            "requestRolloutAttachment",
            "rolloutAttachmentSnapshot",
            "requestClawJSServiceStatuses",
            "clawJSServiceStatusesSnapshot",
            "clawJSServiceStatusUpdated",
            "audioRegisterResult",
            "audioAttachTranscriptResult",
            "audioGetResult",
            "audioBytesResult",
            "audioListResult",
            "audioDeleteResult",
        })
        {
            Assert.Contains(required, types);
        }
    }
}
