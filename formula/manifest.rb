class Manifest < Formula
  desc "A powerful CLI tool for managing manifest files, versioning, and repository operations with trusted timestamp verification"
  homepage "https://github.com/fidenceio/manifest.cli"
  url "https://github.com/fidenceio/manifest.cli/archive/refs/tags/v46.11.0.tar.gz"
  sha256 "81c8a99644c02af00b602e686227d6d14f19ec2d7c947023c5345243618c3d34"
  license "MIT"
  head "https://github.com/fidenceio/manifest.cli.git", branch: "main"

  depends_on "bash"
  depends_on "git" => :recommended
  depends_on "yq" => :recommended
  depends_on "coreutils" => :optional

  def install
    # Copy all project files to libexec
    libexec.install Dir["*"]

    # Create a wrapper script that points to the installed location.
    # Homebrew may launch this through macOS /bin/bash 3.2; re-exec into the
    # formula dependency before sourcing modules that use Bash 5 features.
    (bin/"manifest").write <<~EOS
      #!/usr/bin/env bash
      set -e

      ensure_bash5_or_reexec() {
        local min_major=5
        local current_major="${BASH_VERSINFO[0]:-0}"

        if [ "$current_major" -ge "$min_major" ]; then
          return 0
        fi

        if [ "${MANIFEST_CLI_BASH_REEXEC:-0}" = "1" ]; then
          echo "Manifest CLI requires Bash 5+." >&2
          echo "Current shell: bash ${BASH_VERSION:-unknown}" >&2
          echo "Install Bash 5+ and retry." >&2
          return 1
        fi

        local candidate major
        local candidates=(
          "${MANIFEST_CLI_BASH_PATH:-}"
          "#{Formula["bash"].opt_bin}/bash"
          "/opt/homebrew/bin/bash"
          "/usr/local/bin/bash"
          "$(command -v bash 2>/dev/null || true)"
          "/bin/bash"
        )

        for candidate in "${candidates[@]}"; do
          if [ -z "$candidate" ] || [ ! -x "$candidate" ]; then
            continue
          fi

          major="$("$candidate" -c 'echo "${BASH_VERSINFO[0]:-0}"' 2>/dev/null || echo "0")"
          if [ "$major" -ge "$min_major" ]; then
            MANIFEST_CLI_BASH_REEXEC=1 exec "$candidate" "$0" "$@"
          fi
        done

        echo "Manifest CLI requires Bash 5+." >&2
        echo "Current shell: bash ${BASH_VERSION:-unknown}" >&2
        echo "No compatible bash found in common locations." >&2
        return 1
      }

      ensure_bash5_or_reexec "$@"

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
    system bin/"manifest", "status"
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
