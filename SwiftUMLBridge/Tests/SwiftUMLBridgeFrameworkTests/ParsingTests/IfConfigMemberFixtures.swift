// An `#if` block's clauses are read like the rest of the type, as the class diagram reads them
// (#135). Most tests run their source as written (`ifConfig → true`) and with every `#if`
// replaced by its first clause (`ifConfig → false`), which is the file the compiler sees when
// each condition holds. The second case is the control.

/// `text` with each `#if` line and `#endif` line removed, and each `#else` or `#elseif` clause
/// dropped. Not nested; the sources passed to it never nest.
func source(_ text: String, ifConfig: Bool) -> String {
    guard !ifConfig else { return text }
    var kept: [Substring] = []
    var skipping = false
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let directive = line.trimmingCharacters(in: .whitespaces)
        if directive.hasPrefix("#if") { continue }
        if directive.hasPrefix("#else") || directive.hasPrefix("#elseif") {
            skipping = true
            continue
        }
        if directive.hasPrefix("#endif") {
            skipping = false
            continue
        }
        if !skipping { kept.append(line) }
    }
    return kept.joined(separator: "\n")
}
