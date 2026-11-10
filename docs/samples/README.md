# Samples

Self-contained mini-projects that exercise each `swiftumlbridge` subcommand. Every sample ships a `README.md` with the exact CLI command to run and a short description of what to expect in the output. Each is small enough to read end-to-end at a glance.

These doubles as end-to-end install smoke tests — if all seven samples produce non-empty output on your machine, your `swiftumlbridge` install is working.

## Prerequisites

Install the CLI via [Homebrew](../user/user-guide.md#installation):

```bash
brew install Joseph-Cursio/tap/swiftumlbridge
```

If you built from source instead, substitute `swift run --package-path /path/to/SwiftUMLBridge swiftumlbridge` for `swiftumlbridge` in the commands below.

## Index

| Sample | Demonstrates | Subcommand |
|---|---|---|
| [class-diagram](class-diagram/) | Inheritance, protocol conformance, extensions | `classdiagram` |
| [sequence-diagram](sequence-diagram/) | Static call-graph trace with async/sync arrow distinction | `sequence` |
| [activity-diagram](activity-diagram/) | Control flow: loops, switch, do/catch, await | `activity` |
| [state-machine](state-machine/) | Enum-driven state machine with switch-based transitions | `state` |
| [dependency-graph](dependency-graph/) | Module-level imports with a cycle to demonstrate cycle annotation | `deps` |
| [er-diagram](er-diagram/) | SwiftData `@Model` + `@Relationship` cardinality | `er` |
| [component-diagram](component-diagram/) | SPM targets, `target_dependencies`, and provided interfaces | `component` |

## Notes

- The samples produce diagrams via `--output consoleOnly` so output is print-and-pipe-friendly. Drop the flag (or use `--output browser`) to open each diagram interactively in PlantText or Mermaid Live.
- None of these samples need to compile — `swiftumlbridge` parses Swift source statically. The dependency-graph sample, for example, imports module names that aren't real SwiftPM modules; that's fine for the static parser, even though it wouldn't build.
