class Swiftumlbridge < Formula
  desc "Generate architectural UML diagrams from Swift source"
  homepage "https://github.com/Joseph-Cursio/SwiftUMLStudio"
  url "https://github.com/Joseph-Cursio/SwiftUMLStudio/archive/refs/tags/v1.2.0.tar.gz"
  sha256 "db739506cf5bcc2e69f982c01901c282af2e095caaa5797412e40f0b4f549d8f"
  license "MIT"
  head "https://github.com/Joseph-Cursio/SwiftUMLStudio.git", branch: "main"

  # Bridge's Package.swift declares swift-tools-version: 6.2, which first
  # ships with Xcode 26. Anything older — including Xcode 16's Swift 6.0 /
  # 6.1 — refuses to parse the manifest, so we gate explicitly rather than
  # let the build fail partway through with a manifest error.
  depends_on xcode: ["26.0", :build]
  depends_on :macos
  on_macos do
    depends_on macos: :sequoia
  end

  def install
    cd "SwiftUMLBridge" do
      system "swift", "build",
             "--disable-sandbox",
             "--configuration", "release",
             "--product", "swiftumlbridge"
      # SVG output reads graphre.js from this bundle, which SwiftPM looks for
      # beside the executable, so the two have to stay in one directory.
      libexec.install ".build/release/swiftumlbridge",
                      ".build/release/SwiftUMLBridge_SwiftUMLBridgeFramework.bundle"
      bin.write_exec_script libexec/"swiftumlbridge"
    end
  end

  test do
    assert_match "1.2.0", shell_output("#{bin}/swiftumlbridge --version")
    assert_match "swiftumlbridge", shell_output("#{bin}/swiftumlbridge --help")
    (testpath/"Sample.swift").write "class Base {}\nclass Sub: Base {}\n"
    svg = shell_output("#{bin}/swiftumlbridge classdiagram #{testpath} --format svg --output consoleOnly")
    assert_match "<svg", svg
  end
end
