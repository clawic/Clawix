package com.example.clawix.android.bridge

import com.example.clawix.android.core.BridgeRuntimeState
import com.example.clawix.android.core.SnapshotCache
import com.example.clawix.android.core.WireSession
import com.example.clawix.android.core.WireMessage
import com.example.clawix.android.core.WireProject
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Single source of truth for chat / message / connection state on the
 * client. Mirrors iOS `BridgeStore`.
 *
 * The public state is split by invalidation boundary. `summaryState` is
 * safe for chat lists, project surfaces, and attachment shells; streaming
 * transcript churn is isolated in `transcriptState`. `state` remains as a
 * compatibility projection for callers that genuinely need both.
 */
class BridgeStore(
    private val scope: CoroutineScope,
    private val snapshotCache: SnapshotCache,
    private val unreadCache: UnreadChatTracker,
    private val projectLabelsCache: ProjectLabelStore,
) {
    private val _summaryState = MutableStateFlow(BridgeSummaryState())
    val summaryState: StateFlow<BridgeSummaryState> = _summaryState.asStateFlow()

    private val _transcriptState = MutableStateFlow(BridgeTranscriptState())
    val transcriptState: StateFlow<BridgeTranscriptState> = _transcriptState.asStateFlow()

    val state: StateFlow<BridgeState> = combine(summaryState, transcriptState) { summary, transcript ->
        summary.withTranscript(transcript)
    }.stateIn(scope, SharingStarted.Eagerly, BridgeState())

    private val cacheMutex = Mutex()

    /** Hydrate from disk before the WebSocket connects. Idempotent. */
    fun hydrateFromCache() {
        val payload = snapshotCache.load() ?: return
        _summaryState.update {
            it.copy(
                chats = payload.sessions.take(maxSessionCount),
            )
        }
        _transcriptState.update {
            it.copy(messagesBySession = trimMessagesBySession(payload.messagesBySession, payload.sessions.map { it.id }.toSet()))
        }
    }

    fun setConnection(state: ConnectionState) {
        _summaryState.update { it.copy(connection = state) }
    }

    fun setRuntime(state: BridgeRuntimeState) {
        _summaryState.update { it.copy(runtime = state) }
    }

    fun applySessionsSnapshot(chats: List<WireSession>) {
        val trimmedChats = chats.take(maxSessionCount)
        _summaryState.update { current ->
            current.copy(chats = trimmedChats)
        }
        _transcriptState.update { current ->
            current.copy(messagesBySession = trimMessagesBySession(current.messagesBySession, trimmedChats.map { it.id }.toSet()))
        }
        persistAsync()
    }

    fun applySessionUpdated(chat: WireSession) {
        _summaryState.update { current ->
            val existing = current.chats.toMutableList()
            val idx = existing.indexOfFirst { it.id == chat.id }
            if (idx >= 0) existing[idx] = chat else existing.add(0, chat)
            current.copy(chats = existing.take(maxSessionCount))
        }
        persistAsync()
    }

    /**
     * Optimistic mutation. The UI updates immediately while the daemon
     * confirms with a `sessionUpdated` frame that overwrites the entire chat
     * record. Mirrors how iOS `BridgeStore` patches `WireSession.isPinned`
     * locally before the round-trip resolves.
     */
    private inline fun mutateChat(chatId: String, transform: (WireSession) -> WireSession) {
        _summaryState.update { current ->
            val list = current.chats.toMutableList()
            val idx = list.indexOfFirst { it.id == chatId }
            if (idx < 0) return@update current
            list[idx] = transform(list[idx])
            current.copy(chats = list.take(maxSessionCount))
        }
        persistAsync()
    }

    fun applyOptimisticPin(chatId: String, pinned: Boolean) {
        mutateChat(chatId) { it.copy(isPinned = pinned) }
    }

    fun applyOptimisticArchive(chatId: String, archived: Boolean) {
        mutateChat(chatId) { it.copy(isArchived = archived) }
    }

    fun applyOptimisticRename(chatId: String, title: String) {
        mutateChat(chatId) { it.copy(title = title) }
    }

    fun applyMessagesSnapshot(sessionId: String, messages: List<WireMessage>, hasMore: Boolean?) {
        _transcriptState.update { current ->
            val map = current.messagesBySession.toMutableMap()
            map[sessionId] = messages.takeLast(maxMessagesPerSession)
            val more = current.hasMoreBySession.toMutableMap()
            if (hasMore != null) more[sessionId] = hasMore else more.remove(sessionId)
            current.copy(messagesBySession = trimMessagesBySession(map), hasMoreBySession = more)
        }
        persistAsync()
    }

    fun applyMessagesPage(sessionId: String, older: List<WireMessage>, hasMore: Boolean) {
        _transcriptState.update { current ->
            val existing = current.messagesBySession[sessionId] ?: emptyList()
            val merged = (older + existing).distinctBy { it.id }.takeLast(maxMessagesPerSession)
            val map = current.messagesBySession.toMutableMap().apply { put(sessionId, merged) }
            val more = current.hasMoreBySession.toMutableMap().apply { put(sessionId, hasMore) }
            current.copy(messagesBySession = trimMessagesBySession(map), hasMoreBySession = more)
        }
        persistAsync()
    }

    fun applyMessageAppended(sessionId: String, message: WireMessage) {
        _transcriptState.update { current ->
            val existing = current.messagesBySession[sessionId] ?: emptyList()
            val map = current.messagesBySession.toMutableMap().apply {
                put(sessionId, (existing + message).takeLast(maxMessagesPerSession))
            }
            current.copy(messagesBySession = trimMessagesBySession(map))
        }
        if (message.role == com.example.clawix.android.core.WireRole.assistant && _summaryState.value.openSessionId != sessionId) {
            unreadCache.mark(sessionId)
        }
        persistAsync()
    }

    /**
     * Apply a batch of pending stream updates from StreamCoalescer.
     * Each entry replaces the cumulative content of the matching message.
     * If the message doesn't exist yet (rare race) we ignore the update;
     * a subsequent `messageAppended` will land it.
     */
    fun applyStreamingBatch(batch: Map<String, PendingStreamUpdate>) {
        if (batch.isEmpty()) return
        _transcriptState.update { current ->
            val updatedChats = current.messagesBySession.toMutableMap()
            for ((messageId, upd) in batch) {
                val list = updatedChats[upd.sessionId] ?: continue
                val idx = list.indexOfFirst { it.id == messageId }
                if (idx < 0) continue
                val newList = list.toMutableList()
                val existing = newList[idx]
                newList[idx] = existing.copy(
                    content = upd.content,
                    reasoningText = upd.reasoningText,
                    streamingFinished = upd.finished,
                )
                updatedChats[upd.sessionId] = newList
            }
            current.copy(messagesBySession = trimMessagesBySession(updatedChats))
        }
    }

    fun applyProjects(projects: List<WireProject>) {
        _summaryState.update { it.copy(projects = projects) }
        for (p in projects) {
            projectLabelsCache.put(p.id, p.title)
        }
    }

    fun applyFileSnapshot(snapshot: FileSnapshotState) {
        _summaryState.update {
            val map = it.fileSnapshots.toMutableMap().apply { put(snapshot.path, snapshot) }
            it.copy(fileSnapshots = trimMapToLast(map, maxFileSnapshots))
        }
    }

    fun applyGeneratedImage(image: GeneratedImageState) {
        _summaryState.update {
            val map = it.generatedImages.toMutableMap().apply { put(image.path, image) }
            it.copy(generatedImages = trimMapToLast(map, maxGeneratedImages))
        }
    }

    fun setOpenSession(id: String?) {
        _summaryState.update { it.copy(openSessionId = id) }
        if (id != null) unreadCache.clear(id)
    }

    fun registerPendingNewSession(sessionId: String) {
        _summaryState.update {
            it.copy(pendingNewSessions = (it.pendingNewSessions + sessionId).toList().takeLast(maxPendingSessions).toSet())
        }
    }

    fun unregisterPendingNewSession(sessionId: String) {
        _summaryState.update {
            it.copy(pendingNewSessions = it.pendingNewSessions - sessionId)
        }
    }

    fun registerPendingTranscription(requestId: String, chatId: String) {
        _summaryState.update {
            it.copy(pendingTranscriptions = trimMapToLast(it.pendingTranscriptions + (requestId to chatId), maxPendingTranscriptions))
        }
    }

    fun applyTranscriptionResult(requestId: String, text: String) {
        _summaryState.update {
            val pending = it.pendingTranscriptions - requestId
            val results = trimMapToLast(it.transcriptionResults + (requestId to text), maxTranscriptionResults)
            it.copy(pendingTranscriptions = pending, transcriptionResults = results)
        }
    }

    fun consumeTranscriptionResult(requestId: String): String? {
        val text = _summaryState.value.transcriptionResults[requestId] ?: return null
        _summaryState.update {
            it.copy(transcriptionResults = it.transcriptionResults - requestId)
        }
        return text
    }

    private fun persistAsync() {
        scope.launch(Dispatchers.IO) {
            cacheMutex.withLock {
                snapshotCache.save(_summaryState.value.chats, _transcriptState.value.messagesBySession)
            }
        }
    }

    private fun trimMessagesBySession(
        messages: Map<String, List<WireMessage>>,
        keepSessionIds: Set<String>? = null
    ): Map<String, List<WireMessage>> {
        return messages
            .filterKeys { keepSessionIds == null || it in keepSessionIds }
            .entries
            .toList()
            .takeLast(maxRetainedMessageSessions)
            .associate { (sessionId, list) -> sessionId to list.takeLast(maxMessagesPerSession) }
    }

    private fun <K, V> trimMapToLast(map: Map<K, V>, limit: Int): Map<K, V> {
        if (map.size <= limit) return map
        return map.entries.toList().takeLast(limit).associate { (key, value) -> key to value }
    }

    companion object {
        private const val maxSessionCount = 100
        private const val maxRetainedMessageSessions = 32
        private const val maxMessagesPerSession = 160
        private const val maxFileSnapshots = 20
        private const val maxGeneratedImages = 12
        private const val maxPendingSessions = 20
        private const val maxPendingTranscriptions = 20
        private const val maxTranscriptionResults = 20
    }
}
