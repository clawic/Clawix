package com.example.clawix.android.chatdetail

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.clawix.android.AppContainer
import com.example.clawix.android.core.WireAttachment
import com.example.clawix.android.core.WireMessage
import com.example.clawix.android.core.WireSession
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn

data class ChatDetailUi(
    val chat: WireSession?,
    val messages: List<WireMessage>,
    val hasMore: Boolean,
    val isStreaming: Boolean,
)

class ChatDetailViewModel(
    private val container: AppContainer,
    private val sessionId: String,
) : ViewModel() {

    val ui: StateFlow<ChatDetailUi> = combine(
        container.bridgeStore.summaryState,
        container.bridgeStore.transcriptState,
    ) { summary, transcript ->
        val chat = summary.chats.firstOrNull { it.id == sessionId }
        val messages = transcript.messagesBySession[sessionId] ?: emptyList()
        val hasMore = transcript.hasMoreBySession[sessionId] ?: false
        val streaming = messages.any { !it.streamingFinished && it.role == com.example.clawix.android.core.WireRole.assistant }
        ChatDetailUi(chat, messages, hasMore, streaming)
    }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), ChatDetailUi(null, emptyList(), false, false))

    fun open() {
        container.bridgeStore.setOpenSession(sessionId)
        container.bridgeClient.openSession(sessionId)
    }

    fun close() {
        container.bridgeStore.setOpenSession(null)
        container.bridgeClient.closeSession()
    }

    fun loadOlder(beforeMessageId: String) {
        container.bridgeClient.loadOlderMessages(sessionId, beforeMessageId)
    }

    fun sendMessage(text: String, attachments: List<WireAttachment> = emptyList()) {
        if (sessionId in (container.bridgeStore.summaryState.value.pendingNewSessions)) {
            container.bridgeClient.newSession(sessionId, text, attachments)
            container.bridgeStore.unregisterPendingNewSession(sessionId)
        } else {
            container.bridgeClient.sendMessage(sessionId, text, attachments)
        }
    }

    fun stop() {
        container.bridgeClient.interruptTurn(sessionId)
    }

    fun togglePin() {
        val chat = container.bridgeStore.summaryState.value.chats.firstOrNull { it.id == sessionId } ?: return
        if (chat.isPinned) container.bridgeClient.unpinSession(sessionId)
        else container.bridgeClient.pinSession(sessionId)
    }

    fun toggleArchive() {
        val chat = container.bridgeStore.summaryState.value.chats.firstOrNull { it.id == sessionId } ?: return
        if (chat.isArchived) container.bridgeClient.unarchiveSession(sessionId)
        else container.bridgeClient.archiveSession(sessionId)
    }

    fun rename(newTitle: String) {
        val trimmed = newTitle.trim()
        if (trimmed.isEmpty()) return
        container.bridgeClient.renameSession(sessionId, trimmed)
    }
}
