# Homebrew distribution

This directory holds the source of the `swiftumlbridge` formula. It is
**not** itself a tap. The published tap is the separate repository
[`Joseph-Cursio/homebrew-tap`](https://github.com/Joseph-Cursio/homebrew-tap),
whose `Formula/swiftumlbridge.rb` mirrors the file here.

## Installing

```bash
brew install Joseph-Cursio/tap/swiftumlbridge
```

Use the full name. Homebrew 7 refuses a bare `brew install swiftumlbridge`
from a tap it does not trust yet, and this form adds the tap and trusts the
formula. It also refuses to install from a path such as
`./homebrew/Formula/swiftumlbridge.rb`, because a formula has to be in a tap.

## Updating for new releases

1. Tag a new release and publish it through GitHub (see `gh release create`).
2. Fetch the tarball and compute its SHA256:

   ```bash
   curl -sL https://github.com/Joseph-Cursio/SwiftUMLStudio/archive/refs/tags/vX.Y.Z.tar.gz \
     | shasum -a 256
   ```

3. Bump the `url`, `sha256`, and `test do` version assertion in
   `Formula/swiftumlbridge.rb`. Bump the `Version.current` constant in
   the framework *before* tagging so the CLI's `--version` flag matches
   the formula's assertion.
4. Copy the file to `Formula/swiftumlbridge.rb` in the tap repository, and
   land it there. Users get the tap's copy, not this one.
5. Check the published tap, on a machine without the formula installed:

   ```bash
   brew install Joseph-Cursio/tap/swiftumlbridge
   brew test swiftumlbridge
   ```

   `brew test` covers `--version`, `--help` and an SVG class diagram. To clean
   up with `brew uninstall`, set `HOMEBREW_NO_AUTOREMOVE=1` first, or Homebrew
   also removes any other formula nothing depends on.
