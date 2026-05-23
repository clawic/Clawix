using System.Text.Json;
using System.Text.Json.Serialization;
using Clawix.Core.Models;

namespace Clawix.Core;

/// <summary>
/// Custom converter for <see cref="BridgeFrame"/>. Flat JSON shape on the
/// wire (no <c>payload</c> envelope). Field name casing matches Swift
/// Codable defaults (camelCase).
/// </summary>
internal sealed partial class BridgeFrameConverter : JsonConverter<BridgeFrame>
{
    public override BridgeFrame Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        using var doc = JsonDocument.ParseValue(ref reader);
        var root = doc.RootElement;
        if (root.ValueKind != JsonValueKind.Object)
            throw new BridgeDecodingException("bridge frame must be a JSON object");

        if (!root.TryGetProperty("schemaVersion", out var protocolProp))
            throw new JsonException("frame missing 'schemaVersion'");
        var schemaVersion = protocolProp.GetInt32();
        if (schemaVersion != BridgeConstants.SchemaVersion)
            throw new BridgeDecodingException($"unsupported schemaVersion: {schemaVersion}");

        if (!root.TryGetProperty("type", out var typeProp))
            throw new JsonException("frame missing 'type'");
        var type = typeProp.GetString() ?? throw new JsonException("frame 'type' is null");
        ValidateTopLevel(root, type);

        var body = DecodeBody(root, type, options);
        return new BridgeFrame(body, schemaVersion);
    }

    private static readonly IReadOnlyDictionary<string, HashSet<string>> AllowedPayloadKeys =
        new Dictionary<string, HashSet<string>>(StringComparer.Ordinal)
        {
            ["auth"] = Keys("token", "deviceName", "clientKind", "clientId", "installationId", "deviceId"),
            ["listSessions"] = Keys(),
            ["openSession"] = Keys("sessionId", "limit"),
            ["loadOlderMessages"] = Keys("sessionId", "beforeMessageId", "limit"),
            ["sendMessage"] = Keys("sessionId", "text", "attachments"),
            ["newSession"] = Keys("sessionId", "text", "attachments"),
            ["interruptTurn"] = Keys("sessionId"),
            ["authOk"] = Keys("hostDisplayName"),
            ["authFailed"] = Keys("reason"),
            ["versionMismatch"] = Keys("serverVersion"),
            ["sessionsSnapshot"] = Keys("sessions"),
            ["sessionUpdated"] = Keys("session"),
            ["messagesSnapshot"] = Keys("sessionId", "messages", "hasMore"),
            ["messagesPage"] = Keys("sessionId", "messages", "hasMore"),
            ["messageAppended"] = Keys("sessionId", "message"),
            ["messageStreaming"] = Keys("sessionId", "messageId", "content", "reasoningText", "finished"),
            ["errorEvent"] = Keys("code", "message"),
            ["editPrompt"] = Keys("sessionId", "messageId", "text"),
            ["archiveSession"] = Keys("sessionId"),
            ["unarchiveSession"] = Keys("sessionId"),
            ["pinSession"] = Keys("sessionId"),
            ["unpinSession"] = Keys("sessionId"),
            ["renameSession"] = Keys("sessionId", "title"),
            ["pairingStart"] = Keys(),
            ["listProjects"] = Keys(),
            ["readFile"] = Keys("path"),
            ["pairingPayload"] = Keys("qrJson", "token", "shortCode"),
            ["projectsSnapshot"] = Keys("projects"),
            ["fileSnapshot"] = Keys("path", "content", "isMarkdown", "error"),
            ["transcribeAudio"] = Keys("requestId", "audioBase64", "mimeType", "language"),
            ["transcriptionResult"] = Keys("requestId", "text", "errorMessage"),
            ["requestAudio"] = Keys("audioId"),
            ["audioSnapshot"] = Keys("audioId", "audioBase64", "mimeType", "errorMessage"),
            ["requestGeneratedImage"] = Keys("path"),
            ["generatedImageSnapshot"] = Keys("path", "dataBase64", "mimeType", "errorMessage"),
            ["requestRolloutAttachment"] = Keys("attachmentId"),
            ["rolloutAttachmentSnapshot"] = Keys("attachmentId", "dataBase64", "mimeType", "errorMessage"),
            ["bridgeState"] = Keys("state", "chatCount", "message"),
            ["requestRateLimits"] = Keys(),
            ["rateLimitsSnapshot"] = Keys("rateLimits", "rateLimitsByLimitId"),
            ["rateLimitsUpdated"] = Keys("rateLimits", "rateLimitsByLimitId"),
            ["requestClawJSServiceStatuses"] = Keys(),
            ["clawJSServiceStatusesSnapshot"] = Keys("services"),
            ["clawJSServiceStatusUpdated"] = Keys("service"),
            ["audioRegister"] = Keys("requestId", "request"),
            ["audioAttachTranscript"] = Keys("requestId", "audioId", "transcript"),
            ["audioGet"] = Keys("requestId", "audioId", "appId"),
            ["audioGetBytes"] = Keys("requestId", "audioId", "appId"),
            ["audioList"] = Keys("requestId", "filter"),
            ["audioDelete"] = Keys("requestId", "audioId", "appId"),
            ["audioRegisterResult"] = Keys("requestId", "asset", "errorMessage"),
            ["audioAttachTranscriptResult"] = Keys("requestId", "transcript", "errorMessage"),
            ["audioGetResult"] = Keys("requestId", "asset", "errorMessage"),
            ["audioBytesResult"] = Keys("requestId", "audioBase64", "mimeType", "durationMs", "errorMessage"),
            ["audioListResult"] = Keys("requestId", "list", "errorMessage"),
            ["audioDeleteResult"] = Keys("requestId", "deleted", "errorMessage"),
        };

    private static HashSet<string> Keys(params string[] keys)
    {
        var allowed = new HashSet<string>(StringComparer.Ordinal) { "schemaVersion", "type" };
        foreach (var key in keys) allowed.Add(key);
        return allowed;
    }

    private static void ValidateTopLevel(JsonElement root, string type)
    {
        if (!AllowedPayloadKeys.TryGetValue(type, out var allowed))
            throw BridgeDecodingException.UnknownType(type);
        foreach (var property in root.EnumerateObject())
        {
            if (!allowed.Contains(property.Name))
                throw new BridgeDecodingException($"unexpected field for {type}: {property.Name}");
        }
    }

    private static BridgeBody DecodeBody(JsonElement root, string type, JsonSerializerOptions options)
    {
        T? Get<T>(string name) => root.TryGetProperty(name, out var p) && p.ValueKind != JsonValueKind.Null
            ? JsonSerializer.Deserialize<T>(p.GetRawText(), options)
            : default;

        T GetReq<T>(string name) => root.TryGetProperty(name, out var p)
            ? JsonSerializer.Deserialize<T>(p.GetRawText(), options) ?? throw new JsonException($"missing required field '{name}'")
            : throw new JsonException($"missing required field '{name}'");

        string GetStr(string name) => root.GetProperty(name).GetString() ?? throw new JsonException($"missing required string '{name}'");
        int GetInt(string name) => root.GetProperty(name).GetInt32();
        bool GetBool(string name) => root.GetProperty(name).GetBoolean();

        string? GetStrOpt(string name) => root.TryGetProperty(name, out var p) && p.ValueKind != JsonValueKind.Null ? p.GetString() : null;
        int? GetIntOpt(string name) => root.TryGetProperty(name, out var p) && p.ValueKind != JsonValueKind.Null ? p.GetInt32() : null;
        bool? GetBoolOpt(string name) => root.TryGetProperty(name, out var p) && p.ValueKind != JsonValueKind.Null ? p.GetBoolean() : null;

        IReadOnlyList<WireAttachment> GetAttachments() => root.TryGetProperty("attachments", out var p) && p.ValueKind == JsonValueKind.Array
            ? JsonSerializer.Deserialize<List<WireAttachment>>(p.GetRawText(), options) ?? []
            : [];

        return type switch
        {
            "auth" => new BridgeBody.Auth(
                GetStr("token"),
                GetStrOpt("deviceName"),
                Get<ClientKind>("clientKind"),
                GetStr("clientId"),
                GetStr("installationId"),
                GetStr("deviceId")),

            "listSessions" => new BridgeBody.ListSessions(),
            "openSession" => new BridgeBody.OpenSession(GetStr("sessionId"), GetIntOpt("limit")),

            "loadOlderMessages" => new BridgeBody.LoadOlderMessages(
                GetStr("sessionId"),
                GetStr("beforeMessageId"),
                GetInt("limit")),

            "sendMessage" => new BridgeBody.SendMessage(GetStr("sessionId"), GetStr("text"), GetAttachments()),
            "newSession" => new BridgeBody.NewSession(GetStr("sessionId"), GetStr("text"), GetAttachments()),
            "interruptTurn" => new BridgeBody.InterruptTurn(GetStr("sessionId")),
            "authOk" => new BridgeBody.AuthOk(GetStrOpt("hostDisplayName")),
            "authFailed" => new BridgeBody.AuthFailed(GetStr("reason")),
            "versionMismatch" => new BridgeBody.VersionMismatch(GetInt("serverVersion")),
            "sessionsSnapshot" => new BridgeBody.SessionsSnapshot(GetReq<List<WireSession>>("sessions")),
            "sessionUpdated" => new BridgeBody.SessionUpdated(GetReq<WireSession>("session")),

            "messagesSnapshot" => new BridgeBody.MessagesSnapshot(
                GetStr("sessionId"),
                GetReq<List<WireMessage>>("messages"),
                GetBoolOpt("hasMore")),

            "messagesPage" => new BridgeBody.MessagesPage(
                GetStr("sessionId"),
                GetReq<List<WireMessage>>("messages"),
                GetBool("hasMore")),

            "messageAppended" => new BridgeBody.MessageAppended(GetStr("sessionId"), GetReq<WireMessage>("message")),

            "messageStreaming" => new BridgeBody.MessageStreaming(
                GetStr("sessionId"),
                GetStr("messageId"),
                GetStr("content"),
                GetStr("reasoningText"),
                GetBool("finished")),

            "errorEvent" => new BridgeBody.ErrorEvent(GetStr("code"), GetStr("message")),
            "editPrompt" => new BridgeBody.EditPrompt(GetStr("sessionId"), GetStr("messageId"), GetStr("text")),
            "archiveSession" => new BridgeBody.ArchiveSession(GetStr("sessionId")),
            "unarchiveSession" => new BridgeBody.UnarchiveSession(GetStr("sessionId")),
            "pinSession" => new BridgeBody.PinSession(GetStr("sessionId")),
            "unpinSession" => new BridgeBody.UnpinSession(GetStr("sessionId")),
            "renameSession" => new BridgeBody.RenameSession(GetStr("sessionId"), GetStr("title")),
            "pairingStart" => new BridgeBody.PairingStart(),
            "listProjects" => new BridgeBody.ListProjects(),
            "pairingPayload" => new BridgeBody.PairingPayload(GetStr("qrJson"), GetStr("token"), GetStr("shortCode")),
            "projectsSnapshot" => new BridgeBody.ProjectsSnapshot(GetReq<List<WireProject>>("projects")),
            "readFile" => new BridgeBody.ReadFile(GetStr("path")),

            "fileSnapshot" => new BridgeBody.FileSnapshot(
                GetStr("path"),
                GetStrOpt("content"),
                GetBoolOpt("isMarkdown") ?? false,
                GetStrOpt("error")),

            "transcribeAudio" => new BridgeBody.TranscribeAudio(
                GetStr("requestId"),
                GetStr("audioBase64"),
                GetStr("mimeType"),
                GetStrOpt("language")),

            "transcriptionResult" => new BridgeBody.TranscriptionResult(
                GetStr("requestId"),
                GetStr("text"),
                GetStrOpt("errorMessage")),

            "requestAudio" => new BridgeBody.RequestAudio(GetStr("audioId")),

            "audioSnapshot" => new BridgeBody.AudioSnapshot(
                GetStr("audioId"),
                GetStrOpt("audioBase64"),
                GetStrOpt("mimeType"),
                GetStrOpt("errorMessage")),

            "requestGeneratedImage" => new BridgeBody.RequestGeneratedImage(GetStr("path")),

            "generatedImageSnapshot" => new BridgeBody.GeneratedImageSnapshot(
                GetStr("path"),
                GetStrOpt("dataBase64"),
                GetStrOpt("mimeType"),
                GetStrOpt("errorMessage")),

            "requestRolloutAttachment" => new BridgeBody.RequestRolloutAttachment(GetStr("attachmentId")),

            "rolloutAttachmentSnapshot" => new BridgeBody.RolloutAttachmentSnapshot(
                GetStr("attachmentId"),
                GetStrOpt("dataBase64"),
                GetStrOpt("mimeType"),
                GetStrOpt("errorMessage")),

            "bridgeState" => new BridgeBody.BridgeState(
                GetStr("state"),
                GetInt("chatCount"),
                GetStrOpt("message")),

            "requestRateLimits" => new BridgeBody.RequestRateLimits(),

            "rateLimitsSnapshot" => new BridgeBody.RateLimitsSnapshot(
                Get<WireRateLimitSnapshot>("rateLimits"),
                Get<Dictionary<string, WireRateLimitSnapshot>>("rateLimitsByLimitId") ?? new Dictionary<string, WireRateLimitSnapshot>()),

            "rateLimitsUpdated" => new BridgeBody.RateLimitsUpdated(
                Get<WireRateLimitSnapshot>("rateLimits"),
                Get<Dictionary<string, WireRateLimitSnapshot>>("rateLimitsByLimitId") ?? new Dictionary<string, WireRateLimitSnapshot>()),

            "requestClawJSServiceStatuses" => new BridgeBody.RequestClawJSServiceStatuses(),

            "clawJSServiceStatusesSnapshot" => new BridgeBody.ClawJSServiceStatusesSnapshot(
                GetReq<List<WireClawJSServiceSnapshot>>("services")),

            "clawJSServiceStatusUpdated" => new BridgeBody.ClawJSServiceStatusUpdated(
                GetReq<WireClawJSServiceSnapshot>("service")),

            "audioRegister" => new BridgeBody.AudioRegister(
                GetStr("requestId"),
                GetReq<WireAudioRegisterRequest>("request")),

            "audioAttachTranscript" => new BridgeBody.AudioAttachTranscript(
                GetStr("requestId"),
                GetStr("audioId"),
                GetReq<WireAudioAttachTranscriptInput>("transcript")),

            "audioGet" => new BridgeBody.AudioGet(
                GetStr("requestId"),
                GetStr("audioId"),
                GetStr("appId")),

            "audioGetBytes" => new BridgeBody.AudioGetBytes(
                GetStr("requestId"),
                GetStr("audioId"),
                GetStr("appId")),

            "audioList" => new BridgeBody.AudioList(
                GetStr("requestId"),
                GetReq<WireAudioListFilter>("filter")),

            "audioDelete" => new BridgeBody.AudioDelete(
                GetStr("requestId"),
                GetStr("audioId"),
                GetStr("appId")),

            "audioRegisterResult" => new BridgeBody.AudioRegisterResult(
                GetStr("requestId"),
                Get<WireAudioAssetWithTranscripts>("asset"),
                GetStrOpt("errorMessage")),

            "audioAttachTranscriptResult" => new BridgeBody.AudioAttachTranscriptResult(
                GetStr("requestId"),
                Get<WireAudioTranscript>("transcript"),
                GetStrOpt("errorMessage")),

            "audioGetResult" => new BridgeBody.AudioGetResult(
                GetStr("requestId"),
                Get<WireAudioAssetWithTranscripts>("asset"),
                GetStrOpt("errorMessage")),

            "audioBytesResult" => new BridgeBody.AudioBytesResult(
                GetStr("requestId"),
                GetStrOpt("audioBase64"),
                GetStrOpt("mimeType"),
                GetIntOpt("durationMs"),
                GetStrOpt("errorMessage")),

            "audioListResult" => new BridgeBody.AudioListResult(
                GetStr("requestId"),
                Get<WireAudioListResult>("list"),
                GetStrOpt("errorMessage")),

            "audioDeleteResult" => new BridgeBody.AudioDeleteResult(
                GetStr("requestId"),
                GetBool("deleted"),
                GetStrOpt("errorMessage")),

            _ => throw BridgeDecodingException.UnknownType(type),
        };
    }
}
