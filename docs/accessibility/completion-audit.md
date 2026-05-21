# Accessibility Governance Completion Audit

This public-safe audit tracks the first accessibility governance program. It
does not publish screen reader transcripts, private screenshots, device names,
local paths, or human approval artifacts.

- Constitution principle: IX.8 Accessibility is non-optional.
- Canon: `docs/adr/0029-accessibility-governance.md`.
- Public guard: `scripts/accessibility_governance_guard.mjs`.
- Completion status: blocked by EXTERNAL PENDING private/manual evidence.

| Requirement | Public state | Remaining evidence |
| --- | --- | --- |
| Required accessibility axes are declared | validated-public | None local. |
| Visible UI inventory maps to accessibility axes | validated-public | Private assistive-technology and rendered captures remain EXTERNAL PENDING. |
| Agent-generated UI inherits the baseline | validated-public | Generated UI review packets remain EXTERNAL PENDING until approved examples exist. |
| Source changes are classified by accessibility-impacting detectors | validated-public | Detector findings still require task-specific evidence. |
| Visual/copy/layout authority remains separate | validated-public | Any presentation-changing accessibility fix still needs UI governance approval. |

| External pending lane | Reason | Reentry |
| --- | --- | --- |
| Screen reader transcript evidence | Raw transcripts and local app state are private/manual artifacts. | Store only approved aliases and hashes, then rerun `node scripts/accessibility_governance_guard.mjs`. |
| Signed-host and device keyboard traversal | Requires real app/device state and explicit validation approval. | Run approved host/device validation and attach public-safe evidence aliases. |
| Contrast and large-text rendered captures | Raw captures remain private visual evidence. | Use approved private capture roots and public-safe hashes. |
| Generated UI accessibility review | Needs concrete generated/custom UI samples. | Register a generated-UI review packet before claiming completion. |
