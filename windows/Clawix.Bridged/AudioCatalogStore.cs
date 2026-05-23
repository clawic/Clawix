using System.Text.Json;
using Clawix.Core;
using Clawix.Core.Models;

namespace Clawix.Bridged;

public sealed class AudioCatalogStore
{
    private const string BytesDirectoryName = "bytes";
    private const string MetadataDirectoryName = "metadata";

    private readonly string _root;
    private readonly string _bytesRoot;
    private readonly string _metadataRoot;
    private readonly object _gate = new();

    public AudioCatalogStore(string root)
    {
        _root = root;
        _bytesRoot = Path.Combine(root, BytesDirectoryName);
        _metadataRoot = Path.Combine(root, MetadataDirectoryName);
    }

    public (WireAudioAssetWithTranscripts? Asset, string? Error) Register(WireAudioRegisterRequest request)
    {
        byte[] bytes;
        try
        {
            bytes = Convert.FromBase64String(request.BytesBase64);
        }
        catch (FormatException)
        {
            return (null, "Audio decode failed");
        }

        var id = string.IsNullOrWhiteSpace(request.Id) ? $"audio-{Guid.NewGuid():N}" : SafeId(request.Id);
        var now = NowMs();
        var bytesRelPath = Path.Combine(BytesDirectoryName, $"{id}.bin").Replace('\\', '/');
        var bytesPath = Path.Combine(_root, bytesRelPath);
        var asset = new WireAudioAsset
        {
            Id = id,
            Kind = request.Kind,
            AppId = request.AppId,
            OriginActor = request.OriginActor,
            MimeType = request.MimeType,
            BytesRelPath = bytesRelPath,
            DurationMs = request.DurationMs,
            CreatedAt = now,
            DeviceId = request.DeviceId,
            SessionId = request.SessionId,
            ThreadId = request.ThreadId,
            LinkedMessageId = request.LinkedMessageId,
            MetadataJson = request.MetadataJson,
        };

        List<WireAudioTranscript> transcripts = request.Transcript is null
            ? []
            : new List<WireAudioTranscript>
            {
                new()
                {
                    Id = $"transcript-{Guid.NewGuid():N}",
                    AudioId = id,
                    Role = request.Transcript.Role ?? WireAudioTranscriptRole.Transcription,
                    Text = request.Transcript.Text,
                    Provider = request.Transcript.Provider,
                    Language = request.Transcript.Language,
                    CreatedAt = now,
                    IsPrimary = true,
                },
            };

        var stored = new WireAudioAssetWithTranscripts { Asset = asset, Transcripts = transcripts };
        lock (_gate)
        {
            EnsureDirectories();
            File.WriteAllBytes(bytesPath, bytes);
            WriteMetadata(stored);
        }

        return (stored, null);
    }

    public (WireAudioTranscript? Transcript, string? Error) AttachTranscript(string audioId, WireAudioAttachTranscriptInput transcript)
    {
        lock (_gate)
        {
            var stored = ReadMetadata(audioId);
            if (stored is null) return (null, "Audio no longer available");

            var markPrimary = transcript.MarkAsPrimary ?? !stored.Transcripts.Any(item => item.IsPrimary);
            var next = new WireAudioTranscript
            {
                Id = $"transcript-{Guid.NewGuid():N}",
                AudioId = stored.Asset.Id,
                Role = transcript.Role,
                Text = transcript.Text,
                Provider = transcript.Provider,
                Language = transcript.Language,
                CreatedAt = NowMs(),
                IsPrimary = markPrimary,
            };
            var transcripts = markPrimary
                ? stored.Transcripts.Select(item => item with { IsPrimary = false }).Append(next).ToList()
                : stored.Transcripts.Append(next).ToList();
            var updated = stored with { Transcripts = transcripts };
            WriteMetadata(updated);
            return (next, null);
        }
    }

    public (WireAudioAssetWithTranscripts? Asset, string? Error) Get(string audioId, string appId)
    {
        lock (_gate)
        {
            var stored = ReadMetadata(audioId);
            if (stored is null || !stored.Asset.AppId.Equals(appId, StringComparison.OrdinalIgnoreCase))
            {
                return (null, "Audio no longer available");
            }
            return (stored, null);
        }
    }

    public (string? AudioBase64, string? MimeType, int? DurationMs, string? Error) GetBytes(string audioId, string appId)
    {
        lock (_gate)
        {
            var stored = ReadMetadata(audioId);
            if (stored is null || !stored.Asset.AppId.Equals(appId, StringComparison.OrdinalIgnoreCase))
            {
                return (null, null, null, "Audio no longer available");
            }
            var bytesPath = Path.Combine(_root, stored.Asset.BytesRelPath.Replace('/', Path.DirectorySeparatorChar));
            if (!File.Exists(bytesPath)) return (null, null, null, "Audio bytes no longer available");
            return (Convert.ToBase64String(File.ReadAllBytes(bytesPath)), stored.Asset.MimeType, stored.Asset.DurationMs, null);
        }
    }

    public (WireAudioListResult? List, string? Error) List(WireAudioListFilter filter)
    {
        lock (_gate)
        {
            EnsureDirectories();
            var items = Directory.EnumerateFiles(_metadataRoot, "*.json")
                .Select(path => ReadMetadataFile(path))
                .Where(item => item is not null)
                .Cast<WireAudioAssetWithTranscripts>()
                .Where(item => Matches(item.Asset, filter))
                .OrderByDescending(item => item.Asset.CreatedAt)
                .ToList();
            var total = items.Count;
            var offset = Math.Max(filter.Offset ?? 0, 0);
            var limit = Math.Max(filter.Limit ?? total, 0);
            var page = items.Skip(offset).Take(limit).ToList();
            return (new WireAudioListResult { Items = page, Total = total }, null);
        }
    }

    public (bool Deleted, string? Error) Delete(string audioId, string appId)
    {
        lock (_gate)
        {
            var stored = ReadMetadata(audioId);
            if (stored is null || !stored.Asset.AppId.Equals(appId, StringComparison.OrdinalIgnoreCase))
            {
                return (false, "Audio no longer available");
            }
            var bytesPath = Path.Combine(_root, stored.Asset.BytesRelPath.Replace('/', Path.DirectorySeparatorChar));
            File.Delete(bytesPath);
            File.Delete(MetadataPath(stored.Asset.Id));
            return (true, null);
        }
    }

    private static bool Matches(WireAudioAsset asset, WireAudioListFilter filter)
    {
        return asset.AppId.Equals(filter.AppId, StringComparison.OrdinalIgnoreCase)
            && (filter.Kind is null || asset.Kind == filter.Kind)
            && (filter.OriginActor is null || asset.OriginActor == filter.OriginActor)
            && (filter.DeviceId is null || asset.DeviceId == filter.DeviceId)
            && (filter.SessionId is null || asset.SessionId == filter.SessionId)
            && (filter.ThreadId is null || asset.ThreadId == filter.ThreadId)
            && (filter.LinkedMessageId is null || asset.LinkedMessageId == filter.LinkedMessageId)
            && (filter.FromCreatedAt is null || asset.CreatedAt >= filter.FromCreatedAt)
            && (filter.ToCreatedAt is null || asset.CreatedAt <= filter.ToCreatedAt);
    }

    private WireAudioAssetWithTranscripts? ReadMetadata(string audioId)
    {
        var path = MetadataPath(SafeId(audioId));
        return File.Exists(path) ? ReadMetadataFile(path) : null;
    }

    private static WireAudioAssetWithTranscripts? ReadMetadataFile(string path)
    {
        try
        {
            return JsonSerializer.Deserialize<WireAudioAssetWithTranscripts>(
                File.ReadAllText(path),
                BridgeCoder.Options);
        }
        catch
        {
            return null;
        }
    }

    private void WriteMetadata(WireAudioAssetWithTranscripts asset)
    {
        EnsureDirectories();
        var json = JsonSerializer.Serialize(asset, BridgeCoder.Options);
        var path = MetadataPath(asset.Asset.Id);
        var tmp = path + ".tmp";
        File.WriteAllText(tmp, json);
        File.Move(tmp, path, overwrite: true);
    }

    private string MetadataPath(string audioId)
    {
        return Path.Combine(_metadataRoot, $"{SafeId(audioId)}.json");
    }

    private void EnsureDirectories()
    {
        Directory.CreateDirectory(_root);
        Directory.CreateDirectory(_bytesRoot);
        Directory.CreateDirectory(_metadataRoot);
    }

    private static string SafeId(string id)
    {
        var clean = new string(id.Select(ch => char.IsLetterOrDigit(ch) || ch is '-' or '_' or '.' ? ch : '-').ToArray());
        return string.IsNullOrWhiteSpace(clean) ? $"audio-{Guid.NewGuid():N}" : clean;
    }

    private static long NowMs() => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
}
