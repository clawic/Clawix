package com.example.clawix.android

import com.example.clawix.android.bridge.BridgeStore
import com.example.clawix.android.bridge.PendingStreamUpdate
import com.example.clawix.android.bridge.ProjectLabelStore
import com.example.clawix.android.bridge.UnreadChatTracker
import com.example.clawix.android.core.SnapshotCache
import com.example.clawix.android.core.WireMessage
import com.example.clawix.android.core.WireRole
import com.example.clawix.android.core.WireSession
import java.nio.file.Files
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class BridgeStoreInvalidationTest {

    @Test
    fun streamingBatchUpdatesTranscriptWithoutEmittingSummaryState() = runTest {
        val store = bridgeStore(backgroundScope)
        store.applySessionsSnapshot(listOf(session("s1")))
        store.applyMessagesSnapshot("s1", listOf(message("m1", "")), hasMore = false)

        var summaryEmissions = 0
        val job = backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            store.summaryState.drop(1).collect { summaryEmissions += 1 }
        }
        runCurrent()

        store.applyStreamingBatch(
            mapOf(
                "m1" to PendingStreamUpdate(
                    sessionId = "s1",
                    messageId = "m1",
                    content = "partial",
                    reasoningText = "thinking",
                    finished = false,
                )
            )
        )
        runCurrent()

        assertEquals(0, summaryEmissions)
        assertEquals("partial", store.transcriptState.value.messagesBySession["s1"]?.first()?.content)
        assertEquals("thinking", store.transcriptState.value.messagesBySession["s1"]?.first()?.reasoningText)

        job.cancel()
    }

    @Test
    fun summaryMutationsDoNotEmitTranscriptState() = runTest {
        val store = bridgeStore(backgroundScope)
        store.applySessionsSnapshot(listOf(session("s1")))
        store.applyMessagesSnapshot("s1", listOf(message("m1", "stable")), hasMore = false)

        var transcriptEmissions = 0
        val job = backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            store.transcriptState.drop(1).collect { transcriptEmissions += 1 }
        }
        runCurrent()

        store.applySessionUpdated(session("s1", title = "Renamed"))
        runCurrent()

        assertEquals(0, transcriptEmissions)
        assertEquals("Renamed", store.summaryState.value.chats.first().title)
        assertEquals("stable", store.transcriptState.value.messagesBySession["s1"]?.first()?.content)

        job.cancel()
    }

    @Test
    fun compatibilityStateProjectsBothBoundaries() = runTest {
        val store = bridgeStore(backgroundScope)
        store.applySessionsSnapshot(listOf(session("s1")))
        store.applyMessagesSnapshot("s1", listOf(message("m1", "hello")), hasMore = true)
        runCurrent()

        val combined = store.state.value
        assertEquals("s1", combined.chats.first().id)
        assertEquals("hello", combined.messagesBySession["s1"]?.first()?.content)
        assertTrue(combined.hasMoreBySession["s1"] == true)
    }

    private fun bridgeStore(scope: CoroutineScope): BridgeStore =
        BridgeStore(
            scope = scope,
            snapshotCache = SnapshotCache(Files.createTempDirectory("clawix-android-store-test").toFile()),
            unreadCache = FakeUnreadChatTracker(),
            projectLabelsCache = FakeProjectLabelStore(),
        )

    private fun session(id: String, title: String = id): WireSession =
        WireSession(
            id = id,
            title = title,
            createdAt = Instant.parse("2026-05-01T12:00:00Z"),
        )

    private fun message(id: String, content: String): WireMessage =
        WireMessage(
            id = id,
            role = WireRole.assistant,
            content = content,
            timestamp = Instant.parse("2026-05-01T12:00:01Z"),
        )

    private class FakeUnreadChatTracker : UnreadChatTracker {
        private var ids: Set<String> = emptySet()

        override fun load(): Set<String> = ids

        override fun save(ids: Set<String>) {
            this.ids = ids
        }

        override fun mark(id: String) {
            ids = ids + id
        }

        override fun clear(id: String) {
            ids = ids - id
        }

        override fun clearAll() {
            ids = emptySet()
        }
    }

    private class FakeProjectLabelStore : ProjectLabelStore {
        private val labels = mutableMapOf<String, String>()

        override fun get(id: String): String? = labels[id]

        override fun put(id: String, label: String) {
            labels[id] = label
        }

        override fun all(): Map<String, String> = labels.toMap()

        override fun clear() {
            labels.clear()
        }
    }
}
