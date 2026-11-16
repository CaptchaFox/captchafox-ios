# The tests run on the simulator device that scripts/simulator.sh names, created for them when absent;
# SIMULATOR=<udid> chooses another.
ifndef SIMULATOR
SIMULATOR := $(shell scripts/simulator.sh)
endif
# The tests run in the app TestHost, one at a time: web views that start together on a new simulator device can stall
# WebKit.
XCODEBUILD = xcodebuild -project Tests/TestHost.xcodeproj -scheme TestHost -destination 'platform=iOS Simulator,id=$(SIMULATOR)' -parallel-testing-enabled NO

.PHONY: test test-live example

test:
	$(XCODEBUILD) test -skip-testing:LiveTests

test-live:
	$(XCODEBUILD) test -only-testing:LiveTests

example:
	xcodebuild -project Example/CaptchaFoxExample.xcodeproj -scheme CaptchaFoxExample -destination 'generic/platform=iOS Simulator' build
