# Fish completion for Manifest CLI.
# Install: copy or symlink this file into a fish completions dir, e.g.
#   ~/.config/fish/completions/manifest.fish
# Homebrew puts user completions in (brew --prefix)/share/fish/vendor_completions.d/.

# Mirrors the command coverage of completions/manifest.bash and completions/_manifest.

# --- helpers -----------------------------------------------------------------

# True when the command line is at the Nth positional token (after `manifest`),
# i.e. exactly N tokens follow the program name. Lets us scope completions to a
# subcommand depth without matching deeper.
function __manifest_token_count
    set -l tokens (commandline -opc)
    test (count $tokens) -eq $argv[1]
end

# True when the leading positional tokens after `manifest` match the given words.
function __manifest_path
    set -l tokens (commandline -opc)
    set -l want $argv
    test (count $tokens) -ge (math (count $want) + 1)
    or return 1
    for i in (seq (count $want))
        test "$tokens[(math $i + 1)]" = "$want[$i]"
        or return 1
    end
    return 0
end

# Cached config-key lookup (refreshes once per shell session by default).
function __manifest_keys
    if not set -q _MANIFEST_FISH_KEYS_CACHE
        set -g _MANIFEST_FISH_KEYS_CACHE (manifest config list 2>/dev/null | awk 'NR>2 && $1!="" {print $1}' | sort -u)
    end
    printf '%s\n' $_MANIFEST_FISH_KEYS_CACHE
end

# --- top-level commands ------------------------------------------------------

complete -c manifest -f

complete -c manifest -n '__manifest_token_count 1' -a config      -d 'Setup wizard / show configuration'
complete -c manifest -n '__manifest_token_count 1' -a init        -d 'Scaffold a repo or fleet'
complete -c manifest -n '__manifest_token_count 1' -a quickstart  -d 'Run an opinionated quickstart workflow'
complete -c manifest -n '__manifest_token_count 1' -a plan        -d 'Generate an adoption plan'
complete -c manifest -n '__manifest_token_count 1' -a reconcile   -d 'Validate and apply an adoption plan'
complete -c manifest -n '__manifest_token_count 1' -a status      -d 'Read-only snapshot'
complete -c manifest -n '__manifest_token_count 1' -a recipe      -d 'Inspect workflow recipes'
complete -c manifest -n '__manifest_token_count 1' -a discover    -d 'Discover resources without writing changes'
complete -c manifest -n '__manifest_token_count 1' -a update      -d 'Update fleet membership'
complete -c manifest -n '__manifest_token_count 1' -a add         -d 'Add a resource to Manifest-managed configuration'
complete -c manifest -n '__manifest_token_count 1' -a validate    -d 'Validate fleet configuration'
complete -c manifest -n '__manifest_token_count 1' -a prep        -d 'Connect remotes, pull latest'
complete -c manifest -n '__manifest_token_count 1' -a refresh     -d 'Regenerate docs and metadata'
complete -c manifest -n '__manifest_token_count 1' -a docs        -d 'Generate fleet documentation'
complete -c manifest -n '__manifest_token_count 1' -a ship        -d 'Publish a release (version + tag + push)'
complete -c manifest -n '__manifest_token_count 1' -a pr          -d 'Pull-request operations (gh wrapper)'
complete -c manifest -n '__manifest_token_count 1' -a doctor      -d 'Health check'
complete -c manifest -n '__manifest_token_count 1' -a security    -d 'Security audit'
complete -c manifest -n '__manifest_token_count 1' -a upgrade     -d 'Update Manifest CLI'
complete -c manifest -n '__manifest_token_count 1' -a uninstall   -d 'Remove Manifest CLI'
complete -c manifest -n '__manifest_token_count 1' -a version     -d 'Show CLI version'
complete -c manifest -n '__manifest_token_count 1' -a help        -d 'Show help'

# --- subcommands (token 2) ---------------------------------------------------

# Commands that take a repo|fleet scope.
set -l __manifest_scoped 'init quickstart plan reconcile discover update add validate prep refresh docs ship'
for cmd in (string split ' ' $__manifest_scoped)
    complete -c manifest -n "__manifest_token_count 2; and __manifest_path $cmd" -a repo  -d 'Single-repo scope'
    complete -c manifest -n "__manifest_token_count 2; and __manifest_path $cmd" -a fleet -d 'Fleet scope'
end

complete -c manifest -n '__manifest_token_count 2; and __manifest_path config' -a 'show list get set unset describe doctor setup time'
complete -c manifest -n '__manifest_token_count 2; and __manifest_path recipe' -a 'list show explain help'
complete -c manifest -n '__manifest_token_count 2; and __manifest_path pr'     -a 'create status checks ready merge update queue policy fleet help'
complete -c manifest -n '__manifest_token_count 2; and __manifest_path uninstall' -a '-y --yes --dry-run --force --help'
complete -c manifest -n '__manifest_token_count 2; and __manifest_path reinstall' -a '-y --yes --dry-run --help'

# --- third-token arguments (token 3) -----------------------------------------

complete -c manifest -n '__manifest_path init fleet' \
    -a '-y --yes --depth --all-folders --force --dry-run --name --create-repo-private --create-repo-public --help'
complete -c manifest -n '__manifest_path ship repo' \
    -a 'patch minor major revision -y --yes --local --dry-run --explain -i --interactive --only --except --noprep'
complete -c manifest -n '__manifest_path ship fleet' \
    -a 'patch minor major revision -y --yes --local --dry-run --explain -i --interactive --only --except --noprep'
complete -c manifest -n '__manifest_path plan fleet' \
    -a '--apply --do --dry-run --depth --safety-cap --plan --name --force --help'
complete -c manifest -n '__manifest_path reconcile fleet' \
    -a '--apply --do --dry-run --plan --commit --push --force --adopt-submodules --help'
complete -c manifest -n '__manifest_path pr create' \
    -a '-y --yes --dry-run --draft --title --body --base --labels --reviewers --help'
for sub in ready merge update queue
    complete -c manifest -n "__manifest_path pr $sub" \
        -a '-y --yes --dry-run --method --force --auto --squash --merge --rebase --help'
end
complete -c manifest -n '__manifest_path pr fleet' \
    -a 'create status checks ready queue help -y --yes --dry-run --method --force --help'

# Config keys for the value-taking config subcommands.
for sub in get describe unset set
    complete -c manifest -n "__manifest_path config $sub" -a '(__manifest_keys)'
end
complete -c manifest -n '__manifest_path config set'  -a '--layer'
complete -c manifest -n '__manifest_path config list' -a '--layer'

# --layer value completion, regardless of position.
complete -c manifest -n 'string match -q -- "--layer" (commandline -opc)[-1]' -a 'global project local'
