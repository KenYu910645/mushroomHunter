//
//  DailyRewardStore.swift
//  mushroomHunter
//
//  Purpose:
//  - Loads DailyReward month state and executes the server-authoritative claim action.
//
//  Defined in this file:
//  - DailyRewardStore reward-state loader and claimer.
//
import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

/// Shared state container for the DailyReward sheet.
@MainActor
final class DailyRewardStore: ObservableObject {
    /// Localized title for the visible current month.
    @Published private(set) var monthTitle: String = ""
    /// Calendar cells rendered by the month grid.
    @Published private(set) var calendarCells: [DailyRewardCalendarCell] = []
    /// True while the sheet is loading reward state.
    @Published private(set) var isLoading: Bool = false
    /// True while today's reward claim is in flight.
    @Published private(set) var isClaiming: Bool = false
    /// True after the current Taipei day has already been claimed.
    @Published private(set) var isTodayClaimed: Bool = false
    /// Latest human-readable success message shown after claim.
    @Published var successMessage: String? = nil
    /// Latest human-readable error message shown after load/claim failure.
    @Published var errorMessage: String? = nil

    /// Firestore database handle used to read reward state from the user document.
    private let db = Firestore.firestore()
    /// Callable Functions handle used for server-authoritative claim execution.
    private let functions = Functions.functions(region: "us-central1")

    /// Loads current-month reward state for the signed-in user.
    /// - Parameters:
    ///   - session: Shared session state used for auth context and wallet refresh.
    ///   - isResettingFeedback: True when stale claim success/error messages should be cleared before loading.
    func load(session: UserSessionStore, isResettingFeedback: Bool = true) async {
        isLoading = true
        if isResettingFeedback {
            errorMessage = nil
        }
        defer { isLoading = false }

        let context = currentDateContext()
        if AppTesting.isUITesting {
            session.updateDailyRewardPendingState(AppTesting.isMockDailyRewardPendingToday)
            applyCalendarState(
                context: context,
                claimedDays: AppTesting.mockDailyRewardClaimedDays(forMonthKey: context.monthKey),
                rewardHoney: session.dailyRewardHoneyAmount
            )
            return
        }

        guard let userId = session.authUid ?? Auth.auth().currentUser?.uid, userId.isEmpty == false else {
            session.updateDailyRewardPendingState(true)
            applyCalendarState(
                context: context,
                claimedDays: [],
                rewardHoney: session.dailyRewardHoneyAmount
            )
            return
        }

        do {
            let snapshot = try await db.collection("users").document(userId).getDocument()
            session.updateDailyRewardPendingState(session.resolveIsDailyRewardPending(from: snapshot.data() ?? [:]))
            let claimedDays = claimedDaysFromUserData(snapshot.data(), monthKey: context.monthKey)
            applyCalendarState(
                context: context,
                claimedDays: claimedDays,
                rewardHoney: session.dailyRewardHoneyAmount
            )
        } catch {
            session.updateDailyRewardPendingState(isTodayClaimed == false)
            applyCalendarState(
                context: context,
                claimedDays: [],
                rewardHoney: session.dailyRewardHoneyAmount
            )
            errorMessage = NSLocalizedString("daily_reward_load_error", comment: "")
        }
    }

    /// Claims today's reward through the backend callable and refreshes local wallet/inbox state.
    /// - Parameters:
    ///   - session: Shared session state that owns local honey balance.
    ///   - notificationInbox: Shared inbox store used to refresh the bell list after claim.
    func startClaimTodayReward(
        session: UserSessionStore,
        notificationInbox: EventInboxStore
    ) {
        guard isTodayClaimed == false else { return }
        guard isClaiming == false else { return }

        isClaiming = true
        errorMessage = nil
        successMessage = nil

        Task {
            await claimTodayReward(session: session, notificationInbox: notificationInbox)
        }
    }

    /// Performs the async DailyReward claim work after the tap path has already locked the button.
    /// - Parameters:
    ///   - session: Shared session state that owns local honey balance.
    ///   - notificationInbox: Shared inbox store used to refresh the bell list after claim.
    private func claimTodayReward(
        session: UserSessionStore,
        notificationInbox: EventInboxStore
    ) async {
        defer { isClaiming = false }

        let context = currentDateContext()
        if AppTesting.isUITesting {
            AppTesting.addMockDailyRewardClaim(day: context.day, monthKey: context.monthKey)
            session.updateDailyRewardPendingState(false)
            session.addHoney(session.dailyRewardHoneyAmount)
            applyCalendarState(
                context: context,
                claimedDays: AppTesting.mockDailyRewardClaimedDays(forMonthKey: context.monthKey),
                rewardHoney: session.dailyRewardHoneyAmount
            )
            successMessage = String(
                format: NSLocalizedString("daily_reward_claim_success_message", comment: ""),
                session.dailyRewardHoneyAmount
            )
            return
        }

        do {
            let result = try await functions.httpsCallable("claimDailyHoneyReward").call([:])
            let responseData = result.data as? [String: Any] ?? [:]
            let updatedHoney = responseData["updatedHoney"] as? Int
            let grantedHoney = responseData["rewardAmount"] as? Int ?? session.dailyRewardHoneyAmount
            var claimedDays = claimedDaysFromCurrentCalendar()
            claimedDays.insert(context.day)

            if let updatedHoney {
                session.honey = max(0, updatedHoney)
                session.persistScopedInt(session.kHoney, value: session.honey)
            }
            session.updateDailyRewardPendingState(false)

            applyCalendarState(
                context: context,
                claimedDays: claimedDays,
                rewardHoney: grantedHoney
            )
            successMessage = String(
                format: NSLocalizedString("daily_reward_claim_success_message", comment: ""),
                grantedHoney
            )
            await load(session: session)
            await notificationInbox.refreshFromServer()
            await session.refreshProfileFromBackend()
        } catch let error as NSError {
            errorMessage = claimErrorMessage(from: error)
            await load(session: session, isResettingFeedback: false)
        } catch {
            errorMessage = NSLocalizedString("daily_reward_claim_error_generic", comment: "")
            await load(session: session, isResettingFeedback: false)
        }
    }

    /// Builds one month grid and claim state from the claimed-day list.
    /// - Parameters:
    ///   - context: Current Taipei date context.
    ///   - claimedDays: Claimed day numbers for the visible month.
    private func applyCalendarState(
        context: DailyRewardDateContext,
        claimedDays: Set<Int>,
        rewardHoney: Int
    ) {
        monthTitle = context.monthTitle
        isTodayClaimed = claimedDays.contains(context.day)
        calendarCells = buildCalendarCells(
            context: context,
            claimedDays: claimedDays,
            rewardHoney: rewardHoney
        )
    }

    /// Reads the active-month claimed-day set from one user document payload.
    /// - Parameters:
    ///   - data: Firestore user data.
    ///   - monthKey: Month key that the client is currently rendering.
    /// - Returns: Sanitized set of claimed day numbers for the current month.
    private func claimedDaysFromUserData(_ data: [String: Any]?, monthKey: String) -> Set<Int> {
        guard let rewardData = data?["dailyReward"] as? [String: Any] else {
            return []
        }

        let storedMonthKey = (rewardData["monthKey"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard storedMonthKey == monthKey else {
            return []
        }

        let rawClaimedDays = rewardData["claimedDays"] as? [Any] ?? []
        let claimedDays = rawClaimedDays.compactMap { rawValue -> Int? in
            if let intValue = rawValue as? Int {
                return intValue
            }
            if let numberValue = rawValue as? NSNumber {
                return numberValue.intValue
            }
            return nil
        }

        return Set(claimedDays.filter { $0 > 0 && $0 <= 31 })
    }

    /// Creates the current-month grid including empty leading cells.
    /// - Parameters:
    ///   - context: Current Taipei date context.
    ///   - claimedDays: Claimed day numbers for the current month.
    /// - Returns: Renderable calendar cells.
    private func buildCalendarCells(
        context: DailyRewardDateContext,
        claimedDays: Set<Int>,
        rewardHoney: Int
    ) -> [DailyRewardCalendarCell] {
        var cells: [DailyRewardCalendarCell] = []
        for index in 0..<context.leadingPlaceholderCount {
            cells.append(
                DailyRewardCalendarCell(
                    id: "placeholder-\(index)",
                    dayNumber: nil,
                    rewardHoney: nil,
                    state: nil
                )
            )
        }

        for dayNumber in 1...context.numberOfDays {
            cells.append(
                DailyRewardCalendarCell(
                    id: "day-\(dayNumber)",
                    dayNumber: dayNumber,
                    rewardHoney: rewardHoney,
                    state: dayState(
                        forDay: dayNumber,
                        today: context.day,
                        claimedDays: claimedDays
                    )
                )
            )
        }
        return cells
    }

    /// Resolves how one visible day should appear in the calendar.
    /// - Parameters:
    ///   - dayNumber: Day number being rendered.
    ///   - today: Current Taipei day number.
    ///   - claimedDays: Claimed day set for the active month.
    /// - Returns: Display state for this day.
    private func dayState(forDay dayNumber: Int, today: Int, claimedDays: Set<Int>) -> DailyRewardDayState {
        if claimedDays.contains(dayNumber) {
            return .claimed
        }
        if dayNumber == today {
            return .claimableToday
        }
        if dayNumber < today {
            return .expired
        }
        return .locked
    }

    /// Maps backend and transport failures into user-facing claim errors.
    /// - Parameter error: Callable Functions error payload.
    /// - Returns: Localized error text.
    private func claimErrorMessage(from error: NSError) -> String {
        let alreadyClaimedCode = FunctionsErrorCode.alreadyExists.rawValue
        if error.code == alreadyClaimedCode {
            return NSLocalizedString("daily_reward_claim_error_already_claimed", comment: "")
        }

        let unavailableCode = FunctionsErrorCode.unavailable.rawValue
        let notFoundCode = FunctionsErrorCode.notFound.rawValue
        if error.code == unavailableCode || error.code == notFoundCode {
            return NSLocalizedString("daily_reward_claim_error_service_unavailable", comment: "")
        }

        if let details = error.userInfo[FunctionsErrorDetailsKey] as? String, details.isEmpty == false {
            return details
        }

        return NSLocalizedString("daily_reward_claim_error_generic", comment: "")
    }

    /// Extracts the currently rendered claimed-day set so successful claims can update the UI immediately.
    /// - Returns: Claimed day numbers already reflected in the visible calendar.
    private func claimedDaysFromCurrentCalendar() -> Set<Int> {
        let claimedDays = calendarCells.compactMap { cell -> Int? in
            guard cell.state == .claimed else { return nil }
            return cell.dayNumber
        }
        return Set(claimedDays)
    }

    /// Resolves the current Taipei month/day context used across UI and claim state.
    /// - Returns: Current month/date metadata.
    private func currentDateContext() -> DailyRewardDateContext {
        let calendar = taipeiCalendar()
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        let year = components.year ?? 2000
        let month = components.month ?? 1
        let day = components.day ?? 1
        let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? now
        let numberOfDays = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30
        let weekdayOfFirstDay = calendar.component(.weekday, from: firstOfMonth)
        let leadingPlaceholderCount = (weekdayOfFirstDay - calendar.firstWeekday + 7) % 7

        let monthFormatter = DateFormatter()
        monthFormatter.calendar = calendar
        monthFormatter.timeZone = calendar.timeZone
        monthFormatter.locale = Locale.current
        monthFormatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")

        let monthKey = String(format: "%04d-%02d", year, month)
        return DailyRewardDateContext(
            monthKey: monthKey,
            monthTitle: monthFormatter.string(from: firstOfMonth),
            numberOfDays: numberOfDays,
            day: day,
            leadingPlaceholderCount: leadingPlaceholderCount
        )
    }

    /// Builds the canonical Taipei calendar used by DailyReward business rules.
    /// - Returns: Gregorian calendar locked to the configured reset timezone.
    private func taipeiCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: AppConfig.DailyReward.resetTimeZoneIdentifier) ?? .current
        calendar.firstWeekday = 1
        return calendar
    }
}

/// Immutable current-date snapshot used to derive one month of DailyReward UI.
private struct DailyRewardDateContext {
    /// Month key persisted in Firestore reward state.
    let monthKey: String
    /// Localized month title rendered above the calendar.
    let monthTitle: String
    /// Number of days in the current month.
    let numberOfDays: Int
    /// Current day number in Taipei time.
    let day: Int
    /// Leading empty cells needed before day 1.
    let leadingPlaceholderCount: Int
}
