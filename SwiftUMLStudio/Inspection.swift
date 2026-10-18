import Combine

/// Lets ViewInspector inspect a view while SwiftUI hosts it, so the view's
/// `@State` is installed when its body is read. A view that holds `@State`
/// keeps an `inspection` and forwards `notice` to `visit` with `onReceive`;
/// nothing sends `notice` outside the unit tests.
final class Inspection<V> {
    let notice = PassthroughSubject<UInt, Never>()
    var callbacks: [UInt: (V) -> Void] = [:]

    func visit(_ view: V, _ line: UInt) {
        if let callback = callbacks.removeValue(forKey: line) {
            callback(view)
        }
    }
}
