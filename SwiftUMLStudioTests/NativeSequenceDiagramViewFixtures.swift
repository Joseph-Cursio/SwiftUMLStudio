//  Tests for NativeSequenceDiagramView — the sequence diagram canvas.
//
//  No ViewInspector here, deliberately: the body is a `GeometryReader`, and
//  ViewInspector 0.10.3 traps fabricating a `GeometryProxy` on macOS 27 beta,
//  killing the test process rather than failing a test. See the fuller note in
//  NativeDiagramViewTests.swift.
//
//  `ImageRenderer` drives a real draw pass instead. The pure geometry lives in
//  `NativeSequenceGeometry` (covered by NativeSequenceGeometryTests); what is
//  covered here is the drawing itself and the keyboard-selection logic, which a
//  render pass never fires.

import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

// MARK: - Fixtures

func makeParticipant(
    name: String,
    centerX: Double,
    topY: Double = 20,
    width: Double = 120,
    height: Double = 36,
    bottomTopY: Double = 420
) -> SequenceParticipant {
    SequenceParticipant(
        name: name, centerX: centerX, topY: topY,
        width: width, height: height, bottomTopY: bottomTopY
    )
}

func makeMessage(
    id: Int,
    label: String,
    fromX: Double,
    toX: Double,
    posY: Double,
    isAsync: Bool = false,
    isUnresolved: Bool = false,
    noteText: String? = nil
) -> SequenceMessage {
    SequenceMessage(
        id: id, label: label, fromX: fromX, toX: toX, posY: posY,
        isAsync: isAsync, isUnresolved: isUnresolved, noteText: noteText
    )
}

/// A layout reaching every drawing branch: a left-to-right call, a
/// right-to-left return, a self-loop, an async message, an unresolved one, and
/// a message carrying a note.
@MainActor
func richLayout() -> SequenceLayout {
    SequenceLayout(
        participants: [
            makeParticipant(name: "Caller", centerX: 100),
            makeParticipant(name: "Service", centerX: 320),
            makeParticipant(name: "Store", centerX: 540),
        ],
        messages: [
            makeMessage(id: 0, label: "fetch()", fromX: 100, toX: 320, posY: 90),
            makeMessage(id: 1, label: "load()", fromX: 320, toX: 540, posY: 140, isAsync: true),
            makeMessage(id: 2, label: "retry()", fromX: 540, toX: 540, posY: 190),
            makeMessage(id: 3, label: "result", fromX: 540, toX: 320, posY: 250),
            makeMessage(
                id: 4, label: "unknown()", fromX: 320, toX: 700, posY: 300,
                isUnresolved: true
            ),
            makeMessage(
                id: 5, label: "done()", fromX: 320, toX: 100, posY: 350,
                noteText: "cached for 5 minutes"
            ),
        ],
        title: "Caller.fetch()",
        totalWidth: 700,
        totalHeight: 480,
        lifelineStartY: 56,
        lifelineEndY: 420
    )
}
