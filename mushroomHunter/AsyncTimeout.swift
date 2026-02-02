//
//  AsyncTimeout.swift
//  mushroomHunter
//
//  Created by Ken on 2/2/2026.
//

import Foundation

enum TimeoutError: LocalizedError {
    case timedOut
    var errorDescription: String? { "Request timed out. Check network or Firebase rules." }
}

func withTimeout<T>(
    seconds: Double,
    operation: @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError.timedOut
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
