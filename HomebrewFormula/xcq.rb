class Xcq < Formula
  desc "Query and introspect Xcode projects from the CLI"
  homepage "https://github.com/alvarhansen/XcodeQuery"
  license "MIT"

  # Stable release
  url "https://github.com/alvarhansen/XcodeQuery/archive/refs/tags/v0.1.2.tar.gz"
  sha256 "f3001f344efaffd67e82419b516565a211a438a07a6a7a44f36cafa5c260db2c"

  head "https://github.com/alvarhansen/XcodeQuery.git", branch: "main"

  depends_on xcode: :build

  def install
    ENV["SWIFTPM_DISABLE_SANDBOX"] = "1"
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/xcq"
  end

  test do
    system bin/"xcq", "--help"
end
end
