import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

@Suite("ParsingStack")
struct ParsingStackTests {

    @Test("runs its body on a thread with the large stack")
    func runsOnTheLargeStack() {
        #expect(ParsingStack.run { Thread.current.stackSize } >= ParsingStack.size)
    }

    /// `Thread.current` is unavailable in async code, so the task reads it through these.
    private static func callerQualityOfService() -> QualityOfService { Thread.current.qualityOfService }
    private static func parsingQualityOfService() -> QualityOfService {
        ParsingStack.run { Thread.current.qualityOfService }
    }

    @Test("runs its body at the caller's quality of service", arguments: [
        TaskPriority.userInitiated, .utility, .background
    ])
    func keepsTheCallersQualityOfService(priority: TaskPriority) async {
        let (caller, parsing) = await Task.detached(priority: priority) {
            (Self.callerQualityOfService(), Self.parsingQualityOfService())
        }.value
        #expect(parsing == caller)
    }

    @Test("stays on its thread when it is already on a large stack")
    func nestedRunStaysOnItsThread() {
        let sameThread = ParsingStack.run {
            let outer = ObjectIdentifier(Thread.current)
            return ParsingStack.run { ObjectIdentifier(Thread.current) } == outer
        }
        #expect(sameThread)
    }
}
