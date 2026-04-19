# Testing Guide

This project consists of a macOS SwiftUI app (**SwiftUMLStudio**) and a core logic framework (**SwiftUMLBridge**). Due to the nature of static analysis and Core Data, different testing strategies apply to each component.

## Summary

| Component | Test Framework | How to Run | Notes |
| :--- | :--- | :--- | :--- |
| **SwiftUMLBridge** | Swift Testing | `cd SwiftUMLBridge && xcrun swift test` | **Primary** location for parsing and generation logic. |
| **App Unit/Integration** | Swift Testing | Xcode / `xcodebuild test` | App-specific wiring and Core Data. |
| **App UI** | XCTest | Xcode / `xcodebuild test` | End-to-end UI flows. |

---

## 1. SwiftUMLBridge (Logic Framework)

The core logic for parsing Swift and generating PlantUML/Mermaid diagrams lives in the `SwiftUMLBridge` package.

### Why run via CLI?
These tests require access to `sourcekitd` (via SourceKitten). The Xcode app test host does not provide the necessary toolchain environment (SDK paths, etc.) for `sourcekitd` to function, leading to hangs.

**Always run these tests using the Swift Package Manager:**
```bash
cd SwiftUMLBridge
xcrun swift test
```

---

## 2. SwiftUMLStudio (App)

### Unit & Integration Tests
Located in `SwiftUMLStudioTests`. These use **Swift Testing**.

**Known Issues & Workarounds:**
*   **Main Actor Executor:** On macOS 26 beta, the Swift Concurrency main-actor executor is unstable in the Xcode test host. We use a `runOnMain` helper (GCD-based) to ensure tests run reliably on the main thread.
*   **Core Data:** Tests use an in-memory store. Ensure `DiagramEntity` has `representedClassName` set in the `.xcdatamodeld` to avoid runtime mapping errors.

### UI Tests
Located in `SwiftUMLStudioUITests`. These use **XCTest** (required for UI automation).

---

## 3. Running All App Tests via CLI

To run the app-target tests (Unit + UI) from the command line:

```bash
xcodebuild test \
  -scheme SwiftUMLStudio \
  -destination 'platform=macOS,arch=arm64' \
  -parallel-testing-enabled NO
```
*(Note: Parallel testing is disabled to provide clearer logs in case of Core Data or MainActor conflicts.)*
