import Foundation
import SwiftUMLBridgeFramework

/// The entry points and state machines `DiagramViewModel` lists for the selection, scanned in
/// background tasks (#281). Split out of `DiagramViewModel+Workspace.swift`.
extension DiagramViewModel {

    /// Refreshes whatever the current mode derives from the selection: the entry points of a
    /// sequence or activity diagram, or the state machines of a state diagram.
    ///
    /// This decision existed twice in `ContentView` — on a mode change and in the `selectedPaths`
    /// observer — and the two copies disagreed. One guarded each call with `!selectedPaths.isEmpty`;
    /// the other did not.
    ///
    /// That guard reads like an optimisation and is not one. `refreshEntryPoints()` and
    /// `refreshStateMachines()` both empty their list when there is no selection — that is *what
    /// they do* then. Skipping the call therefore skipped the clearing, so switching to Sequence
    /// Diagram with nothing selected left the entry-point picker showing candidates from files that
    /// were no longer selected, while clearing the selection emptied it correctly.
    ///
    /// One copy, no caller-side guard: every path clears. `loadDiagram(_:)` calls it too.
    ///
    /// The other modes' scans are cancelled (#281). A state-machine scan that finished after the
    /// user left State Machine could still move `stateIdentifier`, and its change restarted the
    /// current mode's generation.
    func refreshModeDerivedData() {
        switch diagramMode {
        case .sequenceDiagram, .activityDiagram:
            stateMachinesTask?.cancel()
            refreshEntryPoints()

        case .stateMachine:
            entryPointsTask?.cancel()
            refreshStateMachines()

        default:
            entryPointsTask?.cancel()
            stateMachinesTask?.cancel()
        }
    }

    /// Lists the selected files' entry points in `availableEntryPoints`. The files are parsed in
    /// a background task, `entryPointsTask`, which a newer scan cancels (#281): parsing them here
    /// froze the window for as long as a large selection or a slow file took. Its result is
    /// dropped when it was cancelled or the selection has changed since, so the list never shows
    /// another selection's entry points. A cancelled scan parses no further file
    /// (`ParsingStack.parse`). With nothing selected the list empties at once.
    func refreshEntryPoints() {
        entryPointsTask?.cancel()
        guard !selectedPaths.isEmpty else {
            entryPointsTask = nil
            availableEntryPoints = []
            return
        }
        let paths = selectedPaths
        let generator = sequenceGenerator
        entryPointsTask = Task {
            let found = await cancellableDetached { generator.findEntryPoints(for: paths) }
            guard !Task.isCancelled, selectedPaths == paths else { return }
            availableEntryPoints = found
        }
    }

    /// Lists the selected files' state machines in `availableStateMachines`, in a background task,
    /// `stateMachinesTask`, as `refreshEntryPoints()` lists entry points (#281). When the result is
    /// kept and does not list `stateIdentifier`, the identifier moves to the machine it names or
    /// to the first one; a dropped result leaves it alone.
    func refreshStateMachines() {
        stateMachinesTask?.cancel()
        guard !selectedPaths.isEmpty else {
            stateMachinesTask = nil
            availableStateMachines = []
            return
        }
        let paths = selectedPaths
        let generator = stateGenerator
        stateMachinesTask = Task {
            let found = await cancellableDetached { generator.findCandidates(for: paths) }
            guard !Task.isCancelled, selectedPaths == paths else { return }
            availableStateMachines = found
            let identifiers = found.map(\.identifier)
            if !identifiers.contains(stateIdentifier) {
                // A diagram saved before names were read as Swift reads them may spell one with
                // backticks it doesn't need, as in `` `Lamp`.Light ``, which is now listed `Lamp.Light`.
                let listed = StateMachineGenerator.listedIdentifier(stateIdentifier)
                stateIdentifier = identifiers.contains(listed) ? listed : identifiers.first ?? ""
            }
        }
    }
}
