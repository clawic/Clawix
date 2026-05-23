# Legal External Pending Validation

Source conversation: `source:legal-safety`

Status: `active_goal_not_complete`

This ledger separates reproducible legal closure evidence from validation that
requires a signed app, OS share sheet, store account, real provider, physical
device, notarization service, or exact release-channel approval. Rows marked
`EXTERNAL PENDING` are not passes and must not be used to approve a release.

## Current Rows

| ID | Requirement | Local evidence | Missing prerequisite | Status |
| --- | --- | --- | --- | --- |
| LEGAL-EXT-001 | macOS signed legal clickwrap smoke | `LegalSafetyTests`, `LegalConsentSheet`, and `ContentChrome` source require current legal acceptance and 18+ confirmation. | Current signed macOS candidate launched through the private workspace launcher. | EXTERNAL PENDING |
| LEGAL-EXT-002 | iOS signed legal clickwrap smoke | `IOSLegalConsentSheet`, `IOSLegalSafetyStore`, and source assertions cover initial/versioned legal acceptance. | Current signed iOS candidate or simulator/device lane selected by the private target toggle. | EXTERNAL PENDING |
| LEGAL-EXT-003 | Signed settings UI smoke | `LegalSafetySettingsPage`, persistent legal settings, and tests cover support/provider/remote opt-ins and audit retention. | Current signed app window inspection through the private launcher. | EXTERNAL PENDING |
| LEGAL-EXT-004 | Platform share-sheet smoke | Export/share source paths require review and legal labels before sensitive output leaves the app. | OS share-sheet or signed app export flow with no production data. | EXTERNAL PENDING |
| LEGAL-EXT-005 | Store metadata review | Terms, Privacy, Disclaimer, Safety, Regulated Domains, EULA, and release checklists define 18+, no emergency service, no professional replacement, and opt-in external flows. | Store console metadata draft for the exact channel. | EXTERNAL PENDING |
| LEGAL-EXT-006 | Signing, notarization, TestFlight, App Store, website, tag, or upload action | Release checklists and preflight gates exist and require exact approval. | Fresh explicit approval for the exact channel action plus the corresponding external service. | EXTERNAL PENDING |
| LEGAL-EXT-007 | Real provider or device validation | Hermetic tests cover refusal, review gates, redaction, opt-in, labels, and local settings behavior. | Approved provider/device account, physical device, paid API, or native permission lane. | EXTERNAL PENDING |

## Goal Completion Impact

| External pending row | linkedPromiseIds | linkedDecisionIds | completionImpact | closureEffect | reentryCondition | evidenceRequired |
| --- | --- | --- | --- | --- | --- | --- |
| LEGAL-EXT-001 | none | LCA-011,LCA-019 | validation_only | allows_local_completion | Current signed macOS candidate is available through an approved launcher lane. | signed macOS clickwrap smoke result |
| LEGAL-EXT-002 | none | LCA-011,LCA-019 | validation_only | allows_local_completion | Current signed iOS candidate or selected simulator/device lane is available. | signed iOS clickwrap smoke result |
| LEGAL-EXT-003 | none | LCA-014,LCA-026,LCA-027 | validation_only | allows_local_completion | Current signed app settings UI can be inspected through an approved lane. | signed settings UI smoke result |
| LEGAL-EXT-004 | none | LCA-033 | validation_only | allows_local_completion | OS share-sheet or signed app export flow can be exercised with synthetic data. | platform share-sheet smoke result |
| LEGAL-EXT-005 | none | LCA-006,LCA-021,LCA-031 | validation_only | allows_local_completion | Store console metadata draft exists for the exact release channel. | store metadata review result |
| LEGAL-EXT-006 | none | LCA-010,LCA-031 | future_extension | allows_local_completion | A future release goal requests the exact signing, notarization, upload, store, website, tag, or publish action. | exact action approval, external service receipt, release audit |
| LEGAL-EXT-007 | none | LCA-018,LCA-025,LCA-027 | validation_only | allows_local_completion | Approved provider or device account, physical device, paid API, or native permission lane is available. | provider or device validation receipt |

## Rules

- `EXTERNAL PENDING` means blocked by unavailable external prerequisites, not
  validated.
- Any `FAIL` in a signed, provider, device, share-sheet, or store lane is a real
  defect and must not be downgraded to `EXTERNAL PENDING`.
- No row authorizes a push, tag, publish, upload, notarization, TestFlight,
  App Store submission, website deployment, paid API call, real prompt, real
  provider mutation, or production-data access.
- When a prerequisite becomes available, rerun the matching lane with explicit
  approval and replace the row with the actual result and evidence.
