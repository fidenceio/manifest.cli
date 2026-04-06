class Manifest < Formula
  desc "A powerful CLI tool for managing manifest files, versioning, and repository operations with trusted timestamp verification"
  homepage "https://github.com/fidenceio/manifest.cli"
  url "https://github.com/fidenceio/manifest.cli/archive/refs/tags/v42.0.3.tar.gz"
  sha256 "2ca4e30ad5496a9ab907bc8319228749cbd1cf96ce6b68ae9dcce9ec922fe7d1"
  license "MIT"
  head "https://github.com/fidenceio/manifest.cli.git", branch: "main"

  depends_on "bash" => :recommended
  depends_on "git" => :recommended
  depends_on "yq" => :recommended
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
    # Clean up legacy manual installation binary (conflicts with Homebrew binary).
    # NOTE: ~/.manifest-cli is intentionally preserved — it is the runtime state/data
    # directory (logs, config markers, etc.), NOT a legacy install artifact.
    legacy_bin = Pathname.new(Dir.home)/".local"/"bin"/"manifest"
    user_global_config = Pathname.new(Dir.home)/".manifest-cli"/"manifest.config.global.yaml"

    if legacy_bin.exist?
      legacy_bin.unlink
      ohai "Removed legacy manual install binary: #{legacy_bin}"
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
        manifest time            # Get trusted timestamp

      The CLI will automatically detect your OS and apply optimizations.

      To always get the latest version:
        brew update && brew upgrade manifest

      To uninstall cleanly (removes config and env vars too):
        manifest uninstall

      For more information, visit: https://github.com/fidenceio/manifest.cli
    EOS
  end
end
