//
//  DiagramMode.swift
//  SwiftPlantUMLstudio
//
//  Created by joe cursio on 2/27/26.
//

import Foundation

enum DiagramMode: String, CaseIterable, Identifiable {
    case classDiagram = "Class Diagram"
    case sequenceDiagram = "Sequence Diagram"
    case dependencyGraph = "Dependency Graph"
    var id: String { rawValue }
}
