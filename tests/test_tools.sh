#!/bin/bash
set -eo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../tools.sh
source "$repo_dir/tools.sh"

STATE_DIR=/
if prepare_state_dir; then exit 1; fi
STATE_DIR=/tmp/..
if prepare_state_dir; then exit 1; fi
STATE_DIR=/var/lib/
if prepare_state_dir; then exit 1; fi
STATE_DIR=/var/lib/server_tools

parse_selection A
[[ " ${PARSED_MODULES[*]} " == *" install_redis " ]]
[[ " ${PARSED_MODULES[*]} " != *" configure_firewall " ]]
[[ " ${PARSED_MODULES[*]} " != *" restore_redis_rdb " ]]
[[ " ${PARSED_MODULES[*]} " != *" configure_sysctl " ]]
[[ " ${PARSED_MODULES[*]} " != *" install_mysql_free " ]]
parse_selection 2
map_output="$(sort_modules_by_dependencies "${PARSED_MODULES[@]}")"
[[ "$map_output" == $'create_user\ninstall_build_tools' ]]
parse_selection 10
map_output="$(sort_modules_by_dependencies "${PARSED_MODULES[@]}")"
[[ "$map_output" == $'create_user\ninstall_build_tools\ninstall_node' ]]
parse_selection 6
map_output="$(sort_modules_by_dependencies "${PARSED_MODULES[@]}")"
[[ "$map_output" == $'create_user\ninstall_build_tools\nconfigure_ssh' ]]
parse_selection 13
map_output="$(sort_modules_by_dependencies "${PARSED_MODULES[@]}")"
[[ "$map_output" == $'create_user\ninstall_build_tools\ninstall_redis\nrestore_redis_rdb' ]]
if parse_selection cancel >/dev/null 2>&1; then exit 1; fi

old_state_dir="$STATE_DIR"
STATE_DIR=$(mktemp -d)
RUNS=(); RUN_RESULT=0; CURRENT=1; DRIFT_MODULE=
run_module() { RUNS+=("$1"); return "$RUN_RESULT"; }
module_is_current() {
    if [ -n "$DRIFT_MODULE" ] && [ "$DRIFT_MODULE" = "$1" ]; then DRIFT_MODULE=; return 1; fi
    [ "$CURRENT" = 1 ]
}

# The first full A execution records every success; a current second A runs nothing.
execute_modules base "${BASE_PROFILE[@]}" <<< y >/dev/null 2>&1
[[ "${RUNS[*]}" == "${BASE_PROFILE[*]}" ]]
for module in "${BASE_PROFILE[@]}"; do [ -f "$(marker_file "$module")" ]; done
first_run_count="${#RUNS[@]}"
execute_modules base "${BASE_PROFILE[@]}" <<< y >/dev/null 2>&1
[ "${#RUNS[@]}" -eq "$first_run_count" ]

# A stale actual state reruns and re-marks after the mocked module repairs it.
DRIFT_MODULE=install_build_tools
execute_modules base install_build_tools <<< y >/dev/null 2>&1
[ "${#RUNS[@]}" -eq "$((first_run_count + 1))" ] && [ -f "$(marker_file install_build_tools)" ]

# A failed run and a failed final check both clear the marker and fail the batch.
RUN_RESULT=1
DRIFT_MODULE=install_build_tools
if execute_modules base install_build_tools <<< y >/dev/null 2>&1; then exit 1; fi
[ ! -e "$(marker_file install_build_tools)" ]
RUN_RESULT=0; CURRENT=0
if execute_modules base install_build_tools <<< y >/dev/null 2>&1; then exit 1; fi
[ ! -e "$(marker_file install_build_tools)" ]

# A failed dependency prevents its downstream module from running.
CURRENT=1; RUN_RESULT=0; RUNS=()
run_module() { RUNS+=("$1"); [ "$1" != install_build_tools ]; }
if execute_modules base install_node <<< y >/dev/null 2>&1; then exit 1; fi
[[ " ${RUNS[*]} " == *" install_build_tools " ]]
[[ " ${RUNS[*]} " != *" install_node " ]]

# An explicit module cancellation is not a failure and never creates a marker.
RUNS=(); CURRENT=1
run_module() { RUNS+=("$1"); return 2; }
execute_modules manual configure_firewall <<< y >/dev/null 2>&1
[ "${#RUNS[@]}" -eq 1 ] && [ ! -e "$(marker_file configure_firewall)" ]

# Automatically added dependencies are skipped when current; the explicit module still runs.
RUNS=()
run_module() { RUNS+=("$1"); return 0; }
execute_modules manual install_node <<< y >/dev/null 2>&1
[[ "${RUNS[*]}" == install_node ]]

# A canceled prerequisite blocks its dependent even though cancellation itself is not a failure.
RUNS=()
module_is_current() { [ "$1" = create_user ] || [ "$1" = install_node ]; }
run_module() { RUNS+=("$1"); [ "$1" = install_build_tools ] && return 2; return 0; }
if execute_modules manual install_node <<< y >/dev/null 2>&1; then exit 1; fi
[[ " ${RUNS[*]} " == *" install_build_tools " ]]
[[ " ${RUNS[*]} " != *" install_node " ]]

rm -rf "$STATE_DIR"
STATE_DIR="$old_state_dir"
echo 'tools.sh selection, state and dependency tests passed'
