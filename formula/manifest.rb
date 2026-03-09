class Manifest < Formula
  desc "A powerful CLI tool for managing manifest files, versioning, and repository operations with trusted timestamp verification"
  homepage "https://github.com/fidenceio/manifest.cli"
  url "https://github.com/fidenceio/manifest.cli/archive/refs/tags/v36.1.0.tar.gz"
  sha256 "fcbeb711bd18373eca9ed98996d689946425402414f37442e86f8bfa46e237a9"
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
    user_global_config = Pathname.new(Dir.home)/".env.manifest.global"

    if legacy_bin.exist?
      legacy_bin.unlink
      ohai "Removed legacy manual install: #{legacy_bin}"
    end

    if legacy_dir.exist?
      legacy_dir.rmtree
      ohai "Removed legacy install directory: #{legacy_dir}"
    end

    # Apply config migrations so `brew upgrade` is functionally equivalent
    # to `manifest upgrade --force` for user-global settings.
    if user_global_config.exist?
      migration_cmd = [
        "#{bin}/manifest",
        "config",
        "doctor",
        "--fix",
        "--file",
        user_global_config.to_s
      ]

      if system(*migration_cmd)
        ohai "Migrated user config: #{user_global_config}"
      else
        opoo "Could not auto-migrate #{user_global_config}. Run: manifest config doctor --fix"
      end
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
