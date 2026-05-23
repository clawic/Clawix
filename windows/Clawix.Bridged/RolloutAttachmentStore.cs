using Clawix.Core.Models;

namespace Clawix.Bridged;

public sealed class RolloutAttachmentStore
{
    private readonly string _root;
    private readonly object _gate = new();

    public RolloutAttachmentStore(string root)
    {
        _root = root;
    }

    public void Register(IReadOnlyList<WireAttachment> attachments)
    {
        foreach (var attachment in attachments)
        {
            Register(attachment);
        }
    }

    public (string? DataBase64, string? MimeType, string? Error) Read(string attachmentId)
    {
        lock (_gate)
        {
            var id = SafeId(attachmentId);
            var metadataPath = MetadataPath(id);
            if (!File.Exists(metadataPath)) return (null, null, "Attachment no longer available");

            try
            {
                var mimeType = File.ReadAllText(metadataPath).Trim();
                if (string.IsNullOrWhiteSpace(mimeType)) return (null, null, "Attachment no longer available");
                var bytesPath = BytesPath(id);
                if (!File.Exists(bytesPath)) return (null, null, "Attachment no longer available");
                return (Convert.ToBase64String(File.ReadAllBytes(bytesPath)), mimeType, null);
            }
            catch
            {
                return (null, null, "Attachment no longer available");
            }
        }
    }

    private void Register(WireAttachment attachment)
    {
        byte[] bytes;
        try
        {
            bytes = Convert.FromBase64String(attachment.DataBase64);
        }
        catch (FormatException)
        {
            return;
        }
        if (bytes.Length == 0) return;

        lock (_gate)
        {
            Directory.CreateDirectory(_root);
            var id = SafeId(attachment.Id);
            File.WriteAllBytes(BytesPath(id), bytes);
            var path = MetadataPath(id);
            var tmp = path + ".tmp";
            File.WriteAllText(tmp, attachment.MimeType);
            File.Move(tmp, path, overwrite: true);
        }
    }

    private string BytesPath(string id) => Path.Combine(_root, $"{id}.bin");

    private string MetadataPath(string id) => Path.Combine(_root, $"{id}.json");

    private static string SafeId(string id)
    {
        var clean = new string(id.Select(ch => char.IsLetterOrDigit(ch) || ch is '-' or '_' or '.' ? ch : '-').ToArray());
        return string.IsNullOrWhiteSpace(clean) ? $"attachment-{Guid.NewGuid():N}" : clean;
    }
}
