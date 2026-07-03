# ``SwiftUMLBridgeFramework``

Generate architectural diagrams from Swift source — class, sequence, activity, state-machine, entity-relationship, dependency, and component diagrams.

## Overview

SwiftUMLBridgeFramework parses Swift source with SourceKitten and SwiftSyntax,
builds a language-agnostic model of the code, and emits diagrams in a range of
formats (PlantUML, Mermaid, Nomnoml) or hands positioned layout data to a native
renderer. It is the engine behind the `swiftumlbridge` command-line tool and the
SwiftUMLStudio macOS app.

The framework is organized in three layers:

- **Parsing** — extracts declarations, call graphs, control flow, and import
  edges from Swift source.
- **Model** — a language-agnostic representation of types, relationships, call
  graphs, control-flow graphs, state machines, ER schemas, and SPM package
  structure.
- **Emitters** — turn a model into a ``DiagramScript`` (or a diagram-specific
  script) in the requested ``DiagramFormat``, or into positioned layout data for
  native rendering.

Each diagram type has a generator with a matching protocol (for test injection),
for example ``ClassDiagramGenerator`` conforming to ``ClassDiagramGenerating``.
See <doc:GeneratingDiagrams> to get started.

## Topics

### Essentials

- <doc:GeneratingDiagrams>

### Generating Diagrams

- ``ClassDiagramGenerator``
- ``ClassDiagramGenerating``
- ``SequenceDiagramGenerator``
- ``SequenceDiagramGenerating``
- ``ActivityDiagramGenerator``
- ``ActivityDiagramGenerating``
- ``StateMachineGenerator``
- ``StateMachineGenerating``
- ``ERDiagramGenerator``
- ``ERDiagramGenerating``
- ``DependencyGraphGenerator``
- ``DependencyGraphGenerating``
- ``ComponentDiagramGenerator``
- ``ComponentDiagramGenerating``

### Configuration

- ``Configuration``
- ``ConfigurationProvider``
- ``FileOptions``
- ``ElementOptions``
- ``RelationshipOptions``
- ``Relationship``
- ``RelationshipStyle``
- ``AccessLevel``
- ``ExtensionVisualization``
- ``DiagramFormat``

### Stereotypes & Theming

- ``Stereotypes``
- ``Stereotype``
- ``Spot``
- ``Theme``
- ``Color``
- ``PageTexts``

### Emitted Scripts & Presentation

- ``DiagramScript``
- ``SequenceScript``
- ``ActivityScript``
- ``StateScript``
- ``ERScript``
- ``DepsScript``
- ``ComponentScript``
- ``DiagramPresenting``
- ``DiagramOutputting``
- ``BrowserPresenter``
- ``ConsolePresenter``
- ``BrowserPresentationFormat``

### Class & Type Model

- ``TypeInfo``
- ``SourceLocation``

### Sequence Model

- ``CallGraph``
- ``CallEdge``
- ``SequenceLayout``
- ``SequenceParticipant``
- ``SequenceMessage``

### Activity Model

- ``ActivityGraph``
- ``ActivityNode``
- ``ActivityEdge``
- ``ActivityNodeKind``
- ``ActivityLayout``
- ``PositionedActivityNode``

### State-Machine Model

- ``StateMachineModel``
- ``StateMachineState``
- ``StateTransition``

### Entity-Relationship Model

- ``ERModel``
- ``EREntity``
- ``ERAttribute``
- ``ERRelationship``
- ``ERCardinality``

### Dependency Model

- ``DependencyGraphModel``
- ``DependencyEdge``
- ``DependencyEdgeKind``
- ``ImportEdge``
- ``DepsMode``

### Component & Package Model

- ``ComponentModel``
- ``Component``
- ``ComponentDependency``
- ``ComponentLayout``
- ``PositionedComponent``
- ``SPMPackageDescription``
- ``SPMTargetDescription``
- ``SPMPackageReader``

### Layout

- ``LayoutGraph``
- ``LayoutNode``
- ``LayoutEdge``
- ``LayoutPoint``
- ``LayoutCluster``
- ``NodeCompartment``
- ``DagreLayoutEngine``

### Rendering

- ``SVGRenderer``
- ``SequenceSVGRenderer``
- ``ActivitySVGRenderer``
- ``ComponentSVGRenderer``

### Parsing & Extraction

- ``ActivityFlowExtractor``
- ``ComponentExtractor``
- ``CoreDataModelExtractor``
- ``PersistenceSchemaExtractor``
- ``FileCollector``

### Utilities

- ``BridgeLogger``
- ``BridgeConfiguration``
- ``Version``
