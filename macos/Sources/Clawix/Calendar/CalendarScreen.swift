import SwiftUI

struct CalendarScreen: View {

    @StateObject private var store = CalendarStore()

    var body: some View {
        VStack(spacing: 0) {
            CalendarToolbar(store: store)
            mainLayout
        }
        .background(CalendarTokens.Surface.window)
        .task { await store.bootstrap() }
        .onDisappear {
            store.cancelSurfaceWork()
        }
        .sheet(isPresented: showSheetBinding) {
            if let draft = store.editingDraft {
                EventEditSheet(store: store,
                                draft: draft,
                                mode: draft.id == nil ? .create : .edit)
            }
        }
    }

    private var mainLayout: some View {
        HStack(spacing: 0) {
            CalendarSubSidebar(store: store)
            ZStack(alignment: .topTrailing) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                inspectorOverlay
            }
        }
        .animation(CalendarTokens.Motion.inspectorShow, value: store.selectedEventID)
    }

    @ViewBuilder
    private var inspectorOverlay: some View {
        if store.viewMode != .year,
           let selectedID = store.selectedEventID,
           let event = store.event(byID: selectedID) {
            EventInspectorPanel(store: store, event: event)
                .frame(maxHeight: .infinity)
                .shadow(color: .black.opacity(0.40), radius: 18, x: -6, y: 0)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private var showSheetBinding: Binding<Bool> {
        Binding(
            get: { store.editingDraft != nil },
            set: { newValue in
                if !newValue { store.cancelEdit() }
            }
        )
    }

    @ViewBuilder
    private var content: some View {
        switch store.access {
        case .unknown, .requesting:
            centered("Loading calendar…")
        case .denied(let reason):
            centered("Calendar access denied", subtitle: reason)
        case .unavailable:
            centered("Calendar unavailable")
        case .granted:
            grantedContent
                .transition(.opacity)
                .id(store.viewMode)
        }
    }

    @ViewBuilder
    private var grantedContent: some View {
        switch store.viewMode {
        case .day:   DayView(store: store)
        case .week:  WeekView(store: store)
        case .month: MonthView(store: store)
        case .year:  YearView(store: store)
        }
    }

    private func centered(_ title: String, subtitle: String? = nil) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(CalendarTokens.Ink.primary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(CalendarTokens.Ink.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
