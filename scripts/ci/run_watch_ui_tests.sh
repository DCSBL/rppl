#!/usr/bin/env bash
# Runs RpplWatchUITests on a booted Watch simulator. When a run fails (the app launch can hang or fail
# outright, LKLR-80 / #498) the simulator is rebooted and the whole suite runs once more; only a full green
# run counts as a pass. The failed attempt stays in "<log>.attempt1" and a warning is annotated.
#
# Usage: run_watch_ui_tests.sh UDID RESULT.xcresult LOG
set -uo pipefail
udid="$1" result="$2" log="$3"
attempts="${WATCH_UI_ATTEMPTS:-2}"

for attempt in $(seq 1 "$attempts"); do
  rm -rf "$result"
  if xcodebuild test \
    -project Rppl.xcodeproj \
    -scheme RpplWatch \
    -destination "platform=watchOS Simulator,id=${udid}" \
    -only-testing:RpplWatchUITests \
    -retry-tests-on-failure \
    -test-iterations 2 \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 240 \
    -resultBundlePath "$result" \
    CODE_SIGNING_ALLOWED=NO \
    COMPILER_INDEX_STORE_ENABLE=NO \
    2>&1 | tee "$log"; then
    exit 0
  fi
  if [ "$attempt" -lt "$attempts" ]; then
    echo "::warning::Watch UI tests failed on attempt ${attempt}; rebooting the simulator and running again"
    mv "$log" "${log}.attempt${attempt}"
    xcrun simctl shutdown "$udid" || true
    xcrun simctl boot "$udid" || true
    xcrun simctl bootstatus "$udid" -b
  fi
done
exit 1
