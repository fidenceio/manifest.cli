class Manifest < Formula
  desc "A powerful CLI tool for managing manifest files, versioning, and repository operations with trusted timestamp verification"
  homepage "https://github.com/fidenceio/manifest.cli"
  url "https://github.com/fidenceio/manifest.cli/archive/refs/tags/v8.6.7.tar.gz"
  sha256 "58cf69be3bb8190dd6f08c6ff327293a4d82d99ccebe823b727c89282635baeb"
  license "MIT"
  head "https://github.com/fidenceio/manifest.cli.git", branch: "main"

  depends_on "git" => :recommended
  depends_on "node" => ">=16.0.0"

  def install
    # Install the CLI to bin
    bin.install "src/cli/manifest-cli-wrapper.sh" => "manifest"
    
    # Make it executable
    chmod 0755, bin/"manifest"
    
    # Copy project files to libexec
    libexec.install Dir["*"]
    
    # Update the wrapper to point to the correct location
    inreplace bin/"manifest" do |s|
      s.gsub! "/Users/william/.manifest-cli", libexec
    end
    
    # Create a proper shebang
    inreplace bin/"manifest", "#!/bin/bash", "#!/usr/bin/env bash"
  end

  test do
    # Test basic functionality
    system bin/"manifest", "--help"
    
    # Test version
    assert_match "8.6.7", 1)
  end

  def caveats
    <<~EOS
      Manifest CLI has been installed as "manifest"
      
      To get started:
        manifest --help          # Show help
        manifest test            # Test functionality
        manifest ntp             # Get trusted timestamp
      
      The CLI will automatically detect your OS and apply optimizations.
      
      For more information, visit: https://github.com/fidenceio/manifest.cli
    EOS
  end
end
