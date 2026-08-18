# Minimal stand-in for the containers/automation common library, which this
# repo no longer installs (containers/automation_images was archived).
# Sourced, not executed.

# Derived from $0 and not exported; re-derived after each re-exec.
SCRIPT_PATH=$(realpath "$(dirname "$0")")
SCRIPT_FILENAME=$(basename "$0")
SCRIPT_FILEPATH="$SCRIPT_PATH/$SCRIPT_FILENAME"

CI="${CI:-false}"
[[ $CI == "false" ]] || CI='true'

A_DEBUG=${A_DEBUG:-0}
( test "$A_DEBUG" -eq 0 || test "$A_DEBUG" -ne 0 ) &>/dev/null || \
    A_DEBUG=1  # assume true when non-integer

DEBUG_MSG_PREFIX="${DEBUG_MSG_PREFIX:-DEBUG:}"
WARNING_MSG_PREFIX="${WARNING_MSG_PREFIX:-WARNING:}"
ERROR_MSG_PREFIX="${ERROR_MSG_PREFIX:-ERROR:}"

msg() {
    echo "${1:-No message specified}" >> /dev/stderr
}

# warn/die/dbg must not use msg(): aio/test.sh overrides it and would recurse.

_ctx() {
    echo "${BASH_SOURCE[3]:-<stdin>}:${BASH_LINENO[2]} in ${FUNCNAME[3]:-main}()"
}

_fmt_ctx() {
    local stars="************************************************"
    echo "$stars"
    echo "${1:-no prefix given}  ($(_ctx))"
    echo "$stars"
}

warn() {
    _fmt_ctx "$WARNING_MSG_PREFIX ${1:-no warning message given}" >> /dev/stderr
}

die() {
    _fmt_ctx "$ERROR_MSG_PREFIX ${1:-no error message given}" >> /dev/stderr
    local exit_code=${2:-1}
    ((exit_code==0)) || \
        exit $exit_code
}

dbg() {
    if ((A_DEBUG)); then
        (
        echo
        echo "$DEBUG_MSG_PREFIX ${1:-No debugging message given}" \
             "(${BASH_SOURCE[1]:-<stdin>}:${BASH_LINENO[0]} in ${FUNCNAME[1]:-main}())"
        ) >> /dev/stderr
    fi
}

showrun() {
    local -a context
    # shellcheck disable=SC2207
    context=($(caller 0))
    echo "+ $*  # ${context[2]}:${context[0]} in ${context[1]}()" >> /dev/stderr
    "$@"
}

req_env_vars() {
    dbg "Confirming non-empty vars for $*"
    local var_name var_value
    for var_name in "$@"; do
        var_value=$(tr -d '[:space:]' <<<"${!var_name}")
        ((${#var_value}>0)) || \
            die "Environment variable '$var_name' is required by ${BASH_SOURCE[1]}:${FUNCNAME[1]:-main}() but empty or entirely white-space."
    done
}
