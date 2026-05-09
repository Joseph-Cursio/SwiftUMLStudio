import Foundation

/// SwiftUI routing path: a route enum driven by a router class with explicit
/// transition methods that switch on the current route and self-assign the
/// next one. Mirrors common `NavigationStack` / `NavigationPath` patterns.
public final class NavigationRouter {
    public enum Route {
        case list
        case detail
        case settings
    }

    public private(set) var route: Route = .list

    public func openDetail() {
        switch self.route {
        case .list:
            self.route = .detail
        case .detail, .settings:
            break
        }
    }

    public func openSettings() {
        switch self.route {
        case .list, .detail:
            self.route = .settings
        case .settings:
            break
        }
    }

    public func goBack() {
        switch self.route {
        case .detail:
            self.route = .list
        case .settings:
            self.route = .list
        case .list:
            break
        }
    }
}
