import Foundation
import Synchronization

// MARK: - Alias Chains

/// How a chain of typealiases is followed to its end (#248), kept apart so the type lookup stays
/// a readable size.
extension LayoutGraphBuilder {
    /// The typealiases one walk along a chain has followed, so a cycle of them, which Swift
    /// rejects, ends where it comes back to one, and a chain without one runs to its end, however
    /// long (#248). A step from an alias to its target keeps the walk's depth and passes the
    /// chain on; a lookup made inside a step, as of the target's name, is one level deeper and
    /// starts a chain of its own. So the next step from an alias depends on that alias, the depth
    /// and whether modules are read alone, and a walk comes back to an alias only round a cycle:
    /// what it finds then, nothing, is what any walk from that alias at that depth finds, so
    /// `AliasWalks` and `AliasKinds` can keep it. A walk that starts reading modules on the way,
    /// through sugar, starts a new chain, as an alias it followed before may come to another type
    /// now. The depth guards still end the loops that go through such inner lookups (#244).
    /// `mayMeanOutsideMember` and `spelledThroughStart` start a chain at the same depth, and
    /// neither comes back to a step without going a level deeper. `startsAtProjectType` follows
    /// only the leading part of a name, so it keeps the parts after it as well
    /// (`TypeLookup.decidingStep`). Aliases are told apart by `Declared`, as `AliasWalks` keys
    /// them: every one is recorded before any lookup, so there are only so many.
    struct AliasChain {
        private var followed: Set<ObjectIdentifier> = []

        /// Adds `alias` to the chain, `false` when it already was. In place, so a step costs no
        /// copy of the aliases before it.
        mutating func follow(_ alias: Declared) -> Bool {
            followed.insert(ObjectIdentifier(alias)).inserted
        }
    }

    /// What a walk from each typealias comes to, by depth and whether modules are read, so a
    /// chain many writers end on is walked once for each: the type
    /// (`TypeLookup.aliased(_:depth:readingModules:chain:)`), or the name
    /// (`TypeLookup.resolvedName(of:from:readingModules:depth:)`,
    /// `TypeLookup.sureResolvedName(of:from:depth:)`). It keeps each `Declared`, so no key's
    /// address is reused while its entry lives.
    final class AliasWalks<Value: Sendable>: Sendable {
        private let entryForKey = Mutex<[AliasTargetKey: AliasWalk<Value>]>([:])

        /// What a walk from `alias` at `depth` comes to, once worked out.
        func entry(for alias: Declared, depth: Int, readingModules: Bool) -> AliasWalk<Value>? {
            let key = AliasTargetKey(alias: ObjectIdentifier(alias), depth: depth, readingModules: readingModules)
            return entryForKey.withLock { $0[key] }
        }

        /// Keeps `value` as what a walk from `alias` at `depth` comes to.
        func record(_ value: Value, for alias: Declared, depth: Int, readingModules: Bool) {
            let key = AliasTargetKey(alias: ObjectIdentifier(alias), depth: depth, readingModules: readingModules)
            entryForKey.withLock { $0[key] = AliasWalk(alias: alias, value: value) }
        }
    }

    /// A typealias and what a walk from it comes to (`AliasWalks`).
    struct AliasWalk<Value: Sendable>: Sendable {
        let alias: Declared
        let value: Value
    }

    /// A typealias `AliasWalks` keeps a walk of, with the depth and whether modules are read.
    struct AliasTargetKey: Hashable {
        let alias: ObjectIdentifier
        let depth: Int
        let readingModules: Bool
    }
}

// An extension of `TypeLookup` in another file does not see the builder's own names, so they are
// written out in full.
extension LayoutGraphBuilder.TypeLookup {
    /// `declared` itself, or for a typealias the type it aliases, as seen from the alias. An
    /// alias of sugar means what an extension so written extends
    /// (`extendedType(named:from:isSugared:depth:)`): Swift's `Array` for `[Int]`, which is
    /// outside the diagram (#126). Each step follows one alias at the same depth, so a chain of
    /// any length runs to its end, and a cycle, which Swift rejects, ends where it comes back
    /// to an alias (`AliasChain`) with nothing; the depth guard ends the lookups made inside
    /// the steps (#248). What each alias comes to is kept (`AliasWalks`).
    func aliased(
        _ declared: Declared,
        depth: Int,
        readingModules startsReadingModules: Bool = true,
        chain startingChain: LayoutGraphBuilder.AliasChain = LayoutGraphBuilder.AliasChain()
    ) -> Declared? {
        // A loop rather than a call a step, so a long chain takes no more stack than a short one.
        var (current, chain, readingModules) = (declared, startingChain, startsReadingModules)
        var followed: [(alias: Declared, readingModules: Bool)] = []
        var found: Declared?
        while true {
            guard let target = current.aliasTarget else {
                found = current
                break
            }
            guard depth < 8, chain.follow(current) else { break }
            if let known = aliasTargets.entry(for: current, depth: depth, readingModules: readingModules) {
                found = known.value
                break
            }
            followed.append((current, readingModules))
            let match: Match?
            if current.isSugared {
                // A member path past the sugar, as `extendedType(named:from:isSugared:depth:)` reads it.
                guard target.contains(".") else { break }
                let member = LayoutGraphBuilder.QualifiedName(name: target, root: .outsideType)
                match = nearestMatch(member, from: current.scope, depth: depth)
                if !readingModules {
                    // An alias followed without reading modules may come to another type reading
                    // them, so coming back to it is no cycle; this sugar's step reads them either way.
                    chain = LayoutGraphBuilder.AliasChain()
                    _ = chain.follow(current)
                }
                readingModules = true
            } else {
                let targetName = qualifiedName(
                    ofWritten: target, from: current.scope, depth: depth + 1, readingModules: readingModules
                )
                match = nearestMatch(targetName, from: current.scope, depth: depth, readingModules: readingModules)
            }
            guard let match else { break }
            current = match.declared
        }
        for step in followed {
            aliasTargets.record(found, for: step.alias, depth: depth, readingModules: step.readingModules)
        }
        return found
    }
}
