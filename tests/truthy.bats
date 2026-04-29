#!/usr/bin/env bats

# Coverage for is_truthy / is_falsy / normalize_enum_value.
#
# These helpers are the canonical answer for forgiving config-value
# matching across YAML and MANIFEST_CLI_* env vars.  Without them, every
# dispatch site reinvents (often inconsistently) whitespace and case
# tolerance.  Tests below lock in the grammar:
#   - is_truthy : 1 | true | yes | on   (case-insensitive, whitespace-tolerant)
#   - is_falsy  : 0 | false | no | off | empty
#   - normalize_enum_value : trim + lowercase

load 'helpers/setup'

setup() {
    load_modules
}

# -----------------------------------------------------------------------------
# is_truthy
# -----------------------------------------------------------------------------

@test "is_truthy: accepts canonical 1|true|yes|on" {
    is_truthy "1"
    is_truthy "true"
    is_truthy "yes"
    is_truthy "on"
}

@test "is_truthy: case-insensitive — TRUE, True, YES, On all accepted" {
    is_truthy "TRUE"
    is_truthy "True"
    is_truthy "YES"
    is_truthy "Yes"
    is_truthy "On"
    is_truthy "ON"
}

@test "is_truthy: tolerates surrounding whitespace" {
    is_truthy " true "
    is_truthy "	yes	"   # tabs
    is_truthy "  1  "
}

@test "is_truthy: combined whitespace + case" {
    is_truthy "  TRUE  "
    is_truthy "	Yes "
}

@test "is_truthy: rejects empty string" {
    ! is_truthy ""
}

@test "is_truthy: rejects falsy tokens" {
    ! is_truthy "0"
    ! is_truthy "false"
    ! is_truthy "no"
    ! is_truthy "off"
    ! is_truthy "FALSE"
}

@test "is_truthy: rejects garbage" {
    ! is_truthy "garbage"
    ! is_truthy "tru"
    ! is_truthy "ye s"  # internal whitespace not collapsed
    ! is_truthy "2"
}

@test "is_truthy: missing arg is treated as empty (falsy)" {
    ! is_truthy
}

# -----------------------------------------------------------------------------
# is_falsy
# -----------------------------------------------------------------------------

@test "is_falsy: accepts canonical 0|false|no|off" {
    is_falsy "0"
    is_falsy "false"
    is_falsy "no"
    is_falsy "off"
}

@test "is_falsy: empty string is falsy" {
    is_falsy ""
}

@test "is_falsy: case-insensitive and whitespace-tolerant" {
    is_falsy "FALSE"
    is_falsy " No "
    is_falsy "  OFF  "
}

@test "is_falsy: rejects truthy tokens" {
    ! is_falsy "1"
    ! is_falsy "true"
    ! is_falsy "yes"
    ! is_falsy "on"
}

@test "is_falsy: rejects garbage (not strict inverse of is_truthy)" {
    # A garbage value is neither truthy nor falsy — callers decide.
    ! is_falsy "garbage"
    ! is_falsy "maybe"
}

# -----------------------------------------------------------------------------
# normalize_enum_value
# -----------------------------------------------------------------------------

@test "normalize_enum_value: trims and lowercases" {
    [ "$(normalize_enum_value "  Release_Head  ")" = "release_head" ]
    [ "$(normalize_enum_value "VERSION_COMMIT")" = "version_commit" ]
    [ "$(normalize_enum_value "	Patch ")" = "patch" ]
}

@test "normalize_enum_value: preserves internal whitespace" {
    # Only edges are trimmed; internal whitespace stays intact so values that
    # legitimately contain spaces (rare for enums, common for free-text) are
    # not corrupted.
    [ "$(normalize_enum_value "  hello world  ")" = "hello world" ]
}

@test "normalize_enum_value: empty in, empty out" {
    [ "$(normalize_enum_value "")" = "" ]
    [ "$(normalize_enum_value "   ")" = "" ]
}
