package com.example.clawix.android.core

import kotlinx.serialization.json.JsonObject

internal object BridgeFrameValidation {
    private val topLevelKeys = setOf("schemaVersion", "type")

    private val allowedPayloadKeys: Map<String, Set<String>> = mapOf(
        "auth" to setOf("token", "deviceName", "clientKind", "clientId", "installationId", "deviceId"),
        "listSessions" to emptySet(),
        "openSession" to setOf("sessionId", "limit"),
        "loadOlderMessages" to setOf("sessionId", "beforeMessageId", "limit"),
        "sendMessage" to setOf("sessionId", "text", "attachments"),
        "newSession" to setOf("sessionId", "text", "attachments"),
        "interruptTurn" to setOf("sessionId"),
        "authOk" to setOf("hostDisplayName"),
        "authFailed" to setOf("reason"),
        "versionMismatch" to setOf("serverVersion"),
        "sessionsSnapshot" to setOf("sessions"),
        "sessionUpdated" to setOf("session"),
        "messagesSnapshot" to setOf("sessionId", "messages", "hasMore"),
        "messagesPage" to setOf("sessionId", "messages", "hasMore"),
        "messageAppended" to setOf("sessionId", "message"),
        "messageStreaming" to setOf("sessionId", "messageId", "content", "reasoningText", "finished"),
        "errorEvent" to setOf("code", "message"),
        "editPrompt" to setOf("sessionId", "messageId", "text"),
        "archiveSession" to setOf("sessionId"),
        "unarchiveSession" to setOf("sessionId"),
        "pinSession" to setOf("sessionId"),
        "unpinSession" to setOf("sessionId"),
        "renameSession" to setOf("sessionId", "title"),
        "pairingStart" to emptySet(),
        "listProjects" to emptySet(),
        "readFile" to setOf("path"),
        "pairingPayload" to setOf("qrJson", "token", "shortCode"),
        "projectsSnapshot" to setOf("projects"),
        "fileSnapshot" to setOf("path", "content", "isMarkdown", "error"),
        "transcribeAudio" to setOf("requestId", "audioBase64", "mimeType", "language"),
        "transcriptionResult" to setOf("requestId", "text", "errorMessage"),
        "requestAudio" to setOf("audioId"),
        "audioSnapshot" to setOf("audioId", "audioBase64", "mimeType", "errorMessage"),
        "requestGeneratedImage" to setOf("path"),
        "generatedImageSnapshot" to setOf("path", "dataBase64", "mimeType", "errorMessage"),
        "requestRolloutAttachment" to setOf("attachmentId"),
        "rolloutAttachmentSnapshot" to setOf("attachmentId", "dataBase64", "mimeType", "errorMessage"),
        "bridgeState" to setOf("state", "chatCount", "message"),
        "requestRateLimits" to emptySet(),
        "rateLimitsSnapshot" to setOf("rateLimits", "rateLimitsByLimitId"),
        "rateLimitsUpdated" to setOf("rateLimits", "rateLimitsByLimitId"),
        "requestClawJSServiceStatuses" to emptySet(),
        "clawJSServiceStatusesSnapshot" to setOf("services"),
        "clawJSServiceStatusUpdated" to setOf("service"),
        "audioRegister" to setOf("requestId", "request"),
        "audioAttachTranscript" to setOf("requestId", "audioId", "transcript"),
        "audioGet" to setOf("requestId", "audioId", "appId"),
        "audioGetBytes" to setOf("requestId", "audioId", "appId"),
        "audioList" to setOf("requestId", "filter"),
        "audioDelete" to setOf("requestId", "audioId", "appId"),
        "audioRegisterResult" to setOf("requestId", "asset", "errorMessage"),
        "audioAttachTranscriptResult" to setOf("requestId", "transcript", "errorMessage"),
        "audioGetResult" to setOf("requestId", "asset", "errorMessage"),
        "audioBytesResult" to setOf("requestId", "audioBase64", "mimeType", "durationMs", "errorMessage"),
        "audioListResult" to setOf("requestId", "list", "errorMessage"),
        "audioDeleteResult" to setOf("requestId", "deleted", "errorMessage"),
    )

    fun validateTopLevel(type: String, obj: JsonObject) {
        val payloadKeys = allowedPayloadKeys[type] ?: error("unknown frame type $type")
        val allowed = topLevelKeys + payloadKeys
        val extra = obj.keys.firstOrNull { it !in allowed }
        require(extra == null) { "unexpected field for $type: $extra" }
    }
}
