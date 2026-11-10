import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

let sampleJSON = Data("""
{
  "name": "DemoPackage",
  "targets": [
    {
      "name": "Networking",
      "type": "library",
      "path": "Sources/Networking",
      "sources": ["HttpClient.swift", "URLSession+Extensions.swift"],
      "target_dependencies": ["Core"]
    },
    {
      "name": "UI",
      "type": "library",
      "path": "Sources/UI",
      "sources": ["LoginView.swift"],
      "target_dependencies": ["Networking"]
    },
    {
      "name": "DemoPackageTests",
      "type": "test",
      "path": "Tests/DemoPackageTests",
      "sources": ["NetworkingTests.swift"],
      "target_dependencies": ["Networking"]
    }
  ]
}
""".utf8)
