//
//  DiagramMode.swift
//  SwiftUMLStudio
//
//  Created by joe cursio on 2/27/26.
//

import Foundation

enum DiagramMode: String, CaseIterable, Identifiable {
    case classDiagram = "Class Diagram"
    case sequenceDiagram = "Sequence Diagram"
    case dependencyGraph = "Dependency Graph"
    case stateMachine = "State Machine"
    case activityDiagram = "Activity Diagram"
    case erDiagram = "ER Diagram"
    case componentDiagram = "Component Diagram"
    var id: String { rawValue }

    /// The entitlement this mode needs, or `nil` when it is free.
    ///
    /// The pairing used to live in `ContentView` as six near-identical `if` blocks — one per paid
    /// mode, each naming its own feature and each repeating the same three-line fallback. Six
    /// copies of one rule is six chances to pair a mode with the wrong entitlement, and an eighth
    /// mode added to this enum would have been free by omission: nothing forced the list to be
    /// complete.
    ///
    /// Stated here it is total by construction — the switch will not compile without a new case —
    /// and it is a pure function of the mode, so it can be checked without standing up a view.
    /// `nonisolated` because it is a lookup on an enum case. The app target isolates to the main
    /// actor by default, which a pure mapping has no need of — and inheriting it would mean every
    /// test asking what a mode costs had to hop to the main actor to find out.
    nonisolated var requiredFeature: ProFeature? {
        switch self {
        case .classDiagram: return nil
        case .sequenceDiagram: return .sequenceDiagrams
        case .dependencyGraph: return .dependencyGraphs
        case .stateMachine: return .stateMachines
        case .activityDiagram: return .activityDiagrams
        case .erDiagram: return .erDiagrams
        case .componentDiagram: return .componentDiagrams
        }
    }
}
