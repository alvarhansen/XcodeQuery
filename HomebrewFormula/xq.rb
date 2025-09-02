class Xq < Formula
  desc "Query and introspect Xcode projects from the CLI"
  homepage "https://github.com/alvarhansen/XcodeQuery"
  license "MIT"

  # Stable release (update url, version, and sha256 on each release)
  # Example for tag v0.1.0:
  # url "https://github.com/alvarhansen/XcodeQuery/archive/refs/tags/v0.1.0.tar.gz"
  # sha256 "REPLACE_WITH_TARBALL_SHA256"

  head "https://github.com/alvarhansen/XcodeQuery.git", branch: "main"

  depends_on xcode: :build

  def install
    system "swift", "build", "-c", "release"
    bin.install ".build/release/xq"
  end

  test do
    system bin/"xq", "--help"
  end
end
