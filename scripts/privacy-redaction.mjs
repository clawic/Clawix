const SECRET_PATTERNS = [
  {
    category: "codex_session",
    description: "private Codex session or goal path",
    pattern: /(?:~|\/[A-Za-z0-9._-]+|\/Users\/[A-Za-z0-9._-]+)\/\.codex\/(?:sessions|goals)\b[^\s"'`)},\]]*/g,
    replacement: "<redacted:codex-session>",
  },
  {
    category: "codex_rollout_id",
    description: "private Codex rollout session id",
    pattern: /\brollout-\d{4}-\d{2}-\d{2}T\d{2}[-:]\d{2}[-:]\d{2}(?:-\d{3})?-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jsonl\b/gi,
    replacement: "<redacted:codex-session>",
  },
  {
    category: "codex_record_id",
    description: "private Codex conversation or plan id",
    pattern: /\b019e[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?:-plan)?\b/gi,
    replacement: "<redacted:codex-id>",
  },
  {
    category: "private_path",
    description: "private filesystem path",
    pattern: /(?:\/Users\/(?!example(?:\/|\b)|demo(?:\/|\b)|me(?:\/|\b)|tester(?:\/|\b)|alice(?:\/|\b)|person(?:\/|\b)|private(?:\/|\b)|<redacted>(?:\/|\b))[A-Za-z0-9._-]+|~\/|[A-Z]:\\)[^\s"'`)},\]]*/g,
    replacement: "<redacted:path>",
  },
  {
    category: "file_url",
    description: "file URL",
    pattern: /\bfile:\/\/[^\s"'`)},\]]+/gi,
    replacement: "<redacted:file-url>",
  },
  {
    category: "private_key",
    description: "private key material",
    pattern: /-----BEGIN [A-Z ]+PRIVATE KEY-----(?:[\s\S]|\\n)*?-----END [A-Z ]+PRIVATE KEY-----/g,
    replacement: "<redacted:private-key>",
  },
  {
    category: "api_key",
    description: "raw API key",
    pattern: /\b(?:sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16})\b/g,
    replacement: "<redacted:secret>",
  },
  {
    category: "bearer_token",
    description: "bearer token",
    pattern: /\bBearer\s+[A-Za-z0-9._~+/=-]{10,}\b/gi,
    replacement: "Bearer <redacted:secret>",
  },
  {
    category: "secret_uri",
    description: "raw secret reference",
    pattern: /\bsecret:\/\/[^\s"'`)},\]]+/gi,
    replacement: "<redacted:secret-ref>",
  },
  {
    category: "apple_team_id",
    description: "Apple Team ID in signing context",
    pattern: /\b(?:DEVELOPMENT_TEAM|TEAM_ID|team_id|teamId|Team ID|team identifier)\b[^\n]{0,60}\b[A-Z0-9]{10}\b/g,
    replacement: "<redacted:team-id>",
  },
  {
    category: "bundle_id",
    description: "real Clawix bundle id",
    pattern: /\b(?:bundle_id|bundleId|bundle identifier|withBundleIdentifier)\b[^\n]{0,80}\bcom\.(?:claw|clawix)(?:\.[A-Za-z0-9_-]+)+\b/g,
    replacement: "<redacted:bundle-id>",
  },
  {
    category: "prompt_content",
    description: "raw prompt or message content",
    pattern: /"(prompt|systemPrompt|userPrompt|assistantPrompt|userMessage|assistantMessage|input|transcript|trace)"\s*:\s*"(?!<redacted:)([^"\\]|\\.){12,}"/gi,
    replacement: "\"$1\":\"<redacted:content>\"",
  },
  {
    category: "prompt_content",
    description: "raw prompt or message content",
    pattern: /\b(prompt|systemPrompt|userPrompt|assistantPrompt|userMessage|assistantMessage|input|transcript|trace)\s*[:=]\s*(?!<redacted:)("[^"\n]{12,}"|'[^'\n]{12,}'|`[^`\n]{12,}`|[^\n]{24,})/gi,
    replacement: "$1=<redacted:content>",
  },
];

export function serializeForPrivacyScan(value) {
  return typeof value === "string" ? value : JSON.stringify(value);
}

export function redactSensitiveText(text) {
  let redacted = String(text ?? "");
  for (const rule of SECRET_PATTERNS) {
    redacted = redacted.replace(rule.pattern, rule.replacement);
  }
  return redacted;
}

export function redactSensitiveValue(value) {
  if (typeof value === "string") return redactSensitiveText(value);
  if (Array.isArray(value)) return value.map((entry) => redactSensitiveValue(entry));
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, child]) => [key, redactSensitiveValue(child)]));
  }
  return value;
}

export function privacyFindings(value) {
  const serialized = serializeForPrivacyScan(value) ?? "";
  const findings = [];
  for (const rule of SECRET_PATTERNS) {
    rule.pattern.lastIndex = 0;
    if (rule.pattern.test(serialized)) {
      findings.push({ category: rule.category, description: rule.description });
    }
  }
  return findings;
}

export function publicSafetyErrors(value, label = "artifact") {
  return privacyFindings(value).map((finding) => `${label} contains ${finding.description}`);
}

export function assertPublicSafe(value, label = "artifact") {
  const errors = publicSafetyErrors(value, label);
  if (errors.length > 0) {
    throw new Error(errors.join("; "));
  }
}

export function sanitizedErrorDetails(value) {
  if (Array.isArray(value)) return value.map((entry) => redactSensitiveText(entry)).join("; ");
  return redactSensitiveText(String(value ?? ""));
}
