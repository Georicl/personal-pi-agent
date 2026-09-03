#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bridge="$repo_root/Resources/pi-package-bridge.mjs"
fixture="$repo_root/Tests/Fixtures/PiPackage"
loose_skill="$repo_root/Tests/Fixtures/LooseResources/skills/loose"
pi_executable="$(realpath "$(command -v pi)")"
node_executable="$(command -v node)"
test_root="$(mktemp -d)"
agent_dir="$test_root/agent"
project_dir="$test_root/project"

cleanup() {
  if [[ "$test_root" == /tmp/* || "$test_root" == /var/folders/* ]]; then
    find "$test_root" -depth -delete
  fi
}
trap cleanup EXIT

mkdir -p "$agent_dir" "$project_dir"

encode_source() {
  "$node_executable" -e 'process.stdout.write(Buffer.from(JSON.stringify({source: process.argv[1], scope: process.argv[2]})).toString("base64"))' "$1" "$2"
}

run_bridge() {
  PI_CODING_AGENT_DIR="$agent_dir" "$node_executable" "$bridge" "$1" "$pi_executable" "$project_dir" "${2:-}"
}

global_install="$(run_bridge install "$(encode_source "$fixture" user)")"
jq -e 'select(.type == "result" and .success == true)' <<<"$global_install" >/dev/null

global_snapshot="$(run_bridge list)"
global_source="$(jq -r '.packages[] | select(.scope == "user") | .source' <<<"$global_snapshot")"
jq -e --arg fixture "$fixture" --arg source "$global_source" '
  (.packages | any(.source == $source and .scope == "user" and .installedPath == $fixture))
  and ([.globalResources[].resourceType] | unique | length == 4)
  and ([.globalResources[] | select(.source == $source)] | length == 4)
' <<<"$global_snapshot" >/dev/null

inherited_resource="$(jq -c --arg source "$global_source" '.projectResources[] | select(.source == $source and .resourceType == "extensions")' <<<"$global_snapshot")"
project_unload_payload="$(RESOURCE_JSON="$inherited_resource" "$node_executable" -e 'process.stdout.write(Buffer.from(JSON.stringify({scope:"project", desiredState:"unload", resource:JSON.parse(process.env.RESOURCE_JSON)})).toString("base64"))')"
project_unload_result="$(run_bridge set_resource "$project_unload_payload")"
jq -e 'select(.type == "result" and .success == true)' <<<"$project_unload_result" >/dev/null

project_override_snapshot="$(run_bridge list)"
jq -e --arg path "$(jq -r '.path' <<<"$inherited_resource")" '
  ([.projectResources[] | select(.path == $path and .sourceScope == "project" and .resourceType == "extensions" and .enabled == false and .overrideState == "unload")] | length == 1)
  and (.packages | any(.scope == "project" and .filtered == true))
' <<<"$project_override_snapshot" >/dev/null

project_inherit_resource="$(jq -c --arg path "$(jq -r '.path' <<<"$inherited_resource")" '.projectResources[] | select(.path == $path and .resourceType == "extensions")' <<<"$project_override_snapshot")"
project_inherit_payload="$(RESOURCE_JSON="$project_inherit_resource" "$node_executable" -e 'process.stdout.write(Buffer.from(JSON.stringify({scope:"project", desiredState:"inherit", resource:JSON.parse(process.env.RESOURCE_JSON)})).toString("base64"))')"
project_inherit_result="$(run_bridge set_resource "$project_inherit_payload")"
jq -e 'select(.type == "result" and .success == true)' <<<"$project_inherit_result" >/dev/null

project_inherit_snapshot="$(run_bridge list)"
jq -e --arg source "$global_source" '
  ([.projectResources[] | select(.source == $source and .resourceType == "extensions" and .enabled == true and .overrideState == "inherit")] | length == 1)
  and ([.packages[] | select(.scope == "project")] | length == 0)
' <<<"$project_inherit_snapshot" >/dev/null

theme_resource="$(jq -c --arg source "$global_source" '.globalResources[] | select(.source == $source and .resourceType == "themes")' <<<"$project_inherit_snapshot")"
toggle_payload="$(RESOURCE_JSON="$theme_resource" "$node_executable" -e 'process.stdout.write(Buffer.from(JSON.stringify({scope:"user", desiredState:"unload", resource:JSON.parse(process.env.RESOURCE_JSON)})).toString("base64"))')"
toggle_result="$(run_bridge set_resource "$toggle_payload")"
jq -e 'select(.type == "result" and .success == true)' <<<"$toggle_result" >/dev/null

paths_payload="$(LOOSE_SKILL="$loose_skill" $node_executable -e 'process.stdout.write(Buffer.from(JSON.stringify({scope:"user",paths:{extensions:[],skills:[process.env.LOOSE_SKILL],prompts:[],themes:["themes/custom/*.json"]}})).toString("base64"))')"
paths_result="$(run_bridge set_paths "$paths_payload")"
jq -e 'select(.type == "result" and .success == true)' <<<"$paths_result" >/dev/null

filtered_snapshot="$(run_bridge list)"
jq -e --arg source "$global_source" --arg loose_dir "$loose_skill" --arg loose "$loose_skill/SKILL.md" '
  ([.globalResources[] | select(.source == $source and .resourceType == "themes" and .enabled == false)] | length == 1)
  and (.globalConfiguredPaths.themes == ["themes/custom/*.json"])
  and (.globalConfiguredPaths.skills | any(. == $loose_dir))
  and ([.globalResources[] | select(.path == $loose and .origin == "top-level" and .enabled == true)] | length == 1)
  and (.packages | any(.source == $source and .scope == "user" and .filtered == true))
' <<<"$filtered_snapshot" >/dev/null

loose_resource="$(jq -c --arg loose "$loose_skill/SKILL.md" '.globalResources[] | select(.path == $loose and .origin == "top-level")' <<<"$filtered_snapshot")"
loose_unload_payload="$(RESOURCE_JSON="$loose_resource" "$node_executable" -e 'process.stdout.write(Buffer.from(JSON.stringify({scope:"user", desiredState:"unload", resource:JSON.parse(process.env.RESOURCE_JSON)})).toString("base64"))')"
loose_unload_result="$(run_bridge set_resource "$loose_unload_payload")"
jq -e 'select(.type == "result" and .success == true)' <<<"$loose_unload_result" >/dev/null

loose_unload_snapshot="$(run_bridge list)"
jq -e --arg loose "$loose_skill/SKILL.md" '
  ([.globalResources[] | select(.path == $loose and .origin == "top-level" and .enabled == false)] | length == 1)
' <<<"$loose_unload_snapshot" >/dev/null

project_loose_resource="$(jq -c --arg loose "$loose_skill/SKILL.md" '.projectResources[] | select(.path == $loose and .origin == "top-level")' <<<"$loose_unload_snapshot")"
project_loose_load_payload="$(RESOURCE_JSON="$project_loose_resource" "$node_executable" -e 'process.stdout.write(Buffer.from(JSON.stringify({scope:"project", desiredState:"load", resource:JSON.parse(process.env.RESOURCE_JSON)})).toString("base64"))')"
project_loose_load_result="$(run_bridge set_resource "$project_loose_load_payload")"
jq -e 'select(.type == "result" and .success == true)' <<<"$project_loose_load_result" >/dev/null

project_loose_load_snapshot="$(run_bridge list)"
jq -e --arg loose "$loose_skill/SKILL.md" '
  ([.projectResources[] | select(.path == $loose and .origin == "top-level" and .enabled == true and .overrideState == "load")] | length == 1)
' <<<"$project_loose_load_snapshot" >/dev/null

project_loose_loaded_resource="$(jq -c --arg loose "$loose_skill/SKILL.md" '.projectResources[] | select(.path == $loose and .origin == "top-level")' <<<"$project_loose_load_snapshot")"
project_loose_inherit_payload="$(RESOURCE_JSON="$project_loose_loaded_resource" "$node_executable" -e 'process.stdout.write(Buffer.from(JSON.stringify({scope:"project", desiredState:"inherit", resource:JSON.parse(process.env.RESOURCE_JSON)})).toString("base64"))')"
project_loose_inherit_result="$(run_bridge set_resource "$project_loose_inherit_payload")"
jq -e 'select(.type == "result" and .success == true)' <<<"$project_loose_inherit_result" >/dev/null

project_loose_inherit_snapshot="$(run_bridge list)"
jq -e --arg loose "$loose_skill/SKILL.md" '
  ([.projectResources[] | select(.path == $loose and .origin == "top-level" and .enabled == false and .overrideState == "inherit")] | length == 1)
  and (.projectConfiguredPaths.skills == [])
' <<<"$project_loose_inherit_snapshot" >/dev/null

global_remove="$(run_bridge remove "$(encode_source "$global_source" user)")"
jq -e 'select(.type == "result" and .success == true)' <<<"$global_remove" >/dev/null

project_install="$(run_bridge install "$(encode_source "$fixture" project)")"
jq -e 'select(.type == "result" and .success == true)' <<<"$project_install" >/dev/null

project_snapshot="$(run_bridge list)"
project_source="$(jq -r '.packages[] | select(.scope == "project") | .source' <<<"$project_snapshot")"
jq -e --arg fixture "$fixture" --arg source "$project_source" '
  (.packages | any(.source == $source and .scope == "project" and .installedPath == $fixture))
  and ([.projectResources[] | select(.source == $source and .sourceScope == "project")] | length == 4)
' <<<"$project_snapshot" >/dev/null

project_remove="$(run_bridge remove "$(encode_source "$project_source" project)")"
jq -e 'select(.type == "result" and .success == true)' <<<"$project_remove" >/dev/null

final_snapshot="$(run_bridge list)"
jq -e '(.packages | length == 0)' <<<"$final_snapshot" >/dev/null

printf 'Pi package bridge compatibility check passed.\n'
