type UnknownRecord = Record<string, unknown>;

export function upsertSession(sessions: unknown[], session: unknown): unknown[] {
  if (!isRecord(session)) return sessions;
  const id = stringValue(session.id);
  if (!id) return sessions;

  const index = sessions.findIndex((item) => isRecord(item) && item.id === id);
  if (index < 0) return [session, ...sessions];

  const next = sessions.slice();
  next[index] = { ...(isRecord(next[index]) ? next[index] : {}), ...session };
  return next;
}

export function appendMessage(
  bySession: Record<string, unknown>,
  sessionId: unknown,
  message: unknown
): Record<string, unknown> {
  const id = stringValue(sessionId);
  if (!id || !isRecord(message)) return bySession;

  const current = Array.isArray(bySession[id]) ? bySession[id] as unknown[] : [];
  return { ...bySession, [id]: [...current, message] };
}

export function applyStreamingMessage(
  bySession: Record<string, unknown>,
  frame: UnknownRecord
): Record<string, unknown> {
  const sessionId = stringValue(frame.sessionId);
  const messageId = stringValue(frame.messageId);
  if (!sessionId || !messageId) return bySession;

  const current = Array.isArray(bySession[sessionId]) ? bySession[sessionId] as UnknownRecord[] : [];
  let found = false;
  const updated = current.map((message) => {
    if (!isRecord(message) || message.id !== messageId) return message;
    found = true;
    return streamingMessage(message, frame);
  });

  if (!found) {
    updated.push(streamingMessage({ id: messageId, role: "assistant", content: "" }, frame));
  }

  return { ...bySession, [sessionId]: updated };
}

function streamingMessage(message: UnknownRecord, frame: UnknownRecord): UnknownRecord {
  return {
    ...message,
    content: frame.content,
    reasoningText: frame.reasoningText,
    streamingFinished: frame.finished
  };
}

function isRecord(value: unknown): value is UnknownRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value : null;
}
