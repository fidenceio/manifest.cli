class Manifest < Formula
  desc "A powerful CLI tool for managing manifest files, versioning, and repository operations with trusted timestamp verification"
  homepage "https://github.com/fidenceio/manifest.cli"
  url "https://github.com/fidenceio/manifest.cli/archive/refs/tags/v30.1.0.tar.gz"
  sha256 "8898ed8a3aa94426cb3f8bea25ec0b23bdb749ecd5b71d5664066c3b708bb10b"
  license "MIT"
  head "https://github.com/fidenceio/manifest.cli.git", branch: "main"

  depends_on "git" => :recommended
  depends_on "coreutils" => :optional

  def install
    # Copy all project files to libexec
    libexec.install Dir["*"]

    # Create a wrapper script that points to the installed location
    (bin/"manifest").write <<~EOS
      #!/usr/bin/env bash
      set -e
      CLI_DIR="#{libexec}"
      source "$CLI_DIR/modules/core/manifest-core.sh"
      main "$@"
    EOS
  end

  test do
    system bin/"manifest", "--help"
  end

  def caveats
    <<~EOS
      Manifest CLI has been installed as "manifest"

      To get started:
        manifest --help          # Show help
        manifest test            # Test functionality
        manifest ntp             # Get trusted timestamp

      The CLI will automatically detect your OS and apply optimizations.

      To always get the latest version:
        brew update && brew upgrade manifest

      For more information, visit: https://github.com/fidenceio/manifest.cli
    EOS
  end
end
