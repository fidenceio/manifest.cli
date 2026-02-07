class Manifest < Formula
  desc "A powerful CLI tool for managing manifest files, versioning, and repository operations with trusted timestamp verification"
  homepage "https://github.com/fidenceio/manifest.cli"
  url "https://github.com/fidenceio/manifest.cli/archive/refs/tags/v32.0.0.tar.gz"
  sha256 "2a7d654e5c77a856467b04f75540cf2f020d55ee0056b78ba2c7654420017556"
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

  def post_install
    # Clean up legacy manual installations
    legacy_bin = Pathname.new(Dir.home)/".local"/"bin"/"manifest"
    legacy_dir = Pathname.new(Dir.home)/".manifest-cli"

    if legacy_bin.exist?
      legacy_bin.unlink
      ohai "Removed legacy manual install: #{legacy_bin}"
    end

    if legacy_dir.exist?
      legacy_dir.rmtree
      ohai "Removed legacy install directory: #{legacy_dir}"
    end
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

      To uninstall cleanly (removes config and env vars too):
        manifest uninstall

      For more information, visit: https://github.com/fidenceio/manifest.cli
    EOS
  end
end
