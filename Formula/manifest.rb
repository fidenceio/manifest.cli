class Manifest < Formula
  desc "A powerful CLI tool for managing manifest files, versioning, and repository operations with trusted timestamp verification"
  homepage "https://github.com/fidenceio/manifest.cli"
  url "https://github.com/fidenceio/manifest.cli/archive/refs/tags/v15.30.0.tar.gz"
  sha256 "3ed742f0f1e3875b1cfbf0ed388a7d01feb0f625739814b3ccdf7713e6c7c430"
  license "MIT"
  head "https://github.com/fidenceio/manifest.cli.git", branch: "main"

  # Minimal dependencies - only what's actually needed
  depends_on "git" => :recommended
  
  # Optional: coreutils for timeout command (if not available on system)
  depends_on "coreutils" => :optional

  def install
    # Install the CLI to bin
    bin.install "src/cli/manifest-cli-wrapper.sh" => "manifest"
    
    # Make it executable
    chmod 0755, bin/"manifest"
    
    # Copy project files to libexec
    libexec.install Dir["*"]
    
    # Create a simple wrapper that points to the installed location
    bin.install_symlink libexec/"src/cli/manifest-cli-wrapper.sh" => "manifest"
    
    # Update the wrapper to use the installed location
    inreplace bin/"manifest" do |s|
      s.gsub! /CLI_DIR="\$\(find_cli_dir\)"/, "CLI_DIR=\"#{libexec}\""
    end
    
    # Create a proper shebang
    inreplace bin/"manifest", "#!/bin/bash", "#!/usr/bin/env bash"
  end

  test do
    # Test basic functionality
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
        brew upgrade manifest    # Upgrade to latest version
        brew update && brew upgrade manifest  # Update Homebrew first, then upgrade
      
      For more information, visit: https://github.com/fidenceio/manifest.cli
    EOS
  end
end
