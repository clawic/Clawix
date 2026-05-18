export const pendingEvidenceEnv = "CLAWIX_UI_ALLOW_PENDING_PRIVATE_EVIDENCE";

export function enforcePrivateVerifierArgs(args, {
  label,
  allowedFlags,
  optionsWithValues = [],
  testOnlyFlags = [],
  testOnlyEnv = pendingEvidenceEnv,
}) {
  const allowed = new Set(allowedFlags);
  const valueOptions = new Set(optionsWithValues);
  const testOnly = new Set(testOnlyFlags);

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith("--")) {
      console.error(`${label} received unexpected argument ${arg}.`);
      process.exit(1);
    }
    if (!allowed.has(arg)) {
      console.error(`${label} received unknown flag ${arg}.`);
      process.exit(1);
    }
    if (valueOptions.has(arg)) {
      const value = args[index + 1];
      if (!value || value.startsWith("--")) {
        console.error(`${label} requires a value after ${arg}.`);
        process.exit(1);
      }
      index += 1;
    }
  }

  if (args.some((arg) => testOnly.has(arg)) && process.env[testOnlyEnv] !== "1") {
    console.error(`${label} pending evidence flags require ${testOnlyEnv}=1.`);
    process.exit(1);
  }
}
