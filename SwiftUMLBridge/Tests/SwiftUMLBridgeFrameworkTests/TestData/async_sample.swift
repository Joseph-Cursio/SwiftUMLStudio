import Foundation

class DataService {
    func loadData(from url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    func processItems() async -> [String] {
        []
    }
}
