import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

@Suite("SPMPackageReader.describe")
struct SPMPackageReaderDescribeTests {

    @Test("describe(at:) on a directory without a manifest throws swiftToolFailed")
    func describeFailsWithoutManifest() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("not-a-package-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        #expect(throws: SPMPackageReader.ReadError.self) {
            _ = try SPMPackageReader.describe(at: tempRoot)
        }
    }
}
