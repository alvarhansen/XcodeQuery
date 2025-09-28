class Xcq < Formula
  desc "Query and introspect Xcode projects from the CLI"
  homepage "https://github.com/alvarhansen/XcodeQuery"
  license "MIT"

  # Stable release installs prebuilt binary zip
  url "https://github.com/alvarhansen/XcodeQuery/releases/download/v0.1.2/xcq-v0.1.2-macos.zip"
  sha256 "84c39f3ed085191707480b60142c6945a2fccfcd8d851b9d1c55af9cf2842614"

  head "https://github.com/alvarhansen/XcodeQuery.git", branch: "main"

  depends_on xcode: :build if build.head?

  def install
    if build.head?
      ENV["SWIFTPM_DISABLE_SANDBOX"] = "1"
      system "swift", "build", "--disable-sandbox", "-c", "release"
      bin.install ".build/release/xcq"
    else
      bin.install "xcq"
    end
  end

  test do
    system bin/"xcq", "--help"
  end
end
