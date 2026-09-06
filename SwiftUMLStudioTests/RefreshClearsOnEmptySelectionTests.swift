//
//  RefreshClearsOnEmptySelectionTests.swift
//  SwiftUMLStudioTests
//
//  An empty selection clears what was derived from the old one.
//

import Foundation
import Testing
@testable import SwiftUMLStudio

/// Refreshing with nothing selected empties the derived lists rather than leaving them.
///
/// `refreshEntryPoints()` and `refreshStateMachines()` both open with
/// `guard !selectedPaths.isEmpty else { … = []; return }` — emptying the list is what they *do*
/// when there is no selection, not a fast path out of doing anything.
///
/// `ContentView` had guarded its calls with `!selectedPaths.isEmpty` on one of the two paths that
/// make them, which skipped the call and therefore skipped the clearing. Switching to Sequence
/// Diagram with nothing selected left the entry-point picker showing candidates from files that
/// were no longer selected, while clearing the selection emptied it correctly — two paths that
/// should agree, disagreeing.
///
/// These pin the contract the caller was working against, so a future caller-side guard has
/// something to fail.
@Suite("An empty selection clears what the old one derived") @MainActor
struct RefreshClearsOnEmptySelectionTests {

    @Test("refreshEntryPoints clears stale entry points")
    func entryPointsAreClearedWhenNothingIsSelected() {
        let viewModel = DiagramViewModel()
        viewModel.availableEntryPoints = ["Stale.run", "AlsoStale.go"]
        viewModel.selectedPaths = []

        viewModel.refreshEntryPoints()

        #expect(viewModel.availableEntryPoints.isEmpty,
                "entry points from a previous selection survived an empty one")
    }

    @Test("refreshStateMachines clears stale candidates")
    func stateMachinesAreClearedWhenNothingIsSelected() {
        let viewModel = DiagramViewModel()
        viewModel.availableStateMachines = []
        viewModel.selectedPaths = []

        viewModel.refreshStateMachines()

        #expect(viewModel.availableStateMachines.isEmpty)
    }

    /// Clearing is idempotent, which is what makes calling it unconditionally safe — the reason
    /// the caller-side guard could be removed rather than duplicated into the second path.
    @Test("clearing twice is the same as clearing once")
    func clearingIsIdempotent() {
        let viewModel = DiagramViewModel()
        viewModel.availableEntryPoints = ["Stale.run"]
        viewModel.selectedPaths = []

        viewModel.refreshEntryPoints()
        let afterFirst = viewModel.availableEntryPoints
        viewModel.refreshEntryPoints()

        #expect(viewModel.availableEntryPoints == afterFirst)
    }
}
