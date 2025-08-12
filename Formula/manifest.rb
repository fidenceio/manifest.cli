class Manifest < Formula
  desc "Complete local development system for Git workflows, version management, and documentation generation"
  homepage "https://github.com/fidenceio/manifest.local"
  url "https://github.com/fidenceio/manifest.local/archive/refs/tags/v3.0.2.tar.gz"
  sha256 "SKIP"  # Will be calculated when we create the release
  license "MIT"
  head "https://github.com/fidenceio/manifest.local.git", branch: "main"

  depends_on "node" => :build
  depends_on "git"

  def install
    # Install Node.js dependencies
    system "npm", "install", "--production"
    
    # Create the CLI executable using the standalone script
    bin.install "src/cli/manifest-standalone.js" => "manifest"
    
    # Make it executable
    chmod 0755, bin/"manifest"
    
    # Create the installation directory structure
    libexec.install Dir["*"]
    
    # Create the configuration directory
    (etc/"manifest").mkpath
    
    # Install example configuration files
    (etc/"manifest").install "env.example" if File.exist?("env.example")
    (etc/"manifest").install ".manifestrc.example" if File.exist?(".manifestrc.example")
    
    # Create the data directory
    (var/"lib/manifest").mkpath
    
    # Create the log directory
    (var/"log/manifest").mkpath
  end

  def post_install
    # Create user-specific configuration directory
    (Dir.home/".manifest-local").mkpath
    
    # Create a default .env file if it doesn't exist
    env_file = Dir.home/".manifest-local/.env"
    unless env_file.exist?
      env_file.write <<~EOS
        # Manifest Local Configuration
        # Copy from #{etc}/manifest/env.example and customize as needed
        
        # Local service configuration (optional)
        MANIFEST_LOCAL_SERVICE_URL=http://localhost:3001
        
        # CLI preferences
        MANIFEST_AUTO_COMMIT=true
        MANIFEST_AUTO_PUSH=true
      EOS
    end
    
    # Set proper permissions
    system "chmod", "600", env_file.to_s
    
    puts <<~EOS
      🎉 Manifest CLI installed successfully!
      
      📁 Configuration files:
         CLI config: ~/.manifest-local/.env
         System config: #{etc}/manifest/
         Data directory: #{var}/lib/manifest/
         Log directory: #{var}/log/manifest/
      
      🚀 Quick start:
         manifest help                    # Show available commands
         manifest diagnose               # Check system health
         manifest go patch               # Automated version bump
      
      📚 Documentation: #{homepage}
      
      💡 To start the local service (optional):
         docker-compose up -d
    EOS
  end

  def caveats
    <<~EOS
      Manifest CLI has been installed to #{bin}/manifest
      
      The CLI will automatically create configuration files in ~/.manifest-local/
      
      For the complete system with local service:
      1. Clone the repository: git clone #{homepage}
      2. Start services: docker-compose up -d
      3. Configure: cp env.example .env
      
      For CLI-only usage, no additional setup is required.
    EOS
  end

  test do
    # Test that the CLI can be executed
    system bin/"manifest", "--help"
    
    # Test basic functionality
    output = shell_output("#{bin}/manifest --help", 1)
    assert_match "Manifest Local CLI", output
  end
end
