# Bash completion for Manifest CLI
# Source from ~/.bashrc:  source /path/to/completions/manifest.bash
# Or symlink into bash-completion's completion dir (e.g. /opt/homebrew/etc/bash_completion.d/).

_manifest_complete() {
    local cur prev words cword
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    cword=$COMP_CWORD
    words=("${COMP_WORDS[@]}")

    # Top-level commands shown in `manifest --help`
    local top_cmds="config init status prep refresh ship pr doctor security upgrade uninstall version help"
    local scopes="repo fleet"
    local bumps="patch minor major revision"
    local config_subs="show list get set unset describe doctor setup time"
    local pr_subs="create status checks ready merge update queue policy help"
    local layers="global project local"

    case $cword in
        1)
            COMPREPLY=( $(compgen -W "$top_cmds" -- "$cur") )
            return 0
            ;;
        2)
            case "${words[1]}" in
                init|prep|refresh|ship)
                    COMPREPLY=( $(compgen -W "$scopes" -- "$cur") )
                    return 0
                    ;;
                config)
                    COMPREPLY=( $(compgen -W "$config_subs" -- "$cur") )
                    return 0
                    ;;
                pr)
                    COMPREPLY=( $(compgen -W "$pr_subs" -- "$cur") )
                    return 0
                    ;;
            esac
            ;;
        3)
            case "${words[1]} ${words[2]}" in
                "ship repo"|"ship fleet")
                    COMPREPLY=( $(compgen -W "$bumps --local --dry-run -i --interactive" -- "$cur") )
                    return 0
                    ;;
                "config get"|"config describe"|"config unset")
                    COMPREPLY=( $(compgen -W "$(_manifest_complete_keys)" -- "$cur") )
                    return 0
                    ;;
                "config set")
                    if [[ "$cur" == --* ]]; then
                        COMPREPLY=( $(compgen -W "--layer" -- "$cur") )
                    else
                        COMPREPLY=( $(compgen -W "$(_manifest_complete_keys)" -- "$cur") )
                    fi
                    return 0
                    ;;
                "config list")
                    COMPREPLY=( $(compgen -W "--layer" -- "$cur") )
                    return 0
                    ;;
            esac
            ;;
    esac

    # --layer <value> handling regardless of position
    if [[ "$prev" == "--layer" ]]; then
        COMPREPLY=( $(compgen -W "$layers" -- "$cur") )
        return 0
    fi
    if [[ "$cur" == --* ]]; then
        COMPREPLY=( $(compgen -W "--help --local --dry-run --layer --fix --json" -- "$cur") )
        return 0
    fi
}

# Cached key lookup (refreshes once per shell session by default).
_manifest_complete_keys() {
    if [[ -z "${_MANIFEST_BASH_KEYS_CACHE:-}" ]]; then
        _MANIFEST_BASH_KEYS_CACHE="$(manifest config list 2>/dev/null | awk 'NR>2 && $1!="" {print $1}' | sort -u | tr '\n' ' ')"
    fi
    printf '%s' "$_MANIFEST_BASH_KEYS_CACHE"
}

complete -F _manifest_complete manifest
