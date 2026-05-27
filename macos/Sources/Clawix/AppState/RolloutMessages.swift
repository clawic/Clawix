import ClawixCore

func rolloutChatMessages(from result: RolloutReader.ReadResult) -> [ChatMessage] {
    result.entries.map { e in
        ChatMessage(
            id: e.id,
            role: e.role == .user ? .user : .assistant,
            content: e.text,
            reasoningText: "",
            streamingFinished: true,
            timestamp: e.timestamp,
            workSummary: e.workSummary,
            timeline: e.timeline,
            attachments: e.attachments,
            goalOutcome: e.goalOutcome
        )
    }
}
