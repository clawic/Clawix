export interface AudioCatalogState {
  itemsById: Record<string, unknown>;
  list: unknown[];
  total: number | null;
  errorsByRequestId: Record<string, string>;
}

export const emptyAudioCatalogState: AudioCatalogState = {
  itemsById: {},
  list: [],
  total: null,
  errorsByRequestId: {}
};

export function applyAudioGetResult(state: AudioCatalogState, frame: unknown): AudioCatalogState {
  if (!isRecord(frame) || typeof frame.requestId !== "string") return state;
  if (typeof frame.errorMessage === "string") return withError(state, frame.requestId, frame.errorMessage);

  const item = frame.asset;
  const id = audioCatalogItemId(item);
  if (!id) return state;

  return {
    ...state,
    itemsById: { ...state.itemsById, [id]: item },
    errorsByRequestId: withoutKey(state.errorsByRequestId, frame.requestId)
  };
}

export function applyAudioAttachTranscriptResult(state: AudioCatalogState, frame: unknown): AudioCatalogState {
  if (!isRecord(frame) || typeof frame.requestId !== "string") return state;
  if (typeof frame.errorMessage === "string") return withError(state, frame.requestId, frame.errorMessage);
  if (!isRecord(frame.transcript) || typeof frame.transcript.audioId !== "string") return state;

  const audioId = frame.transcript.audioId;
  const current = state.itemsById[audioId];
  if (!isRecord(current)) return state;

  const nextItem = withTranscript(current, frame.transcript);
  return {
    ...state,
    itemsById: { ...state.itemsById, [audioId]: nextItem },
    list: state.list.map((item) => (audioCatalogItemId(item) === audioId ? nextItem : item)),
    errorsByRequestId: withoutKey(state.errorsByRequestId, frame.requestId)
  };
}

export function applyAudioListResult(state: AudioCatalogState, frame: unknown): AudioCatalogState {
  if (!isRecord(frame) || typeof frame.requestId !== "string") return state;
  if (typeof frame.errorMessage === "string") return withError(state, frame.requestId, frame.errorMessage);
  if (!isRecord(frame.list) || !Array.isArray(frame.list.items)) return state;

  const itemsById = { ...state.itemsById };
  for (const item of frame.list.items) {
    const id = audioCatalogItemId(item);
    if (id) itemsById[id] = item;
  }

  return {
    ...state,
    itemsById,
    list: frame.list.items,
    total: typeof frame.list.total === "number" ? frame.list.total : frame.list.items.length,
    errorsByRequestId: withoutKey(state.errorsByRequestId, frame.requestId)
  };
}

export function applyAudioDeleteResult(
  state: AudioCatalogState,
  frame: unknown,
  requestAudioIds: Record<string, string>
): AudioCatalogState {
  if (!isRecord(frame) || typeof frame.requestId !== "string") return state;
  if (typeof frame.errorMessage === "string") return withError(state, frame.requestId, frame.errorMessage);
  const audioId = requestAudioIds[frame.requestId];
  if (!audioId || frame.deleted !== true) return state;

  return {
    ...state,
    itemsById: withoutKey(state.itemsById, audioId),
    list: state.list.filter((item) => audioCatalogItemId(item) !== audioId),
    total: typeof state.total === "number" ? Math.max(0, state.total - 1) : state.total,
    errorsByRequestId: withoutKey(state.errorsByRequestId, frame.requestId)
  };
}

export function audioCatalogItemId(item: unknown): string | null {
  if (!isRecord(item)) return null;
  if (isRecord(item.asset) && typeof item.asset.id === "string") return item.asset.id;
  if (isRecord(item.asset) && isRecord(item.asset.asset) && typeof item.asset.asset.id === "string") return item.asset.asset.id;
  return null;
}

function withError(state: AudioCatalogState, requestId: string, message: string): AudioCatalogState {
  return {
    ...state,
    errorsByRequestId: { ...state.errorsByRequestId, [requestId]: message }
  };
}

function withTranscript(item: Record<string, unknown>, transcript: Record<string, unknown>): Record<string, unknown> {
  const transcripts = Array.isArray(item.transcripts) ? item.transcripts : [];
  const transcriptId = typeof transcript.id === "string" ? transcript.id : null;
  const nextTranscripts = transcriptId
    ? [...transcripts.filter((entry) => !isRecord(entry) || entry.id !== transcriptId), transcript]
    : [...transcripts, transcript];
  return { ...item, transcripts: nextTranscripts };
}

function withoutKey<T>(record: Record<string, T>, key: string): Record<string, T> {
  const next = { ...record };
  delete next[key];
  return next;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
