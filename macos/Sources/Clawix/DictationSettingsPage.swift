import SwiftUI
import ClawixEngine
import KeyboardShortcuts

/// Settings page that exposes the dictation engine: hotkey trigger
/// and behaviour, active Whisper model, language hint, paste vs
/// clipboard-only output, and the three permissions the flow needs.
///
/// Mirrors the visual language of the other Settings pages
/// (`PageHeader`, dark-fill cards with hairline strokes, dropdowns and
/// pill toggles) without depending on the file-private helpers in
/// `SettingsView.swift` — the building blocks below are local to this
/// file so the page is self-contained.
struct DictationSettingsPage: View {

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var dictation: DictationCoordinator
    @ObservedObject private var hotkey = DictationHotkeySettingsStore.shared
    @ObservedObject private var micPrefs = MicrophonePreferences.shared

    @AppStorage(DictationCoordinator.injectDefaultsKey) private var injectText = true
    @AppStorage(DictationCoordinator.restoreClipboardDefaultsKey) private var restoreClipboard = true
    @AppStorage(DictationCoordinator.autoSendKeyDefaultsKey) private var autoSendRaw = DictationAutoSendKey.none.rawValue
    @AppStorage(DictationCoordinator.languageDefaultsKey) private var language = "auto"
    @AppStorage(DictationCoordinator.restoreClipboardDelayMsKey) private var restoreClipboardDelayMs = 2000
    @AppStorage(DictationCoordinator.addSpaceBeforeKey) private var addSpaceBefore = true
    @AppStorage(DictationCoordinator.autoFormatParagraphsKey) private var autoFormatParagraphs = true

    @AppStorage(DictationSoundPlayer.defaultsKey) private var soundFeedback = true
    @AppStorage(DictationSoundPlayer.playStartKey) private var playStartSound = true
    @AppStorage(DictationSoundPlayer.playStopKey) private var playStopSound = true
    @AppStorage(DictationSoundPlayer.customStartURLKey) private var customStartURL = ""
    @AppStorage(DictationSoundPlayer.customStopURLKey) private var customStopURL = ""

    @AppStorage(MediaController.enabledKey) private var muteAudioWhileRecording = true
    @AppStorage(MediaController.resumeDelayKey) private var muteResumeDelay = 0

    @AppStorage(PlaybackController.enabledKey) private var pauseMediaWhileRecording = false
    @AppStorage(PlaybackController.resumeDelayKey) private var pauseResumeDelay = 0

    @AppStorage(FillerWordsStore.enabledKey) private var fillerWordsEnabled = true

    @AppStorage(DictationCoordinator.prewarmOnLaunchKey) private var prewarmOnLaunch = true

    @AppStorage(DictationOverlay.styleKey) private var recorderStyle = DictationRecorderStyle.mini.rawValue

    @AppStorage(ClawixPersistentSurfaceKeys.dictationAdvancedExpanded) private var advancedExpanded = false

    @StateObject private var replacementStore = DictationReplacementStore.shared
    @StateObject private var vocabulary = DictationVocabularyStore.shared
    @StateObject private var whisperPrompts = WhisperPromptStore.shared
    @StateObject private var powerMode = PowerModeStore.shared
    @StateObject private var promptLibrary = PromptLibrary.shared
    @StateObject private var transcripts = TranscriptionsRepository.shared

    @State private var permissions = PermissionsSnapshot()
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Voice to Text",
                subtitle: "Local on-device dictation. Press the trigger key in any app, speak, release, and the transcript is pasted at the cursor."
            )

            SectionLabel(title: "Hotkey")
            SettingsCard {
                DropdownRow(
                    title: "Trigger",
                    detail: "Bare modifier press starts dictation in any app",
                    options: DictationHotkeyTrigger.allCases.map { ($0, $0.displayName) },
                    selection: Binding(
                        get: { hotkey.trigger },
                        set: { hotkey.trigger = $0 }
                    ),
                    minWidth: 0
                )
                CardDivider()
                DropdownRow(
                    title: "Behaviour",
                    detail: "Hold to push-to-talk, tap to toggle, or both",
                    options: [
                        (DictationHotkeyMode.hybrid,     "Hybrid"),
                        (DictationHotkeyMode.pushToTalk, "Push-to-talk"),
                        (DictationHotkeyMode.toggle,     "Toggle")
                    ],
                    selection: Binding(
                        get: { hotkey.mode },
                        set: { hotkey.mode = $0 }
                    ),
                    minWidth: 0
                )
            }

            SectionLabel(title: "Audio Input")
            SettingsCard {
                MicrophoneSelectorRow(
                    micPrefs: micPrefs,
                    dictation: dictation,
                    micPermission: permissions.microphone
                )
            }

            SectionLabel(title: "Model")
            SettingsCard {
                ForEach(Array(DictationModel.allCases.enumerated()), id: \.offset) { idx, model in
                    if idx > 0 { CardDivider() }
                    DictationModelRow(
                        model: model,
                        store: dictation.modelStore,
                        appState: appState
                    )
                }
            }

            SectionLabel(title: "Output")
            SettingsCard {
                DropdownRow(
                    title: "Language",
                    detail: "Auto-detect works for most users; force a language for proper nouns",
                    options: languageOptions,
                    selection: $language
                )
                CardDivider()
                ToggleRow(
                    title: "Paste into the focused app",
                    detail: "Off keeps the transcript on the clipboard only",
                    isOn: $injectText
                )
                CardDivider()
                ToggleRow(
                    title: "Restore previous clipboard",
                    detail: "After pasting, put the original clipboard contents back",
                    isOn: $restoreClipboard
                )
                CardDivider()
                DropdownRow(
                    title: "Auto-send after paste",
                    detail: "Submit chat-field transcripts automatically with the right shortcut for that app",
                    options: autoSendOptions,
                    selection: $autoSendRaw,
                    minWidth: 180
                )
            }

            SectionLabel(title: "Sound")
            SettingsCard {
                ToggleRow(
                    title: "Sound feedback",
                    detail: "Play short cues when recording starts and stops",
                    isOn: $soundFeedback
                )
            }

            SectionLabel(title: "While recording")
            SettingsCard {
                ToggleRow(
                    title: "Mute system audio",
                    detail: "Silences output while you dictate so video, music or alerts don't bleed into the mic",
                    isOn: $muteAudioWhileRecording
                )
            }

            SectionLabel(title: "Cleanup")
            SettingsCard {
                ToggleRow(
                    title: "Remove filler words",
                    detail: "Strip \"uh\", \"um\", \"este\", \"o sea\" and similar across multiple languages",
                    isOn: $fillerWordsEnabled
                )
            }

            SectionLabel(title: "Dictionary")
            SettingsCard {
                DictionarySummaryRow(store: replacementStore)
                CardDivider()
                VocabularyHintsRow(vocabulary: vocabulary)
            }

            DSPAdvancedSection(expanded: $advancedExpanded) {
                SectionLabel(title: "Auto-send timing")
                SettingsCard {
                    DropdownRow(
                        title: "Restore clipboard delay",
                        detail: "Wait this long after pasting before putting the original clipboard back. Slow Electron apps need 1-2 s",
                        options: restoreDelayOptions,
                        selection: $restoreClipboardDelayMs,
                        minWidth: 130
                    )
                    CardDivider()
                    ToggleRow(
                        title: "Add space before paste",
                        detail: "If the cursor is right after a word, prepend a space so the transcript doesn't merge into it",
                        isOn: $addSpaceBefore
                    )
                    CardDivider()
                    ToggleRow(
                        title: "Format long transcripts as paragraphs",
                        detail: "Split long pauses into paragraph breaks. Activates once the streaming model lands; toggle is honored already",
                        isOn: $autoFormatParagraphs
                    )
                }

                SectionLabel(title: "Sound (advanced)")
                SettingsCard {
                    ToggleRow(
                        title: "Play start sound",
                        detail: "Independent toggle for the start cue",
                        isOn: $playStartSound
                    )
                    CardDivider()
                    CustomSoundRow(
                        title: "Start sound file",
                        currentPath: $customStartURL
                    )
                    CardDivider()
                    ToggleRow(
                        title: "Play stop sound",
                        detail: "Independent toggle for the stop cue",
                        isOn: $playStopSound
                    )
                    CardDivider()
                    CustomSoundRow(
                        title: "Stop sound file",
                        currentPath: $customStopURL
                    )
                }

                SectionLabel(title: "While recording (advanced)")
                SettingsCard {
                    DropdownRow(
                        title: "Mute resume delay",
                        detail: "Seconds to wait after recording stops before unmuting the system",
                        options: secondsOptions,
                        selection: $muteResumeDelay,
                        minWidth: 130
                    )
                    CardDivider()
                    ToggleRow(
                        title: "Pause media while recording",
                        detail: "Pause Music, Spotify or Podcasts (whichever is playing) and resume only that app",
                        isOn: $pauseMediaWhileRecording
                    )
                    CardDivider()
                    DropdownRow(
                        title: "Pause resume delay",
                        detail: "Seconds before unpausing the media app after the session ends",
                        options: secondsOptions,
                        selection: $pauseResumeDelay,
                        minWidth: 130
                    )
                }

                SectionLabel(title: "Hotkey 2 (optional)")
                SettingsCard {
                    DropdownRow(
                        title: "Trigger",
                        detail: "Second modifier you can use to start dictation, with its own behaviour",
                        options: DictationHotkeyTrigger.allCases.map { ($0, $0.displayName) },
                        selection: Binding(
                            get: { hotkey.trigger2 },
                            set: { hotkey.trigger2 = $0 }
                        ),
                        minWidth: 0
                    )
                    CardDivider()
                    DropdownRow(
                        title: "Behaviour",
                        detail: "Hold to push-to-talk, tap to toggle, or both",
                        options: [
                            (DictationHotkeyMode.hybrid,     "Hybrid"),
                            (DictationHotkeyMode.pushToTalk, "Push-to-talk"),
                            (DictationHotkeyMode.toggle,     "Toggle")
                        ],
                        selection: Binding(
                            get: { hotkey.mode2 },
                            set: { hotkey.mode2 = $0 }
                        ),
                        minWidth: 0
                    )
                }

                SectionLabel(title: "Performance")
                SettingsCard {
                    ToggleRow(
                        title: "Prewarm model on launch",
                        detail: "Run a local warm-up at boot so the first dictation of the session is instant.",
                        isOn: $prewarmOnLaunch
                    )
                }

                SectionLabel(title: "Whisper prompt")
                SettingsCard {
                    WhisperPromptEditorRow(
                        store: whisperPrompts,
                        activeLanguage: language
                    )
                }

                SectionLabel(title: "Recorder style")
                SettingsCard {
                    DropdownRow(
                        title: "Pill placement",
                        detail: "Mini sits at the bottom-centre. Notch docks at the top, hugging the notch on MacBooks that have one",
                        options: DictationRecorderStyle.allCases.map { ($0.rawValue, $0.displayName) },
                        selection: $recorderStyle,
                        minWidth: 160
                    )
                }

                SectionLabel(title: "Power Mode")
                SettingsCard {
                    PowerModeSummaryRow(store: powerMode)
                }

                SectionLabel(title: "AI Enhancement")
                SettingsCard {
                    EnhancementSummaryRow(library: promptLibrary)
                }

                SectionLabel(title: "Transcript history")
                SettingsCard {
                    TranscriptHistorySummaryRow(repo: transcripts)
                }

                SectionLabel(title: "Audio input mode")
                SettingsCard {
                    DropdownRow(
                        title: "Mode",
                        detail: "System default uses macOS sound prefs. Custom keeps a single preferred mic. Prioritized walks an ordered list and falls back if the top one disconnects",
                        options: MicrophoneInputMode.allCases.map { ($0.rawValue, $0.displayName) },
                        selection: Binding(
                            get: { micPrefs.mode.rawValue },
                            set: { raw in
                                if let mode = MicrophoneInputMode(rawValue: raw) {
                                    micPrefs.mode = mode
                                }
                            }
                        ),
                        minWidth: 180
                    )
                }

                SectionLabel(title: "Transcription backend")
                SettingsCard {
                    DropdownRow(
                        title: "Engine",
                        detail: "Local Whisper for highest accuracy. Apple Speech streams partials. Cloud STT uses Model Providers",
                        options: DictationTranscriptionBackend.allCases.map { ($0.rawValue, $0.displayName) },
                        selection: Binding(
                            get: { UserDefaults.standard.string(forKey: DictationCoordinator.backendKey) ?? DictationTranscriptionBackend.whisperLocal.rawValue },
                            set: { UserDefaults.standard.set($0, forKey: DictationCoordinator.backendKey) }
                        ),
                        minWidth: 220
                    )
                    CardDivider()
                    ToggleRow(
                        title: "Live preview while recording",
                        detail: "Show streaming partial transcripts in the floating pill. Only fires with backends that stream (Apple Speech)",
                        isOn: Binding(
                            get: { UserDefaults.standard.object(forKey: DictationCoordinator.livePreviewEnabledKey) as? Bool ?? true },
                            set: { UserDefaults.standard.set($0, forKey: DictationCoordinator.livePreviewEnabledKey) }
                        )
                    )
                    CardDivider()
                    CloudBackendsRow()
                }

                SectionLabel(title: "Quality")
                SettingsCard {
                    ToggleRow(
                        title: "Voice Activity Detection",
                        detail: "Filter silences and non-speech before transcription so Whisper doesn't hallucinate over them. Local Whisper only",
                        isOn: Binding(
                            get: { UserDefaults.standard.bool(forKey: DictationCoordinator.vadEnabledKey) },
                            set: { UserDefaults.standard.set($0, forKey: DictationCoordinator.vadEnabledKey) }
                        )
                    )
                }

                SectionLabel(title: "Voice setup")
                SettingsCard {
                    OnboardingTriggerRow()
                }

                SectionLabel(title: "Quick-action shortcuts")
                SettingsCard {
                    KeyboardShortcutsRow(
                        title: "Toggle dictation",
                        detail: "Start/stop dictation from any app",
                        name: .dictationToggle
                    )
                    CardDivider()
                    KeyboardShortcutsRow(
                        title: "Cancel dictation",
                        detail: "Abandon the in-flight session without pasting",
                        name: .dictationCancel
                    )
                    CardDivider()
                    KeyboardShortcutsRow(
                        title: "Paste last transcription",
                        detail: "Re-paste the most recent transcript at the cursor",
                        name: .pasteLastTranscription
                    )
                    CardDivider()
                    KeyboardShortcutsRow(
                        title: "Retry last transcription",
                        detail: "Re-run the previous audio with the current model",
                        name: .retryLastTranscription
                    )
                    CardDivider()
                    KeyboardShortcutsRow(
                        title: "Toggle AI Enhancement",
                        detail: "Flip the master toggle without opening Settings",
                        name: .toggleEnhancement
                    )
                }
            }

            SectionLabel(title: "Permissions")
            SettingsCard {
                PermissionRow(
                    title: "Microphone",
                    detail: "Needed to capture your voice",
                    status: permissions.microphone,
                    request: {
                        Task { @MainActor in
                            _ = await DictationPermissions.requestMicrophone()
                            refreshPermissions()
                        }
                    },
                    openSettings: { DictationPermissions.openMicrophoneSettings() }
                )
                CardDivider()
                PermissionRow(
                    title: "Accessibility",
                    detail: "Allows Clawix to paste the transcript into the focused app",
                    status: permissions.accessibility,
                    request: {
                        DictationPermissions.requestAccessibility()
                        refreshPermissions()
                    },
                    openSettings: { DictationPermissions.openAccessibilitySettings() }
                )
                CardDivider()
                PermissionRow(
                    title: "Input Monitoring",
                    detail: "Lets the global hotkey work while another app has focus",
                    status: permissions.inputMonitoring,
                    request: {
                        DictationPermissions.requestInputMonitoring()
                        // The grant lands async; the periodic timer
                        // below picks it up and re-registers the
                        // global monitor on the next tick.
                        refreshPermissions()
                    },
                    openSettings: { DictationPermissions.openInputMonitoringSettings() }
                )
            }
            .padding(.bottom, 16)
        }
        .onAppear {
            refreshPermissions()
            // Light periodic refresh so the user sees the green dot
            // flip the moment they grant the permission in System
            // Settings, without a restart.
            refreshTimer?.invalidate()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                Task { @MainActor in refreshPermissions() }
            }
            dictation.modelStore.refreshInstalled()
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private var languageOptions: [(String, String)] {
        var options: [(String, String)] = [("auto", "Auto-detect")]
        for lang in AppLanguage.allCases {
            options.append((lang.whisperLanguageCode, lang.displayName))
        }
        return options
    }

    /// Picker options for the auto-send-after-paste dropdown. Stored as
    /// `DictationAutoSendKey.rawValue` so we don't need a Picker tag
    /// separate from the `@AppStorage` string.
    private var autoSendOptions: [(String, String)] {
        DictationAutoSendKey.allCases.map { ($0.rawValue, $0.displayName) }
    }

    /// Generic 0-5s picker used by the mute and pause delays.
    private var secondsOptions: [(Int, String)] {
        [(0, "0 s"), (1, "1 s"), (2, "2 s"), (3, "3 s"), (4, "4 s"), (5, "5 s")]
    }

    /// Restore-clipboard delay picker. Sub-second resolution at the
    /// short end matches the speed of native Cocoa text fields; the
    /// long tail covers slow web views.
    private var restoreDelayOptions: [(Int, String)] {
        [
            (250, "250 ms"),
            (500, "500 ms"),
            (1000, "1 s"),
            (2000, "2 s"),
            (3000, "3 s"),
            (4000, "4 s"),
            (5000, "5 s")
        ]
    }

    private func refreshPermissions() {
        let previousInputMon = permissions.inputMonitoring
        permissions.microphone = DictationPermissions.microphone()
        permissions.accessibility = DictationPermissions.accessibility()
        permissions.inputMonitoring = DictationPermissions.inputMonitoring()
        // If Input Monitoring was just granted (transition from
        // .notDetermined/.denied to .granted), re-arm the hotkey so
        // the global monitor comes online without a relaunch.
        if previousInputMon != .granted, permissions.inputMonitoring == .granted {
            DictationHotkeyMonitor.shared.bootstrap(
                coordinator: DictationCoordinator.shared
            )
        }
    }

    private struct PermissionsSnapshot {
        var microphone: DictationPermissions.Status = .notDetermined
        var accessibility: DictationPermissions.Status = .notDetermined
        var inputMonitoring: DictationPermissions.Status = .notDetermined
    }
}
