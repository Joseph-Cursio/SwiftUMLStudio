# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This file covers both the **SwiftUMLBridge** package (CLI + framework) and the **SwiftUMLStudio** macOS app.

---

## [Unreleased]

### Added — Studio

- **A Settings window, with a toggle to withdraw PlantUML consent.**
  **Settings…** in the app menu (⌘,) offers **Render PlantUML previews
  with planttext.com**. Until now a grant could only be withdrawn with
  `defaults delete` (a decline could already be changed, since the card
  comes back on the next PlantUML preview). Turning the toggle on grants
  consent; turning it off returns it to undecided — not to declined,
  which would also switch a direct build's launch format to Mermaid.
  Either way the next PlantUML preview asks again. It takes effect at once: the consent store
  is observable, so a PlantUML preview already on screen goes back to
  the card. The card now says the choice can be changed in Settings.

### Fixed — Studio (test infrastructure)

- **The UI test suite runs again — all 30 tests, which had been failing.**
  The symptom pointed away from the cause: the app launched, took the
  menu bar, and exposed no window, so every "assert exists" failed while
  the one "assert absent" and both launch tests passed. That reads like a
  permissions problem, and it was not one. The accessibility hierarchy was
  fully populated — 210 menu items, no window — and the app process has
  neither `XCTestConfigurationFilePath` nor `XCTest` loaded, so the app's
  own test gates were not firing either.

  Sampling the process mid-test found the main thread busy rather than
  blocked, 348 of 742 samples deep in `showInitialWindows()` →
  `makeMainWindow` → `updateToolbarBridge` → `ToolbarBridge.makeStorage` →
  `ViewGraph.updateOutputs`. The window was still being built when the 2-
  and 3-second waits expired. `xcodebuild test` runs the app under
  code-coverage instrumentation — `LLVM_PROFILE_FILE` and the `PERFC_*`
  variables appear only in that launch — and the instrumented first render
  is far slower; the same tests pass with `-enableCodeCoverage NO`.
  Coverage is wanted (the Studio target has a ≥ 70% bar that counts UI
  tests), so the 48 waits move to a shared `UITestTimeout.element` of 30s
  with the diagnosis recorded beside the constant. The old values were
  marginal regardless: uninstrumented, the slowest came in at 3.4s against
  a 3s limit.

- **Five UI tests that passed without asserting anything now assert.**
  Raising the timeouts turned the suite green but left those five
  spending a full 30s in a wait that never resolved, then passing via an
  `||` fallback, a `guard … else { return }`, or an `if` that skipped the
  work. Each query was stale: `detailTabs` is a `TabGroup` rather than a
  `Group` and its children are `Tab` rather than `Button`; the format
  picker is a `PopUpButton` identified `formatPicker`, not a `RadioGroup`
  labelled "Format"; and the Explorer mode option is a `RadioButton` in
  the `appModePicker` group, not a `StaticText`. Two assertions changed
  with them — the default-format check matches on prefix because M14
  relabelled the option `PlantUML (planttext.com)`, and the mode check
  reads `AXValue` because SwiftUI does not set `AXSelected` on radio
  buttons. Soft skips are now hard assertions. Runtime fell from 320s to
  182s, and no test sits near the timeout, which is the evidence that
  every wait resolves.

- `*.profraw` / `*.profdata` are gitignored — an instrumented test run
  drops one in the repository root.

- **Running the Studio unit tests no longer clears your PlantUML
  consent, and the UI tests no longer upload to planttext.com.** The unit
  tests run inside the app, so `PlantUMLConsentTests`' `revoke()` on
  `UserDefaults.standard` reset the developer's own decision every run;
  the consent store now takes a `UserDefaults`, and the tests use
  throwaway suites. The UI tests launched the direct build on its
  PlantUML default with the SampleProject fixture, sending its diagram to
  planttext.com on each run; they now pin consent to undecided through
  launch arguments, which are never written back, and assert the consent
  card in place of a planttext.com web view.

- **The Studio unit tests no longer leave empty plists in
  `~/Library/Preferences`.** The consent tests and
  `ReviewReminderManagerTests` gave each test its own
  `UserDefaults(suiteName:)` suite (`test-plantuml-consent-<UUID>`,
  `test-<UUID>`) and removed the domain afterwards. cfprefsd still keeps
  an empty `<suite>.plist` for every suite written to, so each run added
  a few dozen files; 320+ consent and 153 reminder files had piled up.
  Deleting them from the tests would race cfprefsd. Instead,
  `PlantUMLConsent` and `ReviewReminderManager` now read and write
  through a `KeyValueStore` protocol — the five `UserDefaults` methods
  they use, with `UserDefaults` conforming as is. The app still passes
  `.standard` under the same keys, so existing consent and reminder
  settings carry over. The tests use an in-memory store.
  `KeyValueStoreTests` runs the same checks against that store and
  against `UserDefaults`, through one fixed suite,
  `name.JosephCursio.SwiftUMLStudio.UnitTests`, which every run reuses.
  The leftover files can be removed once each is checked to hold `{}`.

### Fixed — Bridge

- **A comment beside a name is not part of it** (#128). The ER,
  state-machine and call-graph readers read a name with the comment
  after it on its line and the comment lines above it. So:
  - `@Model // persisted` was not an entity, `@Transient // cached` not
    transient, and `var owner: Owner? // may be nil` not a relationship.
  - `var state: Light // current` was not a state machine.
  - A comment line above `Store.shared.load()`, or a comment after
    `Store.shared`, left the call unresolved or named its participant
    `Store.shared // the singleton`.
  - Activity labels, state guards and the `Unresolved:` notes of
    sequence diagrams held the comment: `// load first` above `load()`
    labelled the action `// load first load()`.

  A comment between a name's tokens is unchanged, and stays in labels.
  `@Attribute`'s options and `@Relationship`'s `inverse:` are now read
  from the syntax rather than searched for in the arguments' text:
  - `@Attribute(.externalStorage, /* not .unique */ originalName: "c")`
    and `@Attribute(originalName: "legacy.unique")` are no longer
    unique. Nor is a `.unique` given to another argument, as in
    `originalName: Legacy.unique` or `.transformable(by: Legacy.unique)`.
  - A comment holding `inverse:` no longer gives a relationship an
    inverse, or hides the one it has.
  - An inverse key path names its last property, so
    `\SchemaV1.Book.writer`, for a model nested in a `VersionedSchema`,
    and `` \`v1.2 Book`.author `` name `writer` and `author`, not `Book`
    and `2`.
- **A name written with backticks it doesn't need is the name without
  them** (#123). In Swift, `` `Plain` `` and `Plain` are one identifier,
  but every parser read a name exactly as it was written. So:
  - `` extension `Plain` `` was never merged into `struct Plain` or linked
    to it.
  - `` class Sub: `Base` `` drew its edge to an undeclared `` `Base` ``, and
    `` struct Conformer: `Proto` `` drew a conformance as inheritance. SVG
    dropped both edges.
  - In sequence and activity diagrams, a call written `` `Plain`.make() ``
    was unresolved, and calls made from a method of `` extension `Plain` ``
    were lost.
  - An ER `` @Model final class `Pet` `` was not the end of a `[Pet]`
    relationship.

  Every name the parsers read is now read as Swift reads it: types,
  extensions, supertypes, generic parameters, attributes, members, enum
  cases, call receivers, ER entities and properties, state machines,
  GRDB and SQLite.swift tables, and imports. In an expression,
  `` `self` `` and `` `Self` `` are `self` and `Self`.
  - A name that needs its backticks everywhere it is written keeps them,
    so its ids are unchanged: a raw identifier (`` `Foo Bar` ``), a
    keyword (`` `default` ``), and `Type` or `Protocol`, which a type
    member must escape.
  - `--entry`, `--state` and exclude patterns (`elements.exclude`, the
    relationship excludes and `deps --exclude`) take either spelling.
  - A label changes only where the source wrote needless backticks:
    `` case `package` `` now lists as `package`.
  - In Studio, a state diagram saved with such a name, as in
    `` `Lamp`.Light ``, reopens on the same state machine.
  - A call on `self` written after a comment line is followed in
    sequence diagrams. The comment was read as part of the receiver, so
    the call was left unresolved.
- **A repeat declaration's supertype edges start at its own box, with its
  own arrow** (#68). PlantUML, Mermaid and Nomnoml class diagrams drew
  every supertype edge from the first box with the declaration's name.
  So:
  - `extension Foo: P` drew `P <|.. Foo` from the struct's box, though
    in PlantUML and Nomnoml its nested types already hung off the
    extension's box `Foo0`.
  - Of two `#if` branches that each declare `class PlatformView`, the
    first box got both superclasses, which Swift does not allow, and the
    second got none.
  - Of two extensions of an undeclared `String`, the first drew both
    conformances, and `String0` had no edge at all.

  A repeat also took the first declaration's arrow, so
  `extension Foo: Codable` was drawn `Codable <|-- Foo` after a struct,
  `Codable -- Foo` after an enum or actor and `Codable <|.. Foo` after a
  protocol, but `Codable <.. String` for an undeclared type. Each
  declaration now draws its supertype edges from its own box, as SVG and
  the Studio canvas already did, and with its own kind's arrow. An
  extension's are drawn with `<..`, so `extension Foo: Codable` gives
  `Codable <.. Foo0 : inherits`. A supertype the diagram declares as a
  protocol still takes `<|..` from any declaration. Studio's PlantUML,
  Mermaid and Nomnoml previews and text exports change with the CLI.

  A first declaration's edges are unchanged, except where another type's
  name garbled them. Each arrow was stored beside each name's
  relationship, under the type's name with `LinkType` appended:
  - With `protocol P {}` and `struct PLinkType {}`, `struct S: P` was
    drawn `P inherits S` (`[S] inherits conforms to [P]` in Nomnoml),
    which no format parses. It is now `P <|.. S : conforms to`.
  - With `class Foo {}`, `class Child: FooLinkType {}` drew its edge with
    no label or style, because `Foo`'s arrow was read as the relationship
    of `FooLinkType`. It is now `FooLinkType <|-- Child : inherits`.
- **`--package` gives the same diagram on every run, and labels a type
  with the module that declares it** (#70). `classdiagram --package`,
  `deps --package --types` and Studio's Open Package… read the package's
  files in hash order, which Swift seeds anew in every process and for
  every dictionary. So the same package's diagram changed from run to
  run, and in Studio from one regeneration to the next:
  - Declarations and edges came in a different order in every format,
    and the SVG layout moved.
  - Extension aliases were renumbered, and which of several same-named
    declarations kept the plain name, and with it its module stereotype,
    changed.
  - `--merge-extensions` merged members in a different order, and a type
    no target declares took its module from whichever extension came
    first.

  The files are now read in path order, sorted by byte, so
  `Sources/Zed` comes before `Sources/app`. `deps --types` also labelled
  each type with the module of the last edge that named it, so a type
  another target extended could be labelled with that target. In
  SwiftUMLBridge itself, `DiagramFormat` and `ClassDiagramOutput` came
  out `<<swiftumlbridge>>`, the CLI target that extends them, on some
  runs. A type now takes the module of the target that declares it,
  nested types included. A type no target declares takes the first
  target, in path order, that extends it. `deps --modules --package` and
  `component` were not affected.
  - Only `deps`' cycle highlighting can still change between runs, and
    only for a graph with a cycle, in path mode too. `detectCycles` finds
    a different set of cyclic nodes depending on where its search starts,
    a separate problem #70 notes.
- **An extension's `ext` edge ends on the type it extends** (#72).
  PlantUML, Mermaid and Nomnoml class diagrams drew the edge only when a
  drawn type's short name equalled the extension's full name. So
  `extension Outer.Inner` was never linked to the nested `Outer.Inner`,
  and no qualified extension of a nested type got its edge. With a nested
  `Bar.Foo` drawn, a second top-level `extension Foo` was linked to the
  first, as if one extension extended the other. The edge now ends on the
  type the extension's name means where it is written, found by the
  lookup that SVG's edges and `--merge-extensions` use (#107). With two
  types of a name, that is the one in the extension's file or module. An
  extension of a type the diagram hides gets no edge, rather than one to
  a drawn type that only shares its name.
- **`--merge-extensions` no longer slows down cubically with same-named
  private types.** Deciding whether a type nested in a `private` or
  `fileprivate` extension is visible from another file looked up the
  type that extension extends before checking the nested type's own
  access, which already hides it. With 300 files that each nest such a
  type and extend it, a merged class diagram took 2.6 s; it takes 0.26 s
  now.
- **Nomnoml class diagrams parse again, and every edge ends on the box it
  names** (#69). Two defects broke Nomnoml class diagrams in the CLI's
  `--format nomnoml`, in Studio's preview and in exported source:
  - Every inheritance, conformance and extension edge ended in
    ` : label`, which is Mermaid and PlantUML syntax. nomnoml reads a
    label only beside the arrow, so it rejected the whole diagram. With
    the default labels, any diagram with one of these edges drew nothing.
    The label now goes by the arrow, as in `[Circle] -:> inherits
    [Base]`. In a configured label, brackets become parentheses, since a
    `[` would end it, and line breaks become spaces, since nomnoml reads
    a line that starts with `//` or `#` as a comment or a directive.
  - nomnoml names a node by its `id=`, or else by its title. The emitter
    wrote no id, but every edge named a node by its alias. So these got
    an empty box of their own on each edge, while their real box got
    none: a nested type, every extension after the first of its name,
    and any type whose header carries generics, attributes or a
    `--package` module. Declarations that share a title (`String` and its
    extensions, `A.Inner` and `B.Inner`) merged into one box, which kept
    only one set of members. Each declaration now carries its alias as
    its id, as in `[<extension id=Foo0> Foo|~bar()]`.
  - In an id, a space becomes a no-break space, so the box nomnoml draws
    for an undeclared supertype such as `@unchecked Sendable` shows a
    plain space. The other characters nomnoml takes as syntax appear only
    in raw identifiers. They are percent-encoded: `` `a|b` `` becomes
    `` `a%7Cb` ``.
  - Tests now parse the generated text with the bundled `nomnoml.js`,
    through JavaScriptCore.
- **An extension written with generic arguments or sugar is an extension
  of the type it names** (#66). `extension Foo<Int>` (SE-0361),
  `extension [Int]`, `extension [String: Int]` and `extension Int?` were
  named after their whole text, which class diagrams used as the
  element's id. Mermaid then rejected the whole diagram, in the CLI and in
  Studio's preview; PlantUML read `as Foo<Int>` as a second `Foo`; no
  `ext` edge was drawn; `--merge-extensions` left the extension apart; a
  type nested in it kept the brackets even with extensions hidden; and
  `extension Foo<Swift.Int>` was labelled `Int>`. They are now named
  `Foo`, `Array`, `Dictionary` and `Optional` (`Outer.Inner` for
  `Outer<Int>.Inner<String>`, `InlineArray` for `[3 of Int]`), so every
  format draws, aliases (`Foo0`), links, merges and excludes them exactly
  as `extension Foo where T == Int`.
  - While `elements.showGenerics` is on, the arguments they bind stay
    visible: PlantUML `as Foo0<Int>`, Mermaid `Foo&lt;Int&gt;` (rendered
    `Foo<Int>`), Nomnoml `Foo <Int>`, and the SVG and Studio canvas label
    `Foo<Int>`. Sugar reads as the type it stands for (`Array<Int>`). A
    merged box holding differently bound extensions shows none. In
    PlantUML's generic part, which ends at the first `>`, a function
    type's arrow reads `→` (`Array<() → Void>`); a supertype's arguments
    get the same, so `class D: Base<() -> Void>` no longer breaks the
    diagram.
  - Sequence, activity and state diagrams name the type the same way: a
    method of `extension Foo<Int>` is entered as `Foo.run`, not
    `Foo<Int>.run`. A Mermaid sequence diagram with such a participant now
    parses, `Foo<Swift.Int>`'s methods can be entered, and a state machine
    driven from such an extension is found. A call on the type as the
    extension writes it, `Foo<Int>.make()`, `Outer<Int>.Inner.make()`,
    `Int?.make()` or `[Int].make()`, is followed into the extension, and a
    call on an instance of a nested type, `Foo.Bar().run()`, resolves to
    `Foo.Bar` rather than `Foo.Bar()`.
  - `elements.exclude`, `relationships.dependency.exclude` and
    `deps --exclude` match these extensions by the base name: `Foo` now
    also hides `extension Foo<Int>`, and a pattern written `Foo<Int>` no
    longer matches. `deps --types` draws their conformances from `Foo` or
    `Array`, and `TypeInfo.name` reports the base name.
  - Each such extension that is not the first element of its base name
    now takes a numbered alias (`Foo0`), so later numbered aliases in the
    same diagram move up by one per such extension.
  - Nomnoml now gets the `ext` edge, as for every other extension.
  - Studio history entries keep the script and entry point they were saved
    with: regenerate an old Mermaid diagram, and pick an entry point saved
    as `Foo<Int>.run` again.
- **Nomnoml escapes brackets in a node's header.** `class D:
  Base<[Int]>` gave `[<class> D <[Int]>]`, which nomnoml rejects; it is
  now `[<class id=D> D <(Int)>]`, escaped as members already are. An
  attribute's arguments (`@Wrap<[Int]> struct Model {}`) and a raw
  identifier's name are escaped the same way.
- **A type nested in a hidden type no longer hangs off a drawn element of
  the same name in PlantUML and Nomnoml** (#117). When the diagram does
  not draw a nested type's parent, the edge named that parent by its
  qualified name (#67), which for a top-level type is its short name, and
  so can be the id of a drawn, unrelated element. With `fileprivate struct
  Foo { struct Inner {} }` in one file and `extension Foo { func bar() {}
  }`, or a `private struct Foo`, in another, the diagram drew `Foo +--
  Foo.Inner` onto that other element. With extensions hidden, a type
  nested in an extension hung off the first type of the extended name, not
  the one the extension sees. The edge now ends where SVG ends it: on a
  drawn extension that stands in for the hidden type, or on the type a
  hidden extension extends. Otherwise it still names the parent by its
  qualified name, unless a drawn element already has that id; then, as in
  SVG, it is not drawn.
- **SVG class diagrams draw only the types the other formats draw** (#74).
  `LayoutGraphBuilder` kept every declaration of a drawable kind, so
  `showExtensions: none` (`--hide-extensions`), `elements.exclude` and
  `elements.havingAccessLevel` hid nothing in SVG. The default access
  levels leave out `fileprivate`, so even an unconfigured SVG diagram, in
  the CLI or on Studio's native canvas, drew `fileprivate` types that the
  PlantUML and Mermaid ones hide. SVG now keeps what the text formats
  keep, filtered after extensions merge, so a hidden type takes its
  merged extensions with it. A hidden type still decides which type its
  name means where Swift can see it: an edge to it ends on a drawn
  extension of that very type, or is dropped, and never moves to a
  same-named type in another file or module. A `private` or `fileprivate`
  type takes no name written in another file, nor one below `package` a
  name written in another module. A type is as visible as the most
  restrictive of itself, the types and the extension enclosing it, and
  the type that extension extends. (The text formats link a supertype or
  conformance by bare name, so there such an edge still lands on
  whichever declaration holds that name; a nested type's edge follows
  SVG, see above.)
- **`relationships.realize.exclude` and `relationships.dependency.exclude`
  now hide edges** (#113). Both were decoded but never read, so the
  reference's own `realize.exclude: [Codable, Sendable]` hid nothing.
  - `realize.exclude` is pooled with `inheritance.exclude`: a name in
    either list hides every inheritance or conformance edge to that class
    or protocol. A conformance to a protocol the diagram does not declare,
    such as `Codable`, is labelled and styled as inheritance, and
    `inheritance.exclude` has always reached conformances, so a list for
    conformances alone could not have hidden it. A config that uses only
    `inheritance.exclude` draws exactly what it drew before in PlantUML,
    Mermaid and Nomnoml.
  - `dependency.exclude` matches the extended type's name and hides only
    the `<..` edge from an extension's box to that type. The box, its
    alias and its own conformances stay.
  - SVG class diagrams now honour `inheritance.exclude` and
    `realize.exclude`; they read no relationship setting before.

  The reference's arrow table had its arrows reversed, and both it and
  the user guide's illustrated conformance with `Equatable` or `Codable`,
  which are labelled as inheritance; both are corrected. The reference
  now says that a `relationships:` block replaces the inheritance and
  realize labels.
- **A `{…}` group in `files.include` or `files.exclude` now stands for one
  entry per option** (#58). Each group became a regex alternation instead.
  Its options were escaped with an old copy of the escape class, then
  spliced in without the glob translation.
  - A `*` or `?` after a character acted as a regex quantifier, so
    `{Foo*,Bar}.swift` missed `FooKit.swift`.
  - `^` and `$` became anchors, so `{a^b,c}.swift` never selected
    `a^b.swift`.
  - An option that started with `*` or `?`, or held `**` anywhere, made
    the regex invalid. The whole entry then matched nothing, logging only
    to the system log. So `--exclude '**/{Mock*,*Kit}.swift'` and
    `{Sources/**,Tests/**}` excluded no file.
  - A group of plain directory names, such as `Sources/{App,Core}`,
    matched no file inside them.
  - An option naming a symlinked or absolute directory was not resolved.

  A brace entry now means exactly the list of its expansions, each a whole
  glob. Groups can nest, and spaces around an option are dropped. A plain
  option is a plain entry: `Sources/{App,Core}` now works as
  `Sources/App,Sources/Core` does. The glob reference says so, notes that
  braces expand only in `files.include` and `files.exclude`, and corrects
  the description of a plain string, which matches the path it names
  and what lies inside it, not a substring anywhere.
- **A plain `files.include` or `files.exclude` entry stops at a path
  component** (#111). It matched every path that merely began with the
  same text: `--exclude Sources/App` also dropped `Sources/AppKit/…` and
  `Sources/AppDelegate.swift`, and `--exclude Generated` dropped
  `GeneratedExtra/`. `Glob.matches` tested `path.contains`, a substring
  match left from before entries and enumerated files were spelled
  alike; it now takes the named path and what lies inside it.
- **A type nested in a hidden type no longer hangs off an unrelated type
  with the hidden type's short name** (#67). In PlantUML and Nomnoml,
  the edge from a drawn nested type to a parent the diagram does not draw
  named that parent by its short name. With `struct Outer { fileprivate
  struct Foo { struct Inner {} } }` and a top-level `struct Foo {}`, the
  diagram drew `Foo +-- Outer.Foo.Inner`, nesting `Inner` in the wrong
  `Foo`. A public-only diagram (`havingAccessLevel: [public]`) did the
  same for every internal container of a drawn public nested type. The
  edge now names a hidden parent by its qualified name (`Outer.Foo +--
  Outer.Foo.Inner`), and alias reservation (#54) reserves that name
  instead of the short one. Edges to a merged-away or hidden extension
  are unchanged, because an extension's name is already the extended
  type's full name. Mermaid draws no nested-type edges and SVG names
  parents by their full name, so neither changes.
- **A merged extension's members go into the same-named type its nested
  types hang off** (#107). With two types of one name, `mergeExtensions` took
  the first, ignoring the extension's file and module. The SVG edge from
  a type nested in that extension already preferred the type in the
  same file, then the same module (#55). So `--merge-extensions --format
  svg` could draw `bar()` on one `Foo` and `Foo.Inner` hanging off the
  other. Under `--package`, file order is hash order (#70), so in every
  format the `Foo` that received the members changed from run to run.
  Merging now picks its type by the lookup edges use: the nearest
  same-named type that Swift's access control lets the extension see
  (#74), so never a `private` or `fileprivate` type in another file or
  an internal one in another module. An extension that can see none
  extends a type outside the diagram and keeps its own box, which later
  such extensions merge into. A type nested in a merged extension now
  hangs off that type in every format, while keeping the extension's
  access. When that type is hidden, the edge ends as for any parent the
  diagram does not draw (see above).
- **SVG class diagrams with merged extensions list each merged member once
  and draw a type nested in an extension once** (#73). For `.svg`,
  `DiagramScript` prepared the parsed items twice: once for text
  definitions it then discarded, and once in `LayoutGraphBuilder`.
  Preparation edited the shared `SyntaxStructure` objects in place. It
  appended each extension's members to its type and set their `<&bolt>`
  suffix. So with `--merge-extensions --format svg`, or a config with
  `showExtensions: merged` and `format: svg`, the second pass listed every
  merged member twice and drew a second box for a type nested in an
  extension. `.svg` now skips the unused text definitions. Preparation
  now runs in one function shared by the text emitters and the SVG
  builder, on a private copy of the items. Repeated or concurrent
  diagrams from one parse now give the same output, and a `.merged` run
  no longer leaves `<&bolt>` on a later `.all` one.
- **`classdiagram` no longer diagrams the whole current directory when its
  file selection comes out empty.** The command collected and filtered
  its files, then passed the paths to `ClassDiagramGenerator.generate(for:)`,
  which collected them again — and `FileCollector` reads an empty path
  list as "the current directory". So a `files.include` that matched
  nothing, a `files.exclude` or `--exclude` that matched everything, or a
  path holding no Swift files produced a diagram of every Swift file under
  the working directory, with exit status 0: the files the selection had
  just ruled out. It now fails with `No Swift files were found in the
  given paths, or the files.include / files.exclude (--exclude) filters
  left none.` and a non-zero exit, as `er`, `state` and `component`
  already do when they find nothing. Only `classdiagram` applies file
  filters; the other subcommands, Studio and the framework API are
  unchanged.
- **Every `--exclude` and `files.exclude` entry applies, not only the
  last.** `FileCollector.getFiles(for:in:honoring:)` replaced its set of
  excluded files with each exclude glob in turn, so only the last entry
  excluded anything. The documented
  `classdiagram Sources/ --exclude Sources/Generated/ --exclude Sources/Mocks/`
  dropped `Mocks` and kept `Generated`, and a `.swiftumlbridge.yml` with
  several `files.exclude` patterns honoured only the last one. Include
  globs had a related fault: a file matching two of them came back twice,
  as did a file with include globs and two exclude entries, and include
  results followed the order of the globs rather than the order the
  files were found. Files are now filtered in one pass: dropped if any
  exclude glob matches, kept if any include glob does, each at most once
  and in the order found.
- **A PlantUML diagram reaches planttext.com whole** (#57). `DiagramText`
  deflated the script with `compression_encode_buffer`, passing the
  string's `Character` count as both the number of bytes to read and the
  size of the output buffer. A diagram with more UTF-8 bytes than
  `Character`s — any non-ASCII text, such as a `Café` type, a `naïve`
  property, a CJK name or an emoji, and also a `\r\n` line break, which
  is one `Character` — lost its last `utf8.count − count` bytes, so
  `@enduml` and then the last declarations never reached the renderer. A
  script that did not compress below its own length came out as `""` and
  the URL had no payload: the smallest deps graph, `@startuml\n@enduml`,
  and a one-edge graph both did. Every generated script's PlantUML URL
  went through it — the CLI's `browser` and `browserImageOnly` output and
  Studio's preview of a freshly generated diagram. `DiagramText` now uses
  `NSData.compressed(using: .zlib)`, which reads every byte and sizes its
  own output. It is the same encoder, so a script the old call encoded
  whole — ASCII with no `\r\n`, compressing below its own length — still
  gets the same payload. If compression ever fails, the payload falls
  back to PlantUML's uncompressed `~h` hex form instead of an empty
  string. The `encodeText()` tests only checked for a non-empty result on
  long ASCII input; they now decode the payload and compare it with the
  script.
- **A module or type name with a backslash or line break is laid out by
  dagre again** (#60, #81). `DagreLayoutEngine` pastes node ids, module names
  and cluster ids between `"` in the script it runs on JavaScriptCore,
  and escaped only `"`. A deps `--modules` node is a directory name, and
  macOS allows `\` and newlines in those. `Old\Code` evaluated to
  `OldCode`, so dagre's result no longer matched the node, which stayed
  at (0, 0) with its edges unrouted. `Trail\` escaped the closing quote,
  and a raw LF or CR ended the literal; either way the script failed to
  parse and the whole graph dropped to the grid fallback. This reached
  `swiftumlbridge deps --modules --format svg` and the modules graph on
  Studio's native canvas. Every interpolated string now goes through
  `jsStringLiteral`, which JSON-encodes it and also escapes U+2028 and
  U+2029, so the literal evaluates back to exactly the name.
- **The fallback layout no longer overlaps boxes or drops edges** (#61).
  When dagre gives no result, `DagreLayoutEngine` lays the graph out on a
  grid. Each cell was a fixed 250 × 200 px, whatever the node size, so a
  label or member line of 31 or more characters made neighbours overlap
  and pushed the outer columns off the canvas, and a node with 9 members
  ran off the top or bottom. The fallback also gave no edge any points,
  so both the SVG renderer and Studio's native canvas drew bare boxes
  with no relationships. Each cell is now the largest node plus dagre's
  60 px spacing, inside dagre's 20 px margin. Each edge is drawn as a
  straight line from border to border with its label at the midpoint.
- **A node whose name starts with `cluster:` is laid out as a node.**
  `DagreLayoutEngine` gave each module's cluster the dagre id
  `cluster:<module>` but used every node's own id unchanged, then read
  back anything starting with `cluster:` as a cluster. A deps `--modules`
  directory named `cluster:Core` — or a raw-identifier type — was drawn
  at (0, 0), half off the canvas, with an empty `Core` module box beside
  it. A node whose id was exactly another cluster's, such as
  `cluster:Core` in module `Core`, was the same dagre node as that
  cluster, so the script failed and the graph dropped to the grid with no
  module boxes. Nodes now take the dagre id `node:<id>`, so the two
  namespaces can no longer meet.
- **Two names that sanitize alike are no longer drawn as one node.**
  `DepsScript.mermaidId` and `ComponentScript.safeAlias` rewrite several
  characters to `_`, so `Outer.Inner` and `Outer_Inner` both became the
  identifier `Outer_Inner`. The deps Mermaid emitter then declared both
  under that one id: the renderer drew a single node with the second
  label, the first type vanished, and its edges joined the other's. The
  component PlantUML and Mermaid emitters had the same flaw, and in
  Mermaid a provided interface (`A` + `B` → `A_B`) could also merge with
  a component named `A_B`. Each emitter now hands out identifiers from a
  per-diagram `DiagramIdentifiers` table: the first name keeps its
  sanitized id and a colliding name gets `_2`, `_3`, …. A diagram with no
  collision is unchanged byte for byte. Found by an injectivity property
  prototyped in SwiftInferProperties against SwiftUMLBridge.
- **An if/guard join in an activity diagram now sits below its longer
  branch** (#53). `ActivitySVGRenderer.computeRows` promised longest-path
  layering but kept the first row it gave each node, so when branches of
  different length met, the join took its row from the shorter one. It
  landed level with or above the longer branch's last node, and the edge
  into it was drawn as a dashed loop back-edge — in `.svg` output and on
  Studio's native activity canvas, which shares `ActivityLayout`. Rows now
  come from a DFS from the start node that sets aside back-edges, then
  Kahn's algorithm over the remaining edges, so every predecessor is
  placed before its successor. Nodes start never reaches still go to row 0
  and cannot stall the pass.
- **A class-diagram extension no longer takes another type's id** (#54).
  `DiagramContext.uniqName` gives a repeated name the next value of one
  diagram-wide counter as a suffix, and never checked the result. So
  `struct Foo0 {}`, `struct Foo {}`, `extension Foo {}` declared the
  extension as `Foo0` — Mermaid `class Foo0["Foo"]`, PlantUML
  `class "Foo" as Foo0` — alongside the real `Foo0`, and the `ext` edge
  and any nested-type edge pointed at both. A suffix could likewise take a
  name only an edge uses — `class A: A0 {}` plus `extension A {}` drew A
  inheriting from its own extension — since Mermaid and PlantUML give an
  edge's undeclared end a node of its own. Before the first alias is
  issued, the diagram now reserves every id it will use: the names it
  draws, its edges' supertypes, conformances and raw types, and (where
  nested-type edges are drawn) a hidden parent's name. A suffix skips
  those and every alias already issued. Diagrams with no collision keep
  every alias; in one that collides, each skipped suffix moves the aliases
  issued after it up by one more.
- **An SVG class diagram no longer draws two extensions as one box**
  (#55). `LayoutGraphBuilder.uniqueId` checked candidates against a
  name-to-id map that each new id for a name overwrote, so a name's
  fourth declaration got its second one's id again — `Foo`, `Foo_1`,
  `Foo_2`, `Foo_1`. Dagre keys nodes by id, so both `Foo_1` boxes got one
  position and size and were drawn on top of each other, in `.svg` output
  and on Studio's native class canvas. Ids now come from a set of every
  issued id, with each drawn name reserved up front: a name's first
  declaration keeps it, later ones take the next free `_n`, and ids that
  never collided are spelled as before. The same map decided where edges
  end, and also got that wrong: an edge to a supertype landed on the
  supertype's extension (`Sub → Base_1`), a composition edge to a nested
  type on that type's extension, and an edge to an undeclared `Foo_1` on
  Foo's extension node. Edge ends are now resolved once every node
  exists. A supertype or conformance resolves by name to a type, never an
  extension unless the diagram declares no such type; where several types
  share the name, it picks the one in the referring declaration's file,
  then its module, then the first. A nested type hangs off the
  declaration that contains it, or, inside an extension, off the extended
  type as seen from the extension's file — or off that extension itself
  when the diagram draws no such type. An end the diagram does not
  declare drops the edge. A nested type whose parent sorts after it,
  such as one inside an extension of an undeclared type, now gets the
  composition edge it used to be missing.
- **A `--` in a label no longer makes class-diagram or dependency-graph
  SVG malformed** (#56). `SVGRenderer` wrote each node's label, and each
  module cluster's, into an XML comment ahead of its `<g>`. XML forbids
  `--` inside a comment, and no escape makes it legal there, so a source
  folder named `Old--Code` produced `<!-- Old--Code -->` in
  `deps --modules --format svg` output, and `XMLParser` rejected the
  whole document. Class diagrams broke the same way for a raw-identifier
  type such as `` `Old--Code` ``, and in package mode for a SwiftPM target
  of that name, which labels a module cluster. Exported and CLI-opened
  `.svg` files carried the same text. The two comments are gone: they
  repeated the `<text>` element inside the same `<g>`, and no code read
  them. The output is otherwise unchanged. A diagram saved to Studio's
  history before the fix keeps its old text until it is regenerated. New
  tests parse the output as XML as well as checking substrings.
- **A control character in a label no longer makes an SVG diagram
  malformed** (#80). Every SVG renderer — class, dependency, activity,
  sequence and component — sends its text through `xmlEscaped`, which
  escaped only `&`, `<`, `>` and `"`. XML 1.0 forbids every C0 control
  except tab, line feed and carriage return, and also U+FFFE and U+FFFF,
  and it rejects a character reference to one too. So a single such
  character made `XMLParser` reject the whole document. They got in
  through a source folder whose name holds one (APFS accepts
  U+0001–U+001F), in `deps --modules --format svg`, and through Swift
  source that `swiftc` accepts: a form feed inside a statement, or a
  control character in a comment inside an `if` condition or a type
  annotation, which the activity and class labels keep. `xmlEscaped` now
  replaces a C0 control with its Control Pictures glyph (U+0007 becomes
  `␇`), so the label still shows where it was, and U+FFFE and U+FFFF
  with U+FFFD. It also walks Unicode scalars instead of `Character`s.
  The old replacements matched whole characters, so a `<` or `&`
  followed by a combining mark went out unescaped and broke the document
  as well. Text with none of these characters comes out unchanged.
  Activity labels, in every format, now also collapse a form feed,
  vertical tab or CRLF inside a statement into one space, as they already
  did spaces, tabs and line feeds, so a form-feed line no longer leaves a
  `␌` in its label. Exported and CLI-opened `.svg` files were affected. A diagram saved to
  Studio's history before the fix keeps its old text until it is
  regenerated. New tests parse each renderer's output as XML.
- **`--format nomnoml` on `sequence`, `activity`, `state` and `er` opens
  at mermaid.live instead of nomnoml.com** (#85). These four have no
  Nomnoml emitter and fall back to Mermaid text, but their scripts still
  reported `.nomnoml`. `BrowserPresenter` picks its site from that, so
  browser output handed Mermaid source to nomnoml.com, which drew it as
  literal text or failed to parse it. Studio chose the same way: its
  preview fed the text to `nomnoml.js`, and **Export markup…** saved it
  as `.nomnoml`. The fallbacks now report `.mermaid`, as the
  `--format svg` fallback in `state` and `er` already did, so the CLI
  opens mermaid.live and Studio previews and exports the text as
  Mermaid. A diagram reopened from Studio's history still takes the
  format picker's value rather than the script's, so it is still sent
  to `nomnoml.js`.
- **`--format` help no longer lists only `plantuml` and `mermaid`**
  (#82). The hand-written "Options: plantuml, mermaid" sat beside
  ArgumentParser's own "(values: plantuml, mermaid, nomnoml, svg)",
  which it derives from `DiagramFormat`. Only the generated list is
  left, so the two cannot disagree again.
- **Include and exclude globs match under a directory reached through a
  symlink.** `FileCollector.getFiles(for:in:honoring:)` anchored each
  glob at `directory` as the caller spelled it, but `FileManager`
  reports enumerated files under the directory's resolved path, so a
  walk of `/tmp/x` yields `/private/tmp/x/…`. Under `/tmp`,
  `/var/folders` (`FileManager.temporaryDirectory`) or any symlinked
  parent, an include glob matched nothing and an exclude glob dropped
  nothing. This is why three FileCollector and Glob tests failed for a
  checkout under `/private/tmp`: `Bundle.module` spells its fixture path
  `/tmp/…`. Globs are now anchored at the real path, as `realpath(3)`
  gives it (`resolvingSymlinksInPath()` strips `/private` again, so it
  cannot be used), and each file is tested with its parent resolved the
  same way. That also lets an exclude glob catch an explicit file
  argument typed through a symlink, which the CLI missed even though its
  own working directory is already resolved.
- **A search directory that is itself a symlink is searched.**
  `FileCollector` asked the search path's resource values whether it was
  a directory. Those describe a symlink rather than what it points to, so
  a symlink to a directory came back as if it were a single Swift source
  file, and parsing it found nothing: `swiftumlbridge classdiagram <link>`
  printed an empty `classDiagram`. Every generator collects files this
  way, so each diagram command was affected, as was Studio when given
  such a path. Starting the enumerator at the link would not have helped,
  because it yields nothing there. The directory is now resolved before
  it is walked, and its files come back under its real path, as they
  already did for a directory with a symlinked parent. Globs anchored at
  such a directory resolve it too, which is why they use `realpath(3)`:
  `canonicalPathKey` leaves a final symlink unresolved.
- **An include or exclude entry whose directories run through a symlink,
  or hold `.` or `..`, matches** (#59). The two fixes above resolve the
  search directory, but an absolute or `~` entry never uses it, so
  `classdiagram --exclude '/tmp/proj/Generated/*.swift'` built a regex
  anchored at `/tmp/…` that no enumerated `/private/tmp/…` file could
  match, and a relative entry could still run through a symlink below the
  search directory. Enumeration never reports a `.` or `..` component
  either, so `./Sources/**/*.swift` and `Other/../Sources` matched
  nothing, wherever the directory was. Each entry's directories, up to
  its first glob syntax, now go through `realpath(3)` as the search
  directory does; from there on the entry is still taken as written. An
  entry with no glob syntax had been rescued by a substring match only
  where the symlink just adds a prefix, as `/tmp` → `/private/tmp` does.
  It now names a directory by its real path and a file by its resolved
  parent and its own name. Entries are matched by where the files are,
  so one naming a symlinked directory acts on the directory it leads to,
  and on a case-insensitive volume those leading directories match in
  any case. `matchGlobs` lists a directory that is itself a symlink
  through the link, rather than finding nothing there.
- **Include and exclude globs match under a directory whose name holds
  `[`, `*` or `?`.** A relative entry was read as a glob together with
  the search directory it was appended to, so a project in a folder
  named `Proj [old]` turned `[old]` into a character class that never
  matched the folder: an include glob selected nothing and an exclude
  glob dropped nothing, with no diagnostic. A `*` or `?` in a directory
  name let a glob match sibling directories as well. Splitting each
  entry at its first glob syntax, as the fix above does, split inside
  such a directory. Only the entry is searched for glob syntax now, so
  the search directory is always part of the resolved anchor, and the
  anchor is matched literally; only the rest is read as a glob.
- **A CRLF line break after an `@Relationship` inverse no longer draws
  the relationship twice.** `ERModelExtractor` read the property name in
  `inverse: \Book.author` up to the first `,`, `)`, space, tab or `"\n"`.
  In Swift `"\r\n"` is one `Character`, and it is not equal to `"\n"`, so
  in a CRLF file a line break straight after the key path did not end the
  name, and the inverse came back as `author` plus the line break. The
  explicit `Author.books` then no longer matched the implicit
  `Book.author` it covers, so both were kept and the diagram drew a second
  `Book` → `Author` edge labelled `author`. A lone `\r` line break did the
  same. This reached `swiftumlbridge er` in every format and Studio's ER
  diagram. The name is now the identifier after the dot — letters,
  digits, `_` and the backticks of an escaped name — so any line break,
  whitespace or comment ends it.
- **A module whose name starts with a combining mark keeps it in its
  cluster id.** `DagreLayoutEngine` names each module's cluster
  `cluster:<module>` and, reading the layout back, dropped the prefix's
  eight `Character`s, though the script had matched it by UTF-16 unit. A
  name that starts with a grapheme extender — a combining mark, VS16, a
  ZWJ or a skin-tone modifier — joins the `:` into one `Character`, so
  its first scalar went with the prefix: `\u{301}Core` came back as
  `Core`, `🏻Tools` as `Tools`. The label was still right, but the SVG
  renderer and Studio's native canvas color a module box from its id,
  so the box took another name's hue. Such a name reaches the layout as
  a SwiftPM target in package mode. The prefix is now dropped by scalar.
- **`camelCaseToKebapCase` searches the whole string.** It gave
  `NSRegularExpression` a range as long as the string's `Character`
  count, where an `NSRange` counts UTF-16 units, so a camel-case
  boundary in the last units went unsplit whenever the string held an
  emoji or other wide character: `"😀😀aB"` came out `"😀😀ab"`. Theme
  names are ASCII, so no theme's `rawValue` changed; the range now
  spans the string's UTF-16 length.

### Changed — Bridge

- **Component diagrams requested in Nomnoml fall back to Mermaid, like
  sequence, activity, state and ER.** Nomnoml has no component dialect,
  and `ComponentScript` was the one emitter that sent that case to
  PlantUML instead. In Studio, a component diagram previewed in Nomnoml
  mode was therefore uploaded to planttext.com — with no consent prompt,
  since Studio asked only when PlantUML itself was picked — while the
  consent text promised that Mermaid and Nomnoml render locally.
  `.nomnoml` now produces the same `flowchart TD` text as `.mermaid` and
  reports `.mermaid`, so Studio previews it with the bundled Mermaid
  renderer and exports it as `.mmd`; no Nomnoml-mode diagram reaches
  planttext.com any more. On the CLI, `component --format nomnoml` now
  prints Mermaid rather than PlantUML, and `--output browser` opens it at
  mermaid.live instead of planttext.com. The format switch names
  `.plantuml` explicitly instead of using `default:`, so a future
  `DiagramFormat` case is a compile error there rather than a silent
  PlantUML fallback.

### Fixed — Studio

- **A PlantUML diagram reopened from history renders.** A restored
  history item is a `SimpleDiagramScript`, which still overrode
  `encodeText()` with a placeholder from before the Bridge's encoding was
  public: it percent-encoded the raw text into the planttext.com URL.
  planttext.com could not decode that and drew its "Welcome to PlantUML!"
  placeholder instead of the diagram. The override is gone, so a restored
  item encodes exactly like the script it was saved from (#57).
- **A diagram reopened from history renders in the language its text is
  written in.** History saved only the Format picker's value and rebuilt
  the script with it, but several diagrams fall back to another language:
  state and ER in SVG emit Mermaid, and sequence, activity, state, ER and
  component in Nomnoml emit Mermaid. Reopened,
  such a diagram came back labelled with the picker's format, so the
  preview handed Mermaid to nomnoml.js or wrapped it as raw SVG, and
  Export saved its source with the wrong extension. `DiagramEntity` now
  also stores the script's own format, and reopening restores the picker
  to what the user chose and the script to the format of its text.
  Entries saved before the fix carry no script format and reopen as
  before; regenerating one and saving it again records it.
- **The Nomnoml preview shows non-ASCII names as written.**
  `NomnomlHTMLBuilder` base64-encoded the diagram's UTF-8 bytes and the
  page decoded them with `atob`, which returns one Latin-1 character per
  byte and leaves the UTF-8 undecoded. Every accented letter, CJK name or
  emoji reached nomnoml.js as mojibake: `struct Café { var naïve: Int }`
  drew as `CafÃ©` and `naÃ¯ve`. The page now carries the source as a
  JavaScript string literal, which needs no decoding. It is JSON-encoded
  with `<`, U+2028 and U+2029 escaped, so `</script>` in a diagram cannot
  end the script element. The tests now run the page's own script in
  JavaScriptCore and check what reaches `nomnoml.draw`; the old test
  decoded the base64 in Swift as UTF-8, which the page never did. The
  Mermaid preview was not affected.
- **A PlantUML preview asks before anything reaches planttext.com — on
  every route, in both builds.** M14 asked for consent when the Format
  picker changed to PlantUML, but the preview loaded planttext.com for
  any PlantUML script without checking it, so a script that became
  current another way was uploaded unasked: the direct build's default
  format (Explorer, the default mode, has no picker at all); a reopened
  PlantUML history item, behind the alert, where Cancel could not take
  it back; any regeneration while the alert was open — a restore's path
  or mode change, Open, or a debounced generate already in flight; and
  the component diagram's Nomnoml fallback. Even an empty ER or state
  result contacted planttext.com with Mermaid selected, because the
  Bridge's "nothing found" scripts are typed PlantUML. `PlantTextPreview`
  is now the only code that builds a planttext.com URL, and only with
  consent; until then the preview shows a card that says what would be
  sent, with **Preview with planttext.com** and **Use Mermaid Instead**.
  The modal alert is gone and changing format just regenerates, since
  making PlantUML text is local; the Markup tab and Export work without
  consent. A decline is remembered, so a direct build starts in Mermaid
  next launch instead of asking again. Direct-build users who never
  chose PlantUML in the Format picker never consented — the default
  never raised the old alert — so they now meet the card on their first
  PlantUML preview, until they answer it. In the App Store build, a
  history entry with no readable format no longer switches the picker
  to PlantUML; the picker falls back to the build's default format.

### Documentation

- **The user docs say what `--format svg` and `--format nomnoml` do on
  the CLI** (#82). The reference, user guide and README said the CLI
  emits text only for `plantuml` and `mermaid` and never writes SVG to
  stdout. In fact every subcommand's `--format` accepts all four values.
  `svg` prints a standalone `<svg>` document for `classdiagram`,
  `sequence`, `activity`, `deps` and `component`, and browser output
  writes it to a temporary `diagram.svg` and opens it. `state` and `er`
  print Mermaid instead. Only `classdiagram` and `deps` emit real Nomnoml.
  The reference's new **Formats by Subcommand** table lists every
  combination and where browser output sends it, and the README's
  diagram-types table now credits dependency graphs with Nomnoml output.

---

## [1.1.0] — 2026-08-16

The first release since v1.0.0 (2026-05-11), covering three months of work
that had accumulated unreleased.

Two themes dominate. **M14** makes Studio distributable through the App
Store: a sandboxed `AppStoreRelease` configuration, security-scoped
bookmarks so saved diagrams survive a relaunch, and a consent gate on the
one feature that sends anything off-device. **M12** finishes multi-module
SPM support, so `--package` now works across `classdiagram`, `deps` and
`component`, and Studio draws module grouping boxes to match.

Alongside those: the CLI gained its first test target, Explorer mode
reached all seven diagram types, two hangs in `component --package` were
fixed, and the framework is now free of `nonisolated(unsafe)`.

### Added — Bridge

- **`SwiftUMLBridgeCLITests` — a test target for the `swiftumlbridge`
  executable.** The CLI previously had no tests and no target, so it sat
  outside every coverage measurement: the Bridge's reported 94.8% was the
  framework alone, and counting the executable the package was nearer 88%.
  The CLI is what the Homebrew formula builds and what users actually run,
  and its argument surface — flag precedence, `--entry` validation, output
  routing — was entirely unverified. Now covered in two layers: parse-only
  tests over the argument surface (including that a three-part
  `MyModule.Loader.load` and a dangling-dot `.load` are both *refused*
  rather than guessed at), then end-to-end `run()` calls per subcommand
  over the fixtures, taking the CLI target from 23.8% to 86.1%. Every case
  passes `--output consoleOnly`, since the default presenter opens a
  browser window. A `LinkageSmokeTests` fails first and unambiguously if
  testing an `@main` executable target from SwiftPM ever regresses into a
  link error.

- **M15: DocC documentation catalog for `SwiftUMLBridgeFramework`.** A
  `SwiftUMLBridgeFramework.docc` catalog gives the framework a curated
  landing page (Overview plus topic groups for the seven generators,
  configuration, emitted scripts, per-diagram model layers, layout, and
  rendering) and a `Generating Diagrams` getting-started article. Hosted
  by Swift Package Index via the existing `.spi.yml`
  `documentation_targets`. Also fills in doc comments on previously
  thin public model types (`Configuration`, `ElementOptions`,
  `RelationshipOptions`, `Stereotype` / `Spot`, `SequenceLayout` and its
  participant / message structs).

- **M12 follow-up: `deps --package <Package.swift>`.** Module-aware
  dependency graphs for SPM packages. In `--modules` mode each edge
  comes from a target's `target_dependencies` (authoritative — no
  source-level import parse, system frameworks excluded), and each
  internal node is stereotyped with its target kind:
  `component "Networking" as Networking <<library>>`. In `--types` mode
  each inheritance / conformance edge is tagged with the owning SPM
  target, rendered as `class "Foo" as Foo <<Module>>` (parallels the
  M12 `classdiagram --package` stereotype). Test targets are excluded.

### Added — Studio

- **M14: App Store distribution build (`AppStoreRelease` + App Sandbox).**
  A third build configuration alongside Debug/Release, defining an
  `APP_STORE_BUILD` compilation condition, so the sandboxed App Store
  build and the unsandboxed direct-distribution build ship from one
  codebase. Under the flag:
  - Every subprocess / `dlopen` path is gated off. A new
    `BridgeConfiguration.skipSourceKitTypenameSupplement` (a *runtime*
    toggle, since the SwiftPM package can't see the host project's
    compilation conditions) short-circuits `buildTypenameMap`, avoiding
    a `dlopen` of `sourcekitdInProc` from the system toolchain —
    SwiftSyntax-only parsing still produces every diagram, only
    inferred-type resolution is lost. `Open Package…` and
    `loadPackage` are likewise disabled rather than shelling out to
    `swift package describe`.
  - Entitlements: `app-sandbox`, `files.user-selected.read-write`
    (NSSavePanel exports write via `data.write(to:)`, which the
    read-only grant would silently fail), and `network.client` for the
    PlantUML WebView fallback. Mermaid/Nomnoml ship their JS bundled and
    need no network.
  - **Security-scoped bookmarks** on `DiagramEntity` and
    `ProjectSnapshot` (additive — SwiftData lightweight migration, no
    schema bump). Raw path strings carry no read access under sandbox,
    so restoring a saved diagram in a later launch previously left the
    view model with unreadable paths and silently produced empty
    diagrams. New `SecurityScopedURL` helpers make, resolve, and
    regenerate-when-stale the bookmarks; unresolvable entries are
    dropped under sandbox with a user-visible notice instead of falling
    back to an unreadable path.
- **Studio surfaces `errorMessage` / `packageLoadError` / `restoreNotice`
  as alerts.** All three view-model fields were set but never displayed,
  so a failed generation, an unopenable Swift Package, and a sandbox
  restore that dropped files each produced no feedback at all.
  `restoreNotice` is a dedicated field rather than a reuse of
  `errorMessage`, because `onChange(of: selectedPaths)` fires a
  `generate()` after restore and `generate()` clears `errorMessage` at
  the start of every run — the warning was being wiped before it could
  display.
- **Explorer mode suggests all seven diagram types.** Explorer navigation
  is entirely suggestion-driven (the mode picker is hidden by design), so
  a diagram type with no card is unreachable there. `SuggestionEngine`
  covered only class, sequence, deps, and state machines, leaving ER,
  Component, and Activity invisible to the mode most users start in. ER
  is gated on the project importing SwiftData / Core Data / GRDB /
  SQLite, detected from the already-computed `moduleImports` rather than
  by running the ER extractor. Component is gated on `moduleBreakdown`
  holding two or more targets — exactly the condition under which the
  diagram is more than a single box. Activity offers one card for the top
  entry point rather than matching sequence's `prefix(3)`, which would
  put six cards on the same handful of methods and crowd out the rest of
  the grid; its copy is deliberately distinct from sequence's ("Step
  through Foo.bar" / the branches and loops inside a method, versus
  "Trace Foo.bar" / which types it calls), pinned by test so the two
  don't drift into reading as duplicates.
- **M12 follow-up: Dependency graph picks up SPM module info when a
  package is loaded.** `DiagramViewModel.generateDependencyGraph()` now
  routes through `DependencyGraphGenerator.generateScript(forPackage:…)`
  whenever `Open Package…` has set `packageDescription` /
  `packageRoot`, mirroring the existing class-diagram branch. The
  result is the same `<<library>>` / `<<Module>>` stereotypes the CLI
  emits, surfaced in Studio's three-pane workspace and Insights without
  any UI changes. Path-based generation remains the fallback when no
  package is loaded.
- **M11 follow-up: Per-module dashboard.** When an SPM package is
  loaded, the Explorer-mode dashboard surfaces a new **Modules**
  section above Insights. One card per non-test SPM target shows the
  module's name (with the same deterministic swatch color the native
  canvas already uses for the per-node stripe), its target kind chip
  (`library` / `executable`), and three counts: source files, types,
  and outgoing `target_dependencies`. Driven by a new
  `ProjectAnalyzer.analyze(package:packageRoot:)` overload that emits a
  `ModuleSummary` per target.
- **M12 follow-up: Module-grouped class-diagram layout.** When an SPM
  package is loaded, the native class-diagram canvas now draws each
  module as a tinted, dashed grouping box behind the types it owns,
  labelled with the module name in its deterministic per-module color.
  Layout is driven by `DagreLayoutEngine` running in compound-graph
  mode — one parent node per module — so the engine itself clusters the
  types and reports a bounding box per module (new `LayoutCluster` on
  `LayoutGraph`). The per-node bottom stripe is now a fallback, drawn
  only when no cluster boxes are present. Closes the last deferred
  M11/M12 Studio bullet.

### Changed — Bridge

- **`DependencyGraphGenerating` protocol gains a `forPackage` entry**
  with a default implementation that falls back to the path-based
  `generateScript(for:mode:with:)` over `sourceFileToModuleMap`. Mirrors
  the existing `ClassDiagramGenerating` shape so Studio's mock-injected
  generators degrade gracefully.
- **M12 follow-up: Mermaid and Nomnoml emit the SPM module stereotype.**
  `classdiagram --package` previously rendered the owning target name
  only in PlantUML output (`<<class>> <<Networking>>`); Mermaid and
  Nomnoml silently dropped the field. Both emitters now append the
  module as an additional `<<Module>>` annotation on each class node,
  matching PlantUML. The same parity applies to `deps --package`:
  Mermaid flowchart node labels gain a `<br/>«stereotype»` line
  (`App["App<br/>«executable»"]`) and Nomnoml inlines the stereotype
  into edge endpoints (`[App «executable»] --> [Core «library»]`).
  Closes the "Mermaid/Nomnoml emitter changes" deferred bullet across
  both `classdiagram` and `deps`.
- **M12 follow-up: `DagreLayoutEngine` gains compound-graph layout.**
  When a `LayoutGraph`'s nodes carry `module` values, the engine builds
  the dagre graph in compound mode — one parent node per module, every
  type re-parented beneath it — so dagre clusters the types and reports
  a bounding box per module. Results are parsed into a new
  `LayoutCluster` array on `LayoutGraph`; `SVGRenderer` draws each as a
  tinted, dashed labelled box behind the nodes. Graphs without module
  info are unaffected (plain non-compound layout, empty `clusters`).
- **Internal: duplication cleanup across the package (no behavior
  change; all 870 package tests still pass).** Consolidated repeated
  logic surfaced by `pmd cpd` — the package dropped from 30 copy-paste
  blocks to 4 (the remainder deliberate: base64 bit-twiddling,
  structurally-distinct loop skeletons):
  - XML and nomnoml escaping unified into `String.xmlEscaped` /
    `.nomnomlEscaped`, replacing copies in `SVGRenderer`,
    `SequenceSVGRenderer`, `ActivitySVGRenderer`,
    `ComponentSVGRenderer`, `SyntaxStructure+Nomnoml`, and `DepsScript`.
  - The CLI subcommands share a `CommonDiagramOptions` `@OptionGroup`
    (the `--format` / `--output` / `--config` triplet plus config
    resolution) and an `Optional<ClassDiagramOutput>.present(_:)`
    presenter selector, replacing the per-command `switch output` blocks.
    Entry-point parsing moves to `String.parsedEntryPoint()`.
  - New `TypeStackVisitor` base class hosts the
    class/struct/enum/actor/protocol/extension push-pop walk shared by
    `CallGraphExtractor` and `StateMachineExtractor`;
    `SyntaxStructureBuilder` collapses its five generic-bearing
    type-declaration visitors into one `handleTypeDeclaration` helper.
  - The three class-diagram emitters share `renderDiagramText` (the
    skip / generics / linking flow) and `renderableMember` (the member
    filter) via a new `SyntaxStructure+EmitterShared`.
  - Smaller shared helpers: `String.globPatternToRegex()`,
    `SyntaxStructure.isExcluded(byPatterns:)`,
    `CallGraphExtractor.entryPoints(for:)`, plus within-file dedup in
    `StateScript`, `SequenceScript`, `ActivityGraphBuilder+ControlFlow`
    (`wireBranch`), and `DependencyGraphGenerator` (`typeEdgeBasis`).

### Changed — Studio

- **M14: PlantUML rendering now requires one-time consent, and is no
  longer the sandbox default.** PlantUML previews render via
  `planttext.com` — a third-party HTTPS upload of the user's diagram
  source — which was previously undisclosed: the picker listed "PlantUML"
  alongside the local formats and the first preview silently pushed
  source off-device. Three changes: the App Store build defaults to
  Mermaid so a new user makes no network request without opting in
  (direct builds keep PlantUML as the default for backward
  compatibility); the first selection of `.plantuml` raises a consent
  alert disclosing the upload, with Continue persisting the grant and
  Cancel reverting the format; and the picker now reads
  "PlantUML (planttext.com)" so the network use is visible at the point
  of choice. Required for App Store Review privacy disclosure — the
  nutrition label and privacy policy remain outstanding.
- **M14: Mermaid / Nomnoml HTML builders no longer carry a CDN
  fallback.** `mermaid.min.js`, `graphre.js`, and `nomnoml.js` are always
  bundled into the `.app`, so the `cdn.jsdelivr.net` fallback never fired
  in production — but its presence meant a grep over the binary still
  showed third-party HTTPS references, and the "Mermaid and Nomnoml
  render locally" privacy claim had a silent escape hatch. Each fallback
  is replaced with an inline HTML comment marker, visible in DevTools if
  a build is ever misconfigured but incapable of producing a request.
  Tests now assert the invariant directly: no `https://` reference may
  appear in the emitted HTML regardless of bundle state.
- **Internal: native-canvas and view duplication cleanup (no behavior
  change; Studio's 439 unit and 20 UI tests still pass).** Reduced the
  app from 19 copy-paste blocks to 3 (the remainder the class/sequence
  interactive scaffold, whose modifier order matters for hit-testing):
  - The four native `Canvas` renderers share `canvasPanZoom` and
    `diagramCanvasChrome` view modifiers; the two non-interactive ones
    (activity, component) share a full `DiagramCanvasContainer` body.
    Arrowhead and center→bounds math move to
    `DiagramDrawing.fillArrowhead` and a `CenterPositioned.boundingRect`,
    and the title to `DiagramDrawing.drawTitle`.
  - UI components extracted: `EntryPointPicker` (activity / sequence
    control bars), `AppModePicker` + `PathSummaryLabel` (developer and
    Explorer toolbars), `HistoryListContent` (history list shared by
    `HistorySidebar` and the Explorer sidebar), and `SuggestionHandler`
    + a `.paywallSheet` modifier for the pro-gated suggestion dispatch
    shared by `ExplorerDetailView`, `ExplorerSidebar`, and
    `DiagramDetailView`. Accessibility identifiers are preserved, so the
    UI-test selectors are unchanged.
  - `DiagramViewModel` gains a `resolveEntryPoint()` helper shared by the
    activity and sequence generators.

### Documentation

- **M14 behavior is documented for users.** The sandboxed App Store build's
  differences had shipped with no user-facing documentation at all. The
  Studio User Guide gains an **App Store and Direct Download Builds**
  comparison (default format, `Open Package…` availability, the
  package-dependent features that fall away with it, and the loss of type
  *inference* — not of any diagram type — when SourceKit can't be loaded),
  and Troubleshooting gains matching entries for each symptom.
- **The planttext.com upload is disclosed in prose, not just in the
  consent alert.** A new section states plainly that previewing PlantUML
  sends generated markup — type names, member signatures, relationships,
  but not function bodies or literals — to a third party, that the other
  three formats render locally with no network access of any kind, and
  that the Markup tab is the escape hatch for confidential source.
  Written for the App Store privacy nutrition label, which remains
  outstanding.
- **M11: Xcode Cloud and Fastlane integration guides.** Neither has a
  plugin or marketplace equivalent, so both invoke the CLI directly —
  Xcode Cloud through a `ci_scripts/ci_post_clone.sh` custom build script,
  Fastlane through `sh` in a lane (with a `git diff --exit-code` drift
  check). Both call out `--output consoleOnly` as mandatory on headless
  machines, since the default presenter opens a browser. Closes the last
  open M11 item.
- **Corrected stale statements.** Troubleshooting claimed Mermaid loads
  `mermaid.js` from a CDN and that blocked network access yields a blank
  preview — the CDN fallback was removed and the JS is bundled, so the
  opposite is now true. The Studio guide's Xcode floor was 16.0; the
  embedded package's `swift-tools-version: 6.2` makes it 26.0. Four
  hardcoded `1.0.0` version strings across the user docs are now marked
  as examples so they don't go stale at the next release.

### Changed — Concurrency

- **Every `nonisolated(unsafe)` is gone.** Two sites, both replaced with a
  `Mutex` from `Synchronization` (available at the package's macOS 15
  floor):
  - `BridgeConfiguration.skipSourceKitTypenameSupplement` was one write
    at host start-up racing an unknown number of concurrent reads from
    whichever task was parsing. It held only by the convention that the
    write lands first, which nothing enforced. Setting it is now
    memory-safe at any point, though it remains a start-up decision by
    intent — flipping it mid-generation leaves some files parsed with the
    typename supplement and some without.
  - `SubscriptionManager.transactionListener` needed the opt-out because
    its two accesses straddle the type's isolation: `init` writes on the
    main actor, `nonisolated deinit` reads to cancel. Keeping the deinit
    nonisolated preserves immediate deallocation instead of hopping to
    the actor, so the property carries its own synchronisation.

- **`@unchecked Sendable` audited: 8 of 14 removed.** Six generators
  (Activity, Component, DependencyGraph, ER, Sequence, StateMachine) have
  no stored properties, so the attribute suppressed a check with nothing
  to check; they now declare plain `Sendable`. `ClassDiagramGenerator`
  joined them once `FileCollector`, also stateless, declared the
  conformance it always satisfied. The six that remain are load-bearing
  and now carry the reason in a comment: `DiagramScript` holds a mutable
  `DiagramContext` class, `SyntaxStructure` already documented itself,
  and four test spies never cross an isolation boundary.

### Fixed — Bridge

- **A data race in `SPMPackageReader.describe(at:)`'s timeout flag.** The
  private `UncheckedBox` it used documented a `DispatchGroup` as ordering
  its accesses. That holds for the stderr drain and not for `timedOut`:
  the watchdog is an `asyncAfter` work item outside the group, firing at
  an arbitrary moment, and `watchdog.cancel()` in the `defer` runs after
  the read and cannot stop a block already executing. Both call sites are
  now a `Mutex` and the box is gone.

- **`component --package` no longer hangs on SwiftPM's build lock.**
  SwiftPM locks its scratch directory for the length of a command, and
  `SPMPackageReader.describe(at:)` ran `swift package describe` against
  the package's own `.build`. Describing a package that another SwiftPM
  process was already using — most obviously the one you are building or
  testing from — blocked on that lock forever, with no output and no
  error. The command now runs with `--scratch-path` pointing at a private
  temporary directory, so there is no shared lock to queue behind;
  dependency resolution still reads the shared package cache, so this
  costs no re-cloning (0.32s either way). Chosen over detecting the
  condition, since a pre-flight lock check would race and sniffing
  SwiftPM's "waiting for lock" message would break on any rewording. A
  300s watchdog now also kills the subprocess and throws
  `ReadError.timedOut`, bounding the deadlocks not yet found — set far
  above any honest run, because a first-time resolve over a slow network
  is legitimately slow.
- **`SPMPackageReader.describe(at:)` no longer deadlocks on large
  `swift package describe` output.** It called `waitUntilExit()` before
  draining the child's pipes. Once output outgrows the pipe buffer
  (~64KB on Darwin) the child blocks writing into a full pipe nobody is
  reading while the parent blocks waiting for a child that cannot
  proceed — the CLI hangs with no output and no error. SwiftUMLBridge's
  own describe output is 11.9KB so it never tripped, but a package with a
  few thousand sources does. Both pipes are now drained *concurrently*
  before the wait: sequential draining would fix only the first stream,
  since filling either pipe stalls the child. Regression test generates a
  2,000-source package (~120KB of output) — it hung for over ten minutes
  before the fix and returns in about a second after it.

### Fixed — Studio (test infrastructure)

- **ViewInspector quarantine lifted.** Six tests were disabled because
  ViewInspector 0.10.3 could not read accessibility modifiers on
  macOS 27 — the OS replaced `AccessibilityProperties`' named members
  with a generic storage array. The same upstream PR
  (nalexn/ViewInspector#421, merged 2026-08-09) also fixes a more
  dangerous break: `GeometryProxy` has no public initializer, so
  ViewInspector fabricated one by `unsafeBitCast`-ing a fixed-size zeroed
  struct handling only 48 and 52 bytes; macOS 27 reports 76, and the
  unguarded fallback *trapped* rather than failed, killing the test
  process and reporting unrelated suites as failed.
  `NativeSequenceDiagramView`, `DiagramCanvasContainer`, and
  `NativeDiagramView` all render a `GeometryReader`, so any traversal was
  one scheduling change from crashlooping the target. Pinned to the exact
  upstream revision rather than the branch, since there is still no
  `0.10.4` tag — swap for a version requirement once it lands. The old
  compatibility test asserting `MemoryLayout<GeometryProxy>.size` was 48
  or 52 is replaced by two behavioural preflights, the size-agnostic fix
  having made the assertion both obsolete and wrong.

---

## [1.0.0] — 2026-05-11

First v1 cut. Component diagrams gain full Studio parity with the
other diagram types — including a native SwiftUI canvas, an SVG
format option, and PDF/PNG/SVG export — and CI is finally fully
green across both jobs.

### Added — Component Diagram in Studio

- **`DiagramMode.componentDiagram`** — Studio now surfaces the
  previously CLI-only Component diagram type. New row under the
  "Structural" section of the workspace sidebar (`shippingbox` icon),
  paywall-gated as `ProFeature.componentDiagrams`, with a
  guide-the-user-to-`Open Package…` empty state when no SPM
  package is loaded (Component diagrams are inherently
  package-scoped).
- **`ComponentDiagramGenerating` protocol** — Bridge gains the
  abstraction the other generators already had, so Studio can
  mock-inject `ComponentDiagramGenerator` for tests the same way
  it does class / sequence / deps / state / activity / ER.
- **`ComponentLayout` + `PositionedComponent`** — new public IR for
  laid-out component diagrams, mirroring `ActivityLayout` and
  `SequenceLayout`. Drives the native canvas in Studio.
- **`ComponentSVGRenderer`** — topological-level layout (consumer
  components at the top, depended-on leaves at the bottom; cycle-safe
  via a visiting-set guard) plus a standalone SVG document used as
  the WebView fallback when the user picks `.svg`.
- **`ComponentScript.componentLayout`** — populated when the script
  is rendered in `.svg` format; nil for PlantUML / Mermaid.
- **`DiagramOutputting.componentLayout`** — new optional protocol
  requirement with a `nil` default so existing conformers are
  unaffected.
- **`NativeComponentDiagramView`** — SwiftUI `Canvas` renderer with
  «component» header band, interface list, dotted dependency
  arrows, pan / zoom / ⌘+scroll-wheel zoom, and PDF / PNG / SVG
  export through the existing `DiagramExportMenu` plumbing.
- **Native canvas branches** in `DiagramPreviewView` and
  `DiagramExportMenu` for `componentLayout`. Viewport controls and
  the Export menu now light up in Component mode when `.svg` is
  picked.

### Added — Tests

- **11 new ComponentSVGRenderer tests** covering layout (single /
  multi component, dependency ordering, cycle safety, label-based
  sizing, input-order preservation), SVG output shape, and
  script-level format dispatch including Nomnoml → PlantUML fallback.
- **`MockComponentGenerator`** + dispatch / format-propagation
  coverage in `DiagramViewModelMockTests`.

### Changed — Test Stability

- **Mock generation tests** in `DiagramViewModelMockTests` /
  `DiagramViewModelMockStateTests` and the integration tests in
  `ViewModelFeatureTests` switched from a fixed
  `Task.sleep(for: .milliseconds(500))` (and a 10s wall-clock
  polling helper) to `await viewModel.currentTask?.value`. The
  former raced under CI load on macos-26; the deterministic task
  wait removes the flake without inflating local test wall-time.
- **DashboardUITests** — toolbar Save / Open buttons now carry
  `toolbarSaveButton` / `toolbarOpenButton` /
  `toolbarOpenPackageButton` accessibility identifiers, queried
  with `.firstMatch` to disambiguate the duplicate element the
  macOS 26 accessibility tree exposes on toolbar wrappers.

### Fixed — CI

- **Studio job now actually runs.** Pinned to the `macos-26`
  runner — `macos-latest` is still macOS 15, which can't load
  Studio's macOS 26.4+ test bundle. Bridge stays on
  `macos-latest` because it explicitly targets `.v15` for SPI
  reach.
- **Bridge platform lowered** to `.macOS(.v15)` so the package
  builds on the same CI runner that hosts every other Sequoia
  machine on the team. Studio still targets 26.4+.
- **Code signing disabled** for CI Studio builds
  (`CODE_SIGNING_ALLOWED=NO` + `CODE_SIGNING_REQUIRED=NO` +
  `CODE_SIGN_IDENTITY=`) — the development certificate is
  local-only and not available to runners; the binary isn't
  distributed from CI.
- **Pinned to `latest-stable` Xcode** via
  `maxim-lobanov/setup-xcode` so the Swift 6.2 toolchain the
  Bridge package manifest requires is actually present, and
  stopped hiding `xcodebuild` failures behind `xcbeautify`'s
  exit status.
- **Stale ProFeatureTests count** updated for the new
  `componentDiagrams` Pro feature case.

### Fixed — Bridge

- **`ClassDiagramCommand` help-text line length** — wrapped a 211-
  char `@Option(help:)` string to stay under the 200-char
  hard SwiftLint cap.

---

## [0.3.0] — 2026-05-09

This release lands every diagram type planned for the v1.0 surface
(seven total), the SwiftUML Studio macOS app with Explorer / Developer
modes and a Pro tier, the SwiftSyntax-primary parser, native SVG
rendering, and the Swift 6 strict-concurrency migration. Remaining
v1.0 work is App Store / SPI / Homebrew distribution and a small
backlog of explicitly-deferred Studio integrations called out below.

### Added — Diagram Types

- **Dependency graphs (M4)** — `swiftumlbridge deps` CLI command with `--modules`, `--types`, `--public-only`, `--exclude`; module-level and type-level dependency analysis with cycle detection; PlantUML and Mermaid emitters
- **Activity diagrams (M5)** — `swiftumlbridge activity` CLI; control-flow extraction from imperative function bodies (branches, loops, `switch`, `do/catch`); native SVG renderer
- **State machine diagrams (M6)** — `swiftumlbridge state` CLI; enum-driven state machine detection with confidence scoring, where-clause guards, property-wrapper enum inference; PlantUML, Mermaid, and SVG emitters
- **Entity-Relationship diagrams (M7)** — `swiftumlbridge er` CLI; SwiftData `@Model` and `@Relationship` extraction; PlantUML entity and Mermaid `erDiagram` emitters
- **ER expansion: Core Data + GRDB + SQLite.swift (M7+)** — `swiftumlbridge er` now also accepts Core Data `.xcdatamodeld` bundles (XML parsed via `XMLDocument`, version selected via `.xccurrentversion`, parentEntity surfaced as an "is a" edge) and Swift sources containing GRDB (`FetchableRecord`/`PersistableRecord`/etc. with `belongsTo` / `hasMany` / `hasOne` typed cardinality) or SQLite.swift (`Table("name")` + `Expression<T>("col")` namespace types). Studio's Open dialog accepts `.xcdatamodeld`. Closes all four sub-milestones (C1, C2, G1, G2) of `docs/internal/er-diagram-expansion-plan.md`.
- **Component diagrams** — new `swiftumlbridge component --package <Package.swift>` subcommand. Maps SPM targets to UML components, lists each target's public types as provided interfaces, and renders `target_dependencies` as `..>` edges. PlantUML emits standard `component` syntax with `<<library>>` / `<<executable>>` / `<<test>>` stereotypes; Mermaid falls back to a `flowchart TD` with subgraphs (Mermaid lacks a dedicated component dialect). Test targets are excluded by default; `--include-test-targets` opts in. Fills #4 ("Component diagram") in the prioritized ranking of `docs/internal/missing-uml-diagrams.md`. Studio integration deferred.

### Added — Output Formats

- **Nomnoml** class diagram emitter with locally bundled JS for offline rendering
- **Native SVG** format with Dagre layout via JavaScriptCore (Phase D), plus a SwiftUI `Canvas` renderer for in-app display

### Added — Parsing

- **SwiftSyntax-primary parser (M5)** — replaces SourceKitten as the primary AST source for newer functionality; SourceKitten retained for declarations
- **Macro-aware stereotypes** — `MacroConformanceTable` maps macros (`@Observable`, `@Model`, etc.) to synthetic conformances surfaced in diagrams
- Attribute fields exposed on `SyntaxStructure` for macro-aware diagrams
- **Multi-module SPM cross-references (M12)** — public `SPMPackageDescription` / `SPMTargetDescription` types and an `SPMPackageReader` that runs `swift package describe --type json`; new `ClassDiagramGenerator.generateScript(forPackage:packageRoot:)` entry tags each parsed type with its owning target. PlantUML emits the module as an additional stereotype (`<<class>> <<Networking>>`). Surfaced via `swiftumlbridge classdiagram --package <Package.swift>`. Mermaid/Nomnoml emitter changes, `--package` on `deps`, and Studio integration deferred.
- **`SequenceParticipant.sourceLocation`** — sequence-diagram participants now carry the source location of their underlying type so the Studio app can support reveal-in-source on participant clicks. `SequenceSVGRenderer.computeLayout` accepts an optional `typeLocations: [String: SourceLocation]` map that `SequenceDiagramGenerator` builds from a second pass over each file.

### Added — Diagram Interaction

- **Unified `DiagramViewport`** shared by the class, sequence, and activity native canvases — replaces three duplicated copies of scale/offset state
- **Floating zoom toolbar** (top-trailing): zoom in / zoom out / fit-to-window / actual size / reset, with a live percent label and standard mac shortcuts (⌘= ⌘− ⌘9 ⌘0 ⇧⌘R)
- **Single-click node selection** on class diagrams — selected node is drawn with an accent-colored ring; clicking the canvas background clears the selection
- **`SourceLocation` on `LayoutNode`** — public framework type carrying file path + 1-based line/column, populated by `SyntaxStructureBuilder` from a SwiftSyntax `SourceLocationConverter` for class / struct / enum / actor / protocol / extension declarations
- **"Reveal in Source"** floating button (⌘J) — when a node with a known `sourceLocation` is selected, opens the file in the developer-layout source pane, scrolls to the line, and highlights it in yellow
- **`SourceEditorView` rewritten** as an `NSViewRepresentable` around `NSTextView` to support line scrolling and back-fill highlighting (replaces the previous disabled `TextEditor`)
- **Hover tooltips** on class-diagram nodes — top-leading floating panel showing the node's stereotype, label, and (when available) the source `filename:line`
- **Diagram export menu** (top-trailing) — saves the currently-displayed diagram as PDF (vector, via SwiftUI `ImageRenderer` + `CGContext` PDF consumer), PNG (raster, 2× retina), SVG (when the script's format is already SVG), or source text (`.puml` / `.mmd` / `.nomnoml`) for WebView-rendered formats. Menu items adapt to what the active script supports.
- **Sequence-diagram selection + click-to-source** — single-click a participant box (top or bottom mirror) selects it (accent ring), hover shows the `NodeInfoTooltip`, and "Reveal in Source" jumps to the underlying type's declaration when known. Mirrors what class diagrams gained in the earlier phases.
- **Cmd+scroll-wheel zoom** on all three native canvases — wraps the SwiftUI canvas in an `NSHostingView` subclass that intercepts ⌘+scroll and calls `viewport.zoomIn`/`zoomOut`. Non-⌘ scroll falls through so trackpad pan still works. Cursor-centered zoom deferred.
- **Arrow-key navigation between selected nodes** — when a class- or sequence-diagram canvas has keyboard focus, arrow keys move the selection to the spatially nearest node in that direction (via `NativeDiagramGeometry.nextNode` — picks the closest candidate strictly past the current node along the dominant axis); Esc clears selection. Sequence diagrams only honor left/right since participants share a single row. Pressing an arrow with nothing selected picks the leftmost-topmost node as the starting point.

### Changed — Theming

- **Dark mode polish across native canvases and WebViews.** Native renderers now use `Color(nsColor: .labelColor)` / `.controlBackgroundColor` / `.textBackgroundColor` instead of hardcoded near-white/near-black values, so diagrams render correctly in dark mode. Activity-diagram start/end terminals and fork/join bars switched from a near-black fill (which disappeared into the dark background) to `.labelColor`. Mermaid in `DiagramWebView` now reads `colorScheme` and emits `theme: 'dark'` with a dark page background when applicable; Nomnoml and the SVG fallback adapt their page background. PlantUML remote rendering remains light-only (planttext.com is outside our control); Nomnoml's canvas content also stays light because nomnoml.js draws with hardcoded colors — both documented as known limitations.

### Added — Studio App

- **Two app modes** (`AppMode`): `explorer` (insight-driven default) and `developer` (full-featured three-pane workspace), toggled via the toolbar Picker
- **Project Dashboard** (`ProjectDashboardView`) with stats, insights, and one-click suggestion cards
- **InsightEngine** — plain-language project insights derived from `ProjectAnalyzer`
- **SuggestionEngine** + `SuggestionDispatcher` — actionable diagram suggestions with confidence scoring
- **Explorer Mode** — simplified UI for non-developer users (`ExplorerSidebar`, `ExplorerToolbar`, `ExplorerDetailView`)
- **Pro subscription tier** (StoreKit 2) — `SubscriptionManager`, `SubscriptionProviding`, `FeatureGate`, `PaywallView`, `ReviewReminderManager`, `Configuration.storekit`
- **Architecture Change Tracking (Phase 4)** — diff view comparing snapshots over time for Pro subscribers (`ArchitectureDiffView`, `ProjectSnapshot`, `SnapshotManager`)
- **3-pane NavigationSplitView** layout with sidebar / detail / inspector
- **History sidebar** with diagram restoration and entry-point menu
- **File browser sidebar** with tabbed preview
- **Live-updating preview** with explicit save action
- **MarkupView** annotation overlay tied to diagram entities
- **Inspector strip** + per-mode controls (`SequenceControlsView`, `ActivityControlsView`)
- **SPM package mode** — new "Open Package…" toolbar button (⇧⌘O) opens an SPM directory and runs `swift package describe` off the main actor; class-diagram generation switches to the module-aware `generateScript(forPackage:)` entry. Each native-canvas node gets a thin colored stripe along its bottom edge with the owning module's name (deterministic per-module color via `NativeDiagramGeometry.moduleColor`). The `ClassDiagramGenerating` protocol gained a default-implementing `generateScript(forPackage:)` so mocks degrade gracefully to the path-based flow. Per-module dashboard and module-grouped layout deferred.

### Added — Tests & Quality

- ViewInspector test coverage for `ProjectDashboardView`, `ArchitectureDiffView`, `PaywallView`, `DiagramPreviewView`, `HistoryItemRow`, `SnapshotRowView`, `MarkupView`
- Geometry helpers extracted from `NativeDiagramView` and `NativeSequenceDiagramView` for unit-testable layout
- Protocol abstractions (`DiagramGenerating` family, `SubscriptionProviding`) for dependency-injected testing
- SampleProject fixture enriched for state-machine and sequence-diagram coverage
- 89% test coverage on the Bridge package, 70%+ on the Studio app

### Changed

- **Project rename**: `SwiftPlantUMLstudio` → `SwiftUMLStudio` (working dir, GitHub repo, all targets)
- **Migrated persistence from Core Data to SwiftData** (`PersistenceController`, `DiagramEntity`, `ProjectSnapshot`)
- Modernized to macOS 26 `Tab` API in detail pane (replacing deprecated `tabItem()`)
- Moved project analysis off the main actor to avoid UI blocking
- Switched `Task.sleep` to `Duration`-based API
- Async/await for notification authorization request
- PRD revised to v1.2 covering both Bridge and Studio as first-class products
- CLAUDE.md refreshed to reflect post-M10 state (six diagram types, Swift 6 strict concurrency, Studio architecture)

### Fixed

- Sequence diagram regeneration bug from file-browser sidebar
- `@MainActor` test hangs and Core Data crashes on macOS 26 beta
- DiagramEntity crash; toolbar overflow on small windows
- Empty-paths crash in `ProjectAnalyzer`
- Test isolation issues (UserDefaults injection, removed no-op `.serialized`)
- All SwiftLint violations (multiple cleanup passes — final state: zero warnings, zero errors)
- Accessibility labels and deprecated APIs in native Canvas views
- Stale `ProFeatureTests` and `DiagramModeTests` after enum cases were added

### Removed

- Obsolete plan docs from earlier phases

---

## [0.2.0] — 2026-02-28

### Added

- **M2 — Mermaid.js class diagram output** — first-class Mermaid emitter alongside PlantUML
- **M3 — Sequence diagrams** — static call-graph extraction (`CallGraphExtractor`) and `SequenceDiagramGenerator` with PlantUML and Mermaid emitters; `--depth` and `--entry` CLI flags
- Studio user guide
- GitHub README

### Changed

- Eliminated all force unwraps and `@unchecked Sendable` annotations from the parsing and emitter layers

### Fixed

- SwiftLint violations across the SwiftUMLBridge package

---

## [0.1.0] — 2026-02-27

### Added

- SwiftUMLBridge local Swift package (M0): three-layer parsing/model/emitter architecture powered by SourceKitten, swift-argument-parser, and Yams
- `swiftumlbridge classdiagram` CLI command with `--format`, `--output`, `--sdk`, and `--exclude` options
- `BridgeLogger` singleton wrapping `os.Logger` (replaces SwiftyBeaver)
- macOS SwiftUI studio front-end (M1): file picker, PlantUML preview via planttext.com WebView, toolbar Generate button
- User guide, tutorial, and reference documentation in `docs/`
- Test suite raising SwiftUMLBridge framework coverage from 35% to 89% (229 tests)

### Changed

- **Swift 6 strict concurrency** (`846adfa`):
  - Enabled `swiftLanguageMode(.v6)` in `Package.swift` and `SWIFT_VERSION = 6.0` in the Xcode project for all targets
  - `DiagramPresenting` protocol replaced callback-based `present(script:completionHandler:)` with `async func present(script:)` and added `Sendable` conformance
  - `ClassDiagramGenerator.generate()` methods are now `async`; `DispatchSemaphore`-based `outputDiagram()` removed
  - New public `ClassDiagramGenerator.generateScript(for paths: [String], ...)` synchronous method as the GUI integration point
  - `BrowserPresenter.present()` wraps `NSWorkspace.shared.open()` in `await MainActor.run {}`
  - `BridgeLogger.shared` changed from `var` to `let`; class marked `@unchecked Sendable`
  - `DiagramScript` and `SyntaxStructure` marked `@unchecked Sendable`
  - Full `Sendable` conformance added to all model value types: `Color`, `Theme`, `Version`, `Stereotype`/`Stereotypes`/`Spot`, `Configuration`, `AccessLevel`, `ExtensionVisualization`, `RelationshipInlineStyle`, `RelationshipStyle`, `Relationship`, `RelationshipOptions`, `FileOptions`, `ElementOptions`, `PageTexts`
  - Static mutable singletons and collections converted from `var` to `let`
  - `ClassDiagramCommand` and `SwiftUMLBridgeCLI` migrated to `AsyncParsableCommand`
  - App `DiagramViewModel` replaced GCD + `SwiftUIPresenter` with `Task { await Task.detached { }.value }`
- `Color` enum cases converted to camelCase
- Yams dependency bumped from 5.0.0 to 6.0.0

### Removed

- `SwiftUIPresenter.swift` — no longer needed after async protocol migration
- `outputDiagram(for:with:processingStartDate:)` internal method on `ClassDiagramGenerator`
- All `DispatchSemaphore` usage

### Fixed

- All SwiftLint violations resolved at project inception
