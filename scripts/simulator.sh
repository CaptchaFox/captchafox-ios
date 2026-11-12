#!/bin/sh
# Prints the UDID of the simulator device "CaptchaFox SDK Tests" that the tests run on, so that they never use another
# device. Creates it when absent: an iPhone on the newest available iOS runtime.
set -eu

name="CaptchaFox SDK Tests"

udid="$(xcrun simctl list -j devices available | jq -r --arg name "$name" '[.devices[][] | select(.name == $name)][0].udid // empty')"
if [ -n "$udid" ]; then
  echo "$udid"
  exit 0
fi

# Of runtimes with the same version, the general one supports more device types than one made for a single device.
runtime="$(xcrun simctl list -j runtimes available | jq -c '[.runtimes[] | select(.platform == "iOS")] | sort_by([(.version | split(".") | map(tonumber)), (.supportedDeviceTypes | length)]) | last')"
if [ "$runtime" = "null" ]; then
  echo "No iOS Simulator runtime is available; install one in Xcode." >&2
  exit 1
fi
devicetype="$(printf '%s' "$runtime" | jq -r '[.supportedDeviceTypes[] | select(.productFamily == "iPhone")][0].identifier')"
xcrun simctl create "$name" "$devicetype" "$(printf '%s' "$runtime" | jq -r .identifier)"
