//
//  DailyRewardModels.swift
//  mushroomHunter
//
//  Purpose:
//  - Defines the month/day models rendered by the DailyReward calendar sheet.
//
//  Defined in this file:
//  - DailyRewardCalendarCell and DailyRewardDayState.
//
import Foundation

/// Visual state applied to one day inside the DailyReward calendar.
enum DailyRewardDayState {
    /// Reward was already claimed for this day.
    case claimed
    /// Reward can be claimed right now because this day matches today's Taipei date.
    case claimableToday
    /// Reward day has already passed and can no longer be claimed.
    case expired
    /// Reward day is in the future and is not yet available.
    case locked
}

/// One renderable cell inside the current-month reward calendar grid.
struct DailyRewardCalendarCell: Identifiable {
    /// Stable id used by SwiftUI grid diffing.
    let id: String
    /// Day number shown in the cell. `nil` means this is a leading/trailing spacer cell.
    let dayNumber: Int?
    /// Reward amount shown for a real day cell.
    let rewardHoney: Int?
    /// Display state for a real day cell.
    let state: DailyRewardDayState?

    /// True when this cell is only spacing and should render empty.
    var isPlaceholder: Bool {
        dayNumber == nil
    }
}
