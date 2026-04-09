//
//  ReviewReminderManagerTests.swift
//  SwiftPlantUMLstudioTests
//
//  Unit tests for ReviewReminderManager scheduling and state logic.
//

import Foundation
import Testing
@testable import SwiftPlantUMLstudio

// MARK: - GCD dispatch helpers

private func runOnMain(_ block: @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(block)
    } else {
        DispatchQueue.main.sync { MainActor.assumeIsolated(block) }
    }
}

// MARK: - ReviewReminderManager Tests

@Suite("ReviewReminderManager")
struct ReviewReminderManagerTests {

    /// Creates an isolated UserDefaults instance for a single test.
    private func makeTestDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (defaults, suiteName)
    }

    @Test("isEnabled returns false when intervalDays is zero")
    func isEnabledFalseWhenZero() {
        let (defaults, suiteName) = makeTestDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        runOnMain {
            ReviewReminderManager.setIntervalDays(0, defaults: defaults)
            #expect(ReviewReminderManager.isEnabled(defaults: defaults) == false)
        }
    }

    @Test("isEnabled returns true when intervalDays is positive")
    func isEnabledTrueWhenPositive() {
        let (defaults, suiteName) = makeTestDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        runOnMain {
            ReviewReminderManager.setIntervalDays(7, defaults: defaults)
            #expect(ReviewReminderManager.isEnabled(defaults: defaults) == true)
        }
    }

    @Test("intervalDays getter and setter round-trip through UserDefaults")
    func intervalDaysRoundTrip() {
        let (defaults, suiteName) = makeTestDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        runOnMain {
            ReviewReminderManager.setIntervalDays(14, defaults: defaults)
            #expect(ReviewReminderManager.intervalDays(defaults: defaults) == 14)

            ReviewReminderManager.setIntervalDays(30, defaults: defaults)
            #expect(ReviewReminderManager.intervalDays(defaults: defaults) == 30)
        }
    }

    @Test("disableReminder sets intervalDays to zero")
    func disableReminderSetsZero() {
        let (defaults, suiteName) = makeTestDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        runOnMain {
            ReviewReminderManager.setIntervalDays(14, defaults: defaults)
            #expect(ReviewReminderManager.isEnabled(defaults: defaults) == true)

            ReviewReminderManager.disableReminder(defaults: defaults)
            #expect(ReviewReminderManager.intervalDays(defaults: defaults) == 0)
            #expect(ReviewReminderManager.isEnabled(defaults: defaults) == false)
        }
    }

    @Test("rescheduleIfEnabled does nothing when disabled")
    func rescheduleIfEnabledNoop() {
        let (defaults, suiteName) = makeTestDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        runOnMain {
            ReviewReminderManager.setIntervalDays(0, defaults: defaults)
            // Should not crash or throw
            ReviewReminderManager.rescheduleIfEnabled(defaults: defaults)
            #expect(ReviewReminderManager.isEnabled(defaults: defaults) == false)
        }
    }

    @Test("rescheduleIfEnabled runs when enabled without crashing")
    func rescheduleIfEnabledWhenActive() {
        let (defaults, suiteName) = makeTestDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        runOnMain {
            ReviewReminderManager.setIntervalDays(7, defaults: defaults)
            // Should not crash — notification center may deny permission in tests
            // but the method should still complete.
            ReviewReminderManager.rescheduleIfEnabled(defaults: defaults)
            #expect(ReviewReminderManager.isEnabled(defaults: defaults) == true)
        }
    }

    @Test("enableReminder sets intervalDays and marks as enabled")
    func enableReminderSetsInterval() {
        let (defaults, suiteName) = makeTestDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        runOnMain {
            ReviewReminderManager.enableReminder(intervalDays: 21, defaults: defaults)
            #expect(ReviewReminderManager.intervalDays(defaults: defaults) == 21)
            #expect(ReviewReminderManager.isEnabled(defaults: defaults) == true)
        }
    }

    @Test("enableReminder with default interval uses 14 days")
    func enableReminderDefaultInterval() {
        let (defaults, suiteName) = makeTestDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        runOnMain {
            ReviewReminderManager.enableReminder(defaults: defaults)
            #expect(ReviewReminderManager.intervalDays(defaults: defaults) == 14)
        }
    }
}
