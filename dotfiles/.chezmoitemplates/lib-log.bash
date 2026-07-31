{{/*
Makes lib/log.sh available to a chezmoi provisioning script.

chezmoi copies run_ scripts to a temporary file before executing them, so
${BASH_SOURCE[0]} points into /tmp and the usual "locate the repo from my own
path" trick cannot find the library. The content is therefore embedded here at
render time, straight from lib/log.sh, so there is still exactly one definition
of the helpers in the repository.

It is written to a temporary file and sourced rather than pasted inline on
purpose: lib/log.sh refuses to run when executed instead of sourced, and pasting
it inline would make that guard fire on the run script itself.
*/ -}}
_log_lib="$(mktemp)"
# Single EXIT trap for the whole script: a caller that needs its own temporary
# files appends them here instead of installing a second trap, which would
# silently replace this one.
_cleanup_paths=("$_log_lib")
trap 'rm -rf "${_cleanup_paths[@]}"' EXIT
cat >"$_log_lib" <<'CHEZMOI_EMBEDDED_LOG_SH'
{{ include (joinPath .chezmoi.sourceDir ".." "lib" "log.sh") }}
CHEZMOI_EMBEDDED_LOG_SH
# shellcheck source=/dev/null
source "$_log_lib"
