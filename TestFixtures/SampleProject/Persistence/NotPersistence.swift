import Foundation

/// Negative case for the persistence detector: a plain Swift type that does
/// not conform to any GRDB record protocol or carry SwiftData macros.
/// Extractors must produce zero entities for this file.
public struct ShoppingCart {
    public var items: [String]
    public var subtotal: Decimal
}

public class Catalog {
    public var name: String = ""
    public var products: [String] = []
}
