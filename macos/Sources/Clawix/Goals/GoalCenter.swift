import Foundation
import Combine

// MARK: - Goals
//
// A goal is a budgeted, persistent objective attached to one chat. While a
// goal is active a banner sits above the composer; the agent runtime can
// report token usage against the budget so the goal moves to a "limited"
// state when it overruns, and to "achieved" when the work is done. State is
// stored per chat so it survives relaunches; the runtime layer can later feed
// real token accounting through `recordTokens`/`markAchieved`.

struct ActiveGoal: Identifiable, Codable, Equatable {
    enum Status: String, Codable {
        case active
        case paused
        case limited      // ran past its token budget
        case achieved
    }

    let id: UUID
    var objective: String
    var status: Status
    /// nil means the goal runs without a token budget.
    var tokenBudget: Int?
    var tokensUsed: Int
    var createdAt: Date
    var achievedAt: Date?
    var elapsedSeconds: Int

    init(id: UUID = UUID(),
         objective: String,
         status: Status = .active,
         tokenBudget: Int? = nil,
         tokensUsed: Int = 0,
         createdAt: Date = Date(),
         achievedAt: Date? = nil,
         elapsedSeconds: Int = 0) {
        self.id = id
        self.objective = objective
        self.status = status
        self.tokenBudget = tokenBudget
        self.tokensUsed = tokensUsed
        self.createdAt = createdAt
        self.achievedAt = achievedAt
        self.elapsedSeconds = elapsedSeconds
    }

    /// Status after applying budget overrun, so callers don't recompute it.
    var effectiveStatus: Status {
        if status == .achieved { return .achieved }
        if status == .active, let budget = tokenBudget, budget > 0, tokensUsed >= budget {
            return .limited
        }
        return status
    }

    /// 0...1 budget consumption, or nil when the goal has no budget.
    var budgetFraction: Double? {
        guard let budget = tokenBudget, budget > 0 else { return nil }
        return min(1.0, Double(tokensUsed) / Double(budget))
    }
}

@MainActor
final class GoalStore: ObservableObject {
    static let shared = GoalStore()

    /// Active goals keyed by chat id string.
    @Published private(set) var goals: [String: ActiveGoal] = [:]

    /// When set, the chat with this id should present the goal create/edit
    /// sheet. The composer's `/goal` command sets it; the banner consumes it.
    @Published var creationRequestChatId: UUID?

    private let defaultsKey = "clawix.goals.active.v1"

    private init() { load() }

    func goal(for chatId: UUID) -> ActiveGoal? { goals[chatId.uuidString] }

    func hasGoal(for chatId: UUID) -> Bool { goals[chatId.uuidString] != nil }

    func setGoal(for chatId: UUID, objective: String, tokenBudget: Int?) {
        let trimmed = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = chatId.uuidString
        if var existing = goals[key] {
            existing.objective = trimmed
            existing.tokenBudget = tokenBudget
            if existing.status == .achieved { existing.status = .active; existing.achievedAt = nil }
            goals[key] = existing
        } else {
            goals[key] = ActiveGoal(objective: trimmed, tokenBudget: tokenBudget)
        }
        save()
    }

    func pause(for chatId: UUID) { mutate(chatId) { if $0.status == .active || $0.status == .limited { $0.status = .paused } } }

    func resume(for chatId: UUID) { mutate(chatId) { if $0.status == .paused { $0.status = .active } } }

    func togglePause(for chatId: UUID) {
        guard let goal = goal(for: chatId) else { return }
        goal.status == .paused ? resume(for: chatId) : pause(for: chatId)
    }

    func markAchieved(for chatId: UUID) {
        mutate(chatId) { $0.status = .achieved; $0.achievedAt = Date() }
    }

    func recordTokens(_ count: Int, for chatId: UUID) {
        guard count > 0 else { return }
        mutate(chatId) {
            $0.tokensUsed += count
            if $0.status == .active, let budget = $0.tokenBudget, budget > 0, $0.tokensUsed >= budget {
                $0.status = .limited
            }
        }
    }

    func remove(for chatId: UUID) {
        guard goals[chatId.uuidString] != nil else { return }
        goals[chatId.uuidString] = nil
        save()
    }

    // MARK: - Internals

    private func mutate(_ chatId: UUID, _ body: (inout ActiveGoal) -> Void) {
        let key = chatId.uuidString
        guard var goal = goals[key] else { return }
        body(&goal)
        goals[key] = goal
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: ActiveGoal].self, from: data) else { return }
        goals = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(goals) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
