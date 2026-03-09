//
//  DiagramWebViewTests.swift
//  SwiftPlantUMLstudioTests
//
//  Created by Gemini on 3/7/26.
//
// NOTE: DiagramWebView now uses the native SwiftUI WebView/WebPage APIs (macOS 26+).
// The WKWebView-based coordinator methods (makeCoordinator, updateNSView, plantUMLURL)
// were removed when the view was rewritten. HTML escaping is tested via MermaidHTMLBuilder
// in the Swift Testing suite (SwiftPlantUMLstudioTests.swift).

import XCTest
import SwiftUI
@testable import SwiftPlantUMLstudio

@MainActor
final class DiagramWebViewXCTests: XCTestCase {

    func testDiagramWebViewIsAView() {
        // Verify the type is a View; instantiation must not crash.
        let view = DiagramWebView(script: nil)
        let hosting = NSHostingView(rootView: view)
        XCTAssertNotNil(hosting)
    }
}
