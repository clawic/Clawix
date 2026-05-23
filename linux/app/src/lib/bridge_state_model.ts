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

export function appendErrorMessage(
  bySession: Record<string, unknown>,
  sessionId: unknown,
  content: string
): Record<string, unknown> {
  const id = stringValue(sessionId);
  const trimmed = content.trim();
  if (!id || !trimmed) return bySession;

  return appendMessage(bySession, id, {
    id: `local-error-${Date.now()}`,
    role: "assistant",
    content: trimmed,
    isError: true,
    streamingFinished: true
  });
}

export function prependMessagesPage(
  bySession: Record<string, unknown>,
  sessionId: unknown,
  messages: unknown
): Record<string, unknown> {
  const id = stringValue(sessionId);
  if (!id || !Array.isArray(messages)) return bySession;

  const current = Array.isArray(bySession[id]) ? bySession[id] as unknown[] : [];
  const seen = new Set(messages.filter(isRecord).map((message) => stringValue(message.id)).filter(Boolean));
  const tail = current.filter((message) => !isRecord(message) || !seen.has(stringValue(message.id)));
  return { ...bySession, [id]: [...messages, ...tail] };
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

export function editPromptMessage(
  bySession: Record<string, unknown>,
  sessionId: string,
  messageId: string,
  content: string
): Record<string, unknown> {
  const current = Array.isArray(bySession[sessionId]) ? bySession[sessionId] as unknown[] : [];
  const index = current.findIndex((message) => isRecord(message) && message.id === messageId);
  if (index < 0) return bySession;

  const edited = current.slice(0, index + 1);
  const target = edited[index];
  edited[index] = isRecord(target) ? { ...target, content } : target;
  return { ...bySession, [sessionId]: edited };
}

export function updateSessionFlags(
  sessions: unknown[],
  sessionId: string,
  flags: { isPinned?: boolean; isArchived?: boolean; pinned?: boolean; archived?: boolean }
): unknown[] {
  return sessions.map((session) => {
    if (!isRecord(session) || session.id !== sessionId) return session;
    return { ...session, ...flags };
  });
}

export function updateSessionTitle(sessions: unknown[], sessionId: string, title: string): unknown[] {
  return sessions.map((session) => {
    if (!isRecord(session) || session.id !== sessionId) return session;
    return { ...session, title };
  });
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
