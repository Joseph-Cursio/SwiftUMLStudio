import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

@Suite("SPMPackageDescription.sourceFileToModuleMap")
struct SPMPackageDescriptionMapTests {

    @Test("joins target.path + each source path under packageRoot")
    func joinsPaths() throws {
        let pkg = try SPMPackageReader.parse(sampleJSON)
        let root = URL(fileURLWithPath: "/Users/me/DemoPackage")
        let map = pkg.sourceFileToModuleMap(packageRoot: root)
        #expect(map["/Users/me/DemoPackage/Sources/Networking/HttpClient.swift"] == "Networking")
        #expect(map["/Users/me/DemoPackage/Sources/UI/LoginView.swift"] == "UI")
    }

    @Test("excludes test targets from the map")
    func excludesTests() throws {
        let pkg = try SPMPackageReader.parse(sampleJSON)
        let root = URL(fileURLWithPath: "/Users/me/DemoPackage")
        let map = pkg.sourceFileToModuleMap(packageRoot: root)
        #expect(map["/Users/me/DemoPackage/Tests/DemoPackageTests/NetworkingTests.swift"] == nil)
    }
}
