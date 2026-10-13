//
//  ReviewReminderManagerTests.swift
//  SwiftUMLStudioTests
//
//  Unit tests for ReviewReminderManager scheduling and state logic.
//

import Foundation
import Testing
@testable import SwiftUMLStudio

// MARK: - ReviewReminderManager Tests

// Each test keeps its interval in memory: `UserDefaults.standard` is the developer's own
// defaults in this app-hosted bundle, and a throwaway suite leaves its plist behind in
// ~/Library/Preferences.
@Suite("ReviewReminderManager") @MainActor
struct ReviewReminderManagerTests {

    @Test("isEnabled returns false when intervalDays is zero")
    func isEnabledFalseWhenZero() {
        let defaults = InMemoryKeyValueStore()
        ReviewReminderManager.setIntervalDays(0, defaults: defaults)
        #expect(ReviewReminderManager.isEnabled(defaults: defaults) == false)
    }

    @Test("isEnabled returns true when intervalDays is positive")
    func isEnabledTrueWhenPositive() {
        let defaults = InMemoryKeyValueStore()
        ReviewReminderManager.setIntervalDays(7, defaults: defaults)
        #expect(ReviewReminderManager.isEnabled(defaults: defaults) == true)
    }

    @Test("intervalDays getter and setter round-trip through the store")
    func intervalDaysRoundTrip() {
        let defaults = InMemoryKeyValueStore()
        ReviewReminderManager.setIntervalDays(14, defaults: defaults)
        #expect(ReviewReminderManager.intervalDays(defaults: defaults) == 14)

        ReviewReminderManager.setIntervalDays(30, defaults: defaults)
        #expect(ReviewReminderManager.intervalDays(defaults: defaults) == 30)
    }

    @Test("disableReminder sets intervalDays to zero")
    func disableReminderSetsZero() {
        let defaults = InMemoryKeyValueStore()
        ReviewReminderManager.setIntervalDays(14, defaults: defaults)
        #expect(ReviewReminderManager.isEnabled(defaults: defaults) == true)

        ReviewReminderManager.disableReminder(defaults: defaults)
        #expect(ReviewReminderManager.intervalDays(defaults: defaults) == 0)
        #expect(ReviewReminderManager.isEnabled(defaults: defaults) == false)
    }

    @Test("rescheduleIfEnabled does nothing when disabled")
    func rescheduleIfEnabledNoop() {
        let defaults = InMemoryKeyValueStore()
        ReviewReminderManager.setIntervalDays(0, defaults: defaults)
        // Should not crash or throw
        ReviewReminderManager.rescheduleIfEnabled(defaults: defaults)
        #expect(ReviewReminderManager.isEnabled(defaults: defaults) == false)
    }

    @Test("rescheduleIfEnabled runs when enabled without crashing")
    func rescheduleIfEnabledWhenActive() {
        let defaults = InMemoryKeyValueStore()
        ReviewReminderManager.setIntervalDays(7, defaults: defaults)
        // Should not crash — notification center may deny permission in tests
        // but the method should still complete.
        ReviewReminderManager.rescheduleIfEnabled(defaults: defaults)
        #expect(ReviewReminderManager.isEnabled(defaults: defaults) == true)
    }

    @Test("enableReminder sets intervalDays and marks as enabled")
    func enableReminderSetsInterval() {
        let defaults = InMemoryKeyValueStore()
        ReviewReminderManager.enableReminder(intervalDays: 21, defaults: defaults)
        #expect(ReviewReminderManager.intervalDays(defaults: defaults) == 21)
        #expect(ReviewReminderManager.isEnabled(defaults: defaults) == true)
    }

    @Test("enableReminder with default interval uses 14 days")
    func enableReminderDefaultInterval() {
        let defaults = InMemoryKeyValueStore()
        ReviewReminderManager.enableReminder(defaults: defaults)
        #expect(ReviewReminderManager.intervalDays(defaults: defaults) == 14)
    }
}
