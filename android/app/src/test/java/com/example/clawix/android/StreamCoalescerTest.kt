package com.example.clawix.android

import com.example.clawix.android.bridge.PendingStreamUpdate
import com.example.clawix.android.bridge.StreamCoalescer
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class StreamCoalescerTest {

    @Test
    fun coalescesMultipleFramesForSameMessageWithLatestContent() = runTest {
        val flushed = mutableListOf<Map<String, PendingStreamUpdate>>()
        val coalescer = StreamCoalescer(
            scope = backgroundScope,
            coalesceMs = 80,
            flush = { flushed.add(it) },
        )

        coalescer.enqueue(stream("m1", "partial 1", "reason 1", finished = false))
        coalescer.enqueue(stream("m1", "partial 2", "reason 2", finished = false))
        runCurrent()

        assertTrue(flushed.isEmpty())

        advanceTimeBy(80)
        runCurrent()

        assertEquals(1, flushed.size)
        assertEquals("partial 2", flushed.single()["m1"]?.content)
        assertEquals("reason 2", flushed.single()["m1"]?.reasoningText)
    }

    @Test
    fun finishedFrameFlushesImmediately() = runTest {
        val flushed = mutableListOf<Map<String, PendingStreamUpdate>>()
        val coalescer = StreamCoalescer(
            scope = backgroundScope,
            coalesceMs = 80,
            flush = { flushed.add(it) },
        )

        coalescer.enqueue(stream("m1", "done", "", finished = true))
        runCurrent()

        assertEquals(1, flushed.size)
        assertEquals("done", flushed.single()["m1"]?.content)
        assertTrue(flushed.single()["m1"]?.finished == true)
    }

    private fun stream(
        messageId: String,
        content: String,
        reasoning: String,
        finished: Boolean,
    ): PendingStreamUpdate =
        PendingStreamUpdate(
            sessionId = "s1",
            messageId = messageId,
            content = content,
            reasoningText = reasoning,
            finished = finished,
        )
}
