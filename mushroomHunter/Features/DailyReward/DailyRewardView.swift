//
//  DailyRewardView.swift
//  mushroomHunter
//
//  Purpose:
//  - Renders the current-month DailyReward sheet and today's claim action.
//
//  Defined in this file:
//  - DailyRewardView and its calendar cell presentation helpers.
//
import SwiftUI

/// Current-month DailyReward sheet shared by Mushroom, Postcard, and Profile tabs.
struct DailyRewardView: View {
    /// Shared session state used to refresh local honey after a claim.
    @EnvironmentObject private var session: UserSessionStore
    /// Shared inbox store refreshed after a successful claim event write.
    @EnvironmentObject private var notificationInbox: EventInboxStore
    /// Presentation dismiss action for the sheet close button.
    @Environment(\.dismiss) private var dismiss

    /// Local sheet state owner for reward loading and claiming.
    @StateObject private var store = DailyRewardStore()

    /// Weekday symbols rendered above the month grid.
    private let weekdaySymbols: [String] = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale.current
        calendar.firstWeekday = 1
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale.current
        return formatter.shortStandaloneWeekdaySymbols
    }()

    /// Sheet body containing month header, reward calendar, and claim CTA.
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text(store.monthTitle)
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("daily_reward_month_title")

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                        ForEach(weekdaySymbols, id: \.self) { symbol in
                            Text(symbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }

                        ForEach(store.calendarCells) { cell in
                            DailyRewardDayCell(cell: cell)
                        }
                    }
                    .accessibilityIdentifier("daily_reward_calendar_grid")
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )

                VStack(spacing: 10) {
                    Button {
                        store.startClaimTodayReward(session: session, notificationInbox: notificationInbox)
                    } label: {
                        HStack(spacing: 8) {
                            if store.isClaiming {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            }
                            Text(LocalizedStringKey(store.isClaiming ? "daily_reward_claiming_button" : "daily_reward_claim_button"))
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isTodayClaimed || store.isClaiming || store.isLoading)
                    .accessibilityIdentifier("daily_reward_claim_button")

                    if store.isTodayClaimed {
                        Text(LocalizedStringKey("daily_reward_today_claimed_hint"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(LocalizedStringKey("daily_reward_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityIdentifier("daily_reward_close_button")
                }
            }
            .overlay {
                if store.isLoading {
                    ProgressView(LocalizedStringKey("common_loading"))
                }
            }
            .overlay {
                if let successMessage = store.successMessage {
                    MessageBox(
                        title: NSLocalizedString("daily_reward_claim_success_title", comment: ""),
                        message: successMessage,
                        buttons: [
                            MessageBoxButton(
                                id: "daily_reward_success_ok",
                                title: NSLocalizedString("common_ok", comment: "")
                            ) {
                                store.successMessage = nil
                            }
                        ]
                    )
                }
            }
            .overlay {
                if let errorMessage = store.errorMessage {
                    MessageBox(
                        title: NSLocalizedString("common_error", comment: ""),
                        message: errorMessage,
                        buttons: [
                            MessageBoxButton(
                                id: "daily_reward_error_ok",
                                title: NSLocalizedString("common_ok", comment: "")
                            ) {
                                store.errorMessage = nil
                            }
                        ]
                    )
                }
            }
        }
        .presentationDetents([.large])
        .task {
            await store.load(session: session)
        }
    }
}

/// One calendar day cell used inside the DailyReward month grid.
private struct DailyRewardDayCell: View {
    /// Calendar cell payload to render.
    let cell: DailyRewardCalendarCell

    /// Body that renders either a spacer slot or one styled reward day.
    var body: some View {
        Group {
            if cell.isPlaceholder {
                Color.clear
                    .frame(height: 44)
            } else {
                ZStack(alignment: .topTrailing) {
                    if isShowingTodayDot {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)
                            .padding(.trailing, 6)
                    }

                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Text("\(cell.dayNumber ?? 0)")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(dayNumberTextColor)
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(dayBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(dayBorderColor, lineWidth: 1)
                )
                .accessibilityIdentifier("daily_reward_day_\(cell.dayNumber ?? 0)")
            }
        }
    }

    /// Background fill color for the current day state.
    private var dayBackgroundColor: Color {
        switch cell.state {
        case .claimed:
            return Color.orange.opacity(0.28)
        case .claimableToday:
            return Color.gray.opacity(0.22)
        case .expired:
            return Color.gray.opacity(0.22)
        case .locked:
            return Color.gray.opacity(0.22)
        case .none:
            return .clear
        }
    }

    /// Border color used to keep day states visually distinct.
    private var dayBorderColor: Color {
        switch cell.state {
        case .claimed:
            return Color.orange.opacity(0.55)
        case .claimableToday:
            return Color.gray.opacity(0.38)
        case .expired:
            return Color.gray.opacity(0.38)
        case .locked:
            return Color.gray.opacity(0.38)
        case .none:
            return .clear
        }
    }

    /// Text tint for the day number so received and unreceived days stay readable.
    private var dayNumberTextColor: Color {
        switch cell.state {
        case .claimed:
            return .orange
        case .claimableToday:
            return .primary
        case .expired:
            return .primary
        case .locked:
            return .primary
        case .none:
            return .clear
        }
    }

    /// True when the unclaimed current day should show the small red reminder dot.
    private var isShowingTodayDot: Bool {
        switch cell.state {
        case .claimableToday:
            return true
        default:
            return false
        }
    }
}
