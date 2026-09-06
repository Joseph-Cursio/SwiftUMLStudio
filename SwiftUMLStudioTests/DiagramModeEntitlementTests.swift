import Testing
@testable import SwiftUMLStudio

/// Which diagram modes are paid, stated once and checkable.
///
/// The pairing used to be six near-identical `if` blocks inside an `onChange` closure in
/// `ContentView`. Paywall enforcement is business logic, and it lived where no test could call it:
/// there was no name to invoke and no seam to reach it through. A mode paired with the wrong
/// entitlement, or a new mode added to the enum and forgotten, would have shipped silently — the
/// second one giving a paid feature away for free.
///
/// Moving the pairing to `DiagramMode.requiredFeature` makes it total by construction. These pin
/// what that totality is worth.
@Suite("Every diagram mode declares what it costs")
struct DiagramModeEntitlementTests {

    /// The regression that omission would cause. `classDiagram` is the only free mode, so any
    /// other case returning `nil` is a paid feature given away.
    @Test("every mode except the class diagram requires an entitlement")
    func onlyTheClassDiagramIsFree() {
        for mode in DiagramMode.allCases where mode != .classDiagram {
            #expect(mode.requiredFeature != nil, "\(mode) is not gated, so it is free")
        }
        #expect(DiagramMode.classDiagram.requiredFeature == nil)
    }

    /// Two modes sharing an entitlement would mean unlocking one silently unlocks the other —
    /// invisible at the call site, because each block named its own feature.
    @Test("no two modes share an entitlement")
    func entitlementsAreDistinct() {
        let required = DiagramMode.allCases.compactMap(\.requiredFeature)
        #expect(Set(required).count == required.count, "duplicate entitlements in \(required)")
    }

    /// The mapping is a function of the mode alone — no clock, no subscription state, no view.
    /// That is what lets the two properties above be asserted at all.
    @Test("the entitlement is the same every time it is asked")
    func mappingIsDeterministic() {
        for mode in DiagramMode.allCases {
            #expect(mode.requiredFeature == mode.requiredFeature)
        }
    }
}
