#!/usr/bin/env bash
# Build-related path filter for Xcode Cloud and local CI dry-runs.
# Keep in sync with .pre-commit-config.yaml xcode-gate files.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
fi

# Matches pre-push xcode-gate hook file patterns (no (?x) — bash [[ =~ ]] does not support it).
RPPL_BUILD_RELATED_PATH_REGEX='\.(swift|plist|entitlements|pbxproj|xcscheme|xcconfig|xcprivacy|storyboard|xib|metal|intentdefinition)$|Package\.(swift|resolved)$|\.xcassets/|scripts/git-hooks/xcode-gate\.sh$'

# Return 0 when any changed path is build-related; 1 otherwise.
# Reads paths from arguments, or from stdin when no arguments are given.
rppl_any_build_related_path() {
  local path

  if [[ "$#" -gt 0 ]]; then
    for path in "$@"; do
      [[ -z "$path" ]] && continue
      if [[ "$path" =~ $RPPL_BUILD_RELATED_PATH_REGEX ]]; then
        return 0
      fi
    done
    return 1
  fi

  while IFS= read -r path || [[ -n "$path" ]]; do
    [[ -z "$path" ]] && continue
    if [[ "$path" =~ $RPPL_BUILD_RELATED_PATH_REGEX ]]; then
      return 0
    fi
  done

  return 1
}
