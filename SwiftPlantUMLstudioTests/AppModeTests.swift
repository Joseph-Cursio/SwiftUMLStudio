import Testing
@testable import SwiftPlantUMLstudio

struct AppModeTests {

    @Test("has exactly two cases")
    func allCasesCount() {
        #expect(AppMode.allCases.count == 2)
    }

    @Test("explorer raw value is 'Explorer'")
    func explorerRawValue() {
        #expect(AppMode.explorer.rawValue == "Explorer")
    }

    @Test("developer raw value is 'Developer'")
    func developerRawValue() {
        #expect(AppMode.developer.rawValue == "Developer")
    }

    @Test("init from raw value roundtrips")
    func rawValueRoundtrip() {
        for mode in AppMode.allCases {
            #expect(AppMode(rawValue: mode.rawValue) == mode)
        }
    }
}
