//
//  UserSessionStore+Wallet.swift
//  mushroomHunter
//
//  Purpose:
//  - Manages user economy and reputation state updates.
//
//  Defined in this file:
//  - UserSessionStore honey and stars mutation helpers.
//
import Foundation

extension UserSessionStore {
    func updateStars(_ newValue: Int) { // Handles stars update flow.
        stars = max(0, newValue)
        persistScopedInt(kStars, value: stars)

        Task { await syncProfileFields(["stars": stars]) }
        Task { await syncHostedRoomProfile(stars: stars) }
    }

    func canAffordHoney(_ amount: Int) -> Bool { // Evaluates whether the user can pay the requested honey amount.
        guard amount >= 0 else { return false }
        return honey >= amount
    }

    @discardableResult
    func spendHoney(_ amount: Int) -> Bool { // Deducts honey locally if sufficient balance exists.
        guard amount >= 0, honey >= amount else { return false }

        honey -= amount
        persistScopedInt(kHoney, value: honey)
        return true
    }

    func addHoney(_ amount: Int) { // Adds honey locally and syncs new balance to backend.
        guard amount > 0 else { return }

        honey += amount
        persistScopedInt(kHoney, value: honey)
        Task { await syncProfileFields(["honey": honey]) }
    }
}
