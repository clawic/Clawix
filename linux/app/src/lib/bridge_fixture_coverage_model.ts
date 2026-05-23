export const supportedLinuxBridgeV1FixtureTypes = [
  "auth",
  "listSessions",
  "openSession",
  "loadOlderMessages",
  "sendMessage",
  "newSession",
  "interruptTurn",
  "authOk",
  "authFailed",
  "versionMismatch",
  "sessionsSnapshot",
  "sessionUpdated",
  "messagesSnapshot",
  "messagesPage",
  "messageAppended",
  "messageStreaming",
  "errorEvent",
  "editPrompt",
  "archiveSession",
  "unarchiveSession",
  "pinSession",
  "unpinSession",
  "renameSession",
  "pairingStart",
  "listProjects",
  "readFile",
  "pairingPayload",
  "projectsSnapshot",
  "fileSnapshot",
  "requestAudio",
  "audioGetBytes",
  "audioSnapshot",
  "audioBytesResult",
  "audioGet",
  "audioRegister",
  "audioAttachTranscript",
  "audioList",
  "audioDelete",
  "audioGetResult",
  "audioRegisterResult",
  "audioAttachTranscriptResult",
  "audioListResult",
  "audioDeleteResult",
  "requestGeneratedImage",
  "generatedImageSnapshot",
  "requestRolloutAttachment",
  "rolloutAttachmentSnapshot",
  "bridgeState",
  "requestRateLimits",
  "rateLimitsSnapshot",
  "rateLimitsUpdated",
  "requestClawJSServiceStatuses",
  "clawJSServiceStatusesSnapshot",
  "clawJSServiceStatusUpdated"
] as const;

export const pendingLinuxBridgeV1FixtureTypes = [
  "transcribeAudio",
  "transcriptionResult",
] as const;

export interface BridgeFixtureCoverage {
  supported: string[];
  pending: string[];
  unknown: string[];
  retiredClassifications: string[];
}

export function bridgeV1FixtureCoverage(fixtureTypes: string[]): BridgeFixtureCoverage {
  const fixtureSet = new Set(fixtureTypes);
  const supportedSet = new Set<string>(supportedLinuxBridgeV1FixtureTypes);
  const pendingSet = new Set<string>(pendingLinuxBridgeV1FixtureTypes);
  const classifiedSet = new Set<string>([...supportedSet, ...pendingSet]);

  return {
    supported: sortedIntersection(fixtureSet, supportedSet),
    pending: sortedIntersection(fixtureSet, pendingSet),
    unknown: [...fixtureSet].filter((type) => !classifiedSet.has(type)).sort(),
    retiredClassifications: [...classifiedSet].filter((type) => !fixtureSet.has(type)).sort()
  };
}

function sortedIntersection(left: Set<string>, right: Set<string>): string[] {
  return [...left].filter((type) => right.has(type)).sort();
}
