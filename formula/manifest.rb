class Manifest < Formula
  desc "A powerful CLI tool for managing manifest files, versioning, and repository operations with trusted timestamp verification"
  homepage "https://github.com/fidenceio/manifest.cli"
  url "https://github.com/fidenceio/manifest.cli/archive/refs/tags/v52.3.1.tar.gz"
  sha256 "b44fbc7812aab39caf9f2e0be2e8ec771a6e8aa0d95cc1e922dd39a959aa4bb9"
  license "Apache-2.0"
  head "https://github.com/fidenceio/manifest.cli.git", branch: "main"

  depends_on "bash"
  depends_on "git" => :recommended
  depends_on "yq"
  # GNU userland: coreutils ships gdate/gstat (and the gnubin date/stat),
  # gnu-sed ships GNU sed. The bin wrapper forces their gnubin onto PATH so the
  # CLI runs one GNU codepath (sed -i / date -d / stat -c) instead of branching
  # on BSD. coreutils alone is insufficient — GNU sed lives in gnu-sed.
  depends_on "coreutils"
  depends_on "gnu-sed"

  def install
    # Copy all project files to libexec
    libexec.install Dir["*"]
    bash_completion.install libexec/"completions/manifest.bash" => "manifest"
    zsh_completion.install libexec/"completions/_manifest"
    fish_completion.install libexec/"completions/manifest.fish"

    # Create a wrapper script that points to the installed location.
    # Homebrew may launch this through macOS /bin/bash 3.2; re-exec into the
    # formula dependency before sourcing modules that use Bash 5 features.
    (bin/"manifest").write <<~EOS
      #!/usr/bin/env bash
      set -e

      CLI_DIR="#{libexec}"
      source "$CLI_DIR/modules/core/manifest-requirements.sh"

      # Put GNU sed/date/stat ahead of the BSD builtins on macOS before re-exec,
      # so the relaunched shell (and every module) runs one GNU codepath. The
      # formula declares coreutils + gnu-sed, so these gnubin dirs are present.
      manifest_requirement_prepend_gnu_userland_path

      ensure_bash5_or_reexec() {
        local current_major="${BASH_VERSINFO[0]:-0}"

        if manifest_requirement_bash_is_supported_major "$current_major"; then
          return 0
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

          major="$(manifest_requirement_bash_major_from_command "$candidate")"
          if manifest_requirement_bash_is_supported_major "$major"; then
            MANIFEST_CLI_BASH_REEXEC=1 exec "$candidate" "$0" "$@"
          fi
        done

        echo "Manifest CLI requires Bash ${MANIFEST_CLI_REQUIRED_BASH_VERSION}+." >&2
        echo "Current shell: bash ${BASH_VERSION:-unknown}" >&2
        echo "No compatible bash found in common locations." >&2
        return 1
      }

      ensure_bash5_or_reexec "$@"

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

      To preview a clean uninstall:
        manifest uninstall

      To uninstall cleanly (removes config and env vars too):
        manifest uninstall -y

      For more information, visit: https://github.com/fidenceio/manifest.cli
    EOS
  end
end
