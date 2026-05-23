#!/usr/bin/env node

const SECRET_TEXT_PATTERNS = [
  /\bBearer\s+([A-Za-z0-9._-]{6,})/gi,
  /\b(sk-[A-Za-z0-9._-]{6,})\b/g,
  /\b(api[_ -]?key|token|secret)\b\s*[:=]\s*([^\s,;]+)/gi,
  /\/Users\/[^/\s]+/g,
];

export function createDiagnostic(code, message, options = {}) {
  return {
    code,
    status: options.status ?? "FAIL",
    message,
    location: options.location ?? null,
    suggestion: options.suggestion ?? null,
    safeNextStep: options.safeNextStep ?? null,
  };
}

export function printActionableFailureReport({ title, diagnostics, stream = process.stderr }) {
  const normalized = diagnostics.map(normalizeDiagnostic);
  stream.write(`${redactSensitiveText(title)}\n`);
  for (const diagnostic of normalized) {
    stream.write(`- [${diagnostic.status}] ${diagnostic.message}\n`);
    stream.write(`  code: ${diagnostic.code}\n`);
    if (diagnostic.location) stream.write(`  location: ${diagnostic.location}\n`);
    if (diagnostic.suggestion) stream.write(`  suggestion: ${diagnostic.suggestion}\n`);
    if (diagnostic.safeNextStep) stream.write(`  next: ${diagnostic.safeNextStep}\n`);
  }
}

export function normalizeDiagnostic(diagnostic) {
  if (typeof diagnostic === "string") {
    return {
      code: "validation_failed",
      status: "FAIL",
      message: redactSensitiveText(diagnostic),
      location: null,
      suggestion: "Inspect the failing file or manifest entry named in the message.",
      safeNextStep: "Fix the validation input, then rerun the same check.",
    };
  }
  return {
    code: redactSensitiveText(String(diagnostic.code || "validation_failed")),
    status: redactSensitiveText(String(diagnostic.status || "FAIL")),
    message: redactSensitiveText(String(diagnostic.message || "Validation failed.")),
    location: diagnostic.location ? redactSensitiveText(String(diagnostic.location)) : null,
    suggestion: diagnostic.suggestion ? redactSensitiveText(String(diagnostic.suggestion)) : null,
    safeNextStep: diagnostic.safeNextStep ? redactSensitiveText(String(diagnostic.safeNextStep)) : null,
  };
}

export function redactSensitiveText(value) {
  let redacted = String(value);
  redacted = redacted.replaceAll(SECRET_TEXT_PATTERNS[0], (_match, token) => `Bearer ${redactString(token)}`);
  redacted = redacted.replaceAll(SECRET_TEXT_PATTERNS[1], (match) => redactString(match));
  redacted = redacted.replaceAll(SECRET_TEXT_PATTERNS[2], (_match, label, secret) => `${label}: ${redactString(secret)}`);
  redacted = redacted.replaceAll(SECRET_TEXT_PATTERNS[3], "~");
  return redacted;
}

function redactString(value) {
  if (value.length <= 8) return "[REDACTED]";
  return `${"*".repeat(Math.max(4, value.length - 4))}${value.slice(-4)}`;
}

function runSelfTest() {
  const chunks = [];
  printActionableFailureReport({
    title: "Example check failed for /Users/example/private",
    diagnostics: [
      createDiagnostic("example_missing_file", "token: sk-test-secret-123456", {
        location: "/Users/example/private/repo/file.json",
        suggestion: "Create the missing fixture with synthetic data.",
        safeNextStep: "Rerun node scripts/actionable-error.mjs --self-test.",
      }),
    ],
    stream: { write: (chunk) => { chunks.push(chunk); } },
  });
  const output = chunks.join("");
  if (!output.includes("code: example_missing_file")) throw new Error("self-test missing stable code");
  if (!output.includes("location: ~/private/repo/file.json")) throw new Error("self-test missing redacted location");
  if (!output.includes("next: Rerun node scripts/actionable-error.mjs --self-test.")) throw new Error("self-test missing safe next step");
  if (output.includes("sk-test-secret-123456") || output.includes("/Users/example")) throw new Error("self-test leaked private data");
  console.log("actionable error helper self-test passed");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  if (process.argv.includes("--self-test")) runSelfTest();
  else {
    printActionableFailureReport({
      title: "actionable error helper usage error:",
      diagnostics: [
        createDiagnostic("usage_error", "Use --self-test to verify formatting and redaction.", {
          status: "USAGE",
          location: "scripts/actionable-error.mjs",
          suggestion: "Import createDiagnostic and printActionableFailureReport from guard scripts.",
          safeNextStep: "Run node scripts/actionable-error.mjs --self-test.",
        }),
      ],
    });
    process.exit(64);
  }
}
