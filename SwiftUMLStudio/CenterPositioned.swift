import CoreGraphics
import SwiftUMLBridgeFramework

/// A layout element positioned by its center point and size.
protocol CenterPositioned {
    var centerX: Double { get }
    var centerY: Double { get }
    var width: Double { get }
    var height: Double { get }
}

extension CenterPositioned {
    /// The element's frame as a top-left-origin `CGRect`, converting from the
    /// center-based coordinates the layout engine produces.
    var boundingRect: CGRect {
        CGRect(
            x: centerX - width / 2,
            y: centerY - height / 2,
            width: width,
            height: height
        )
    }
}

extension PositionedActivityNode: CenterPositioned {}
extension PositionedComponent: CenterPositioned {}
