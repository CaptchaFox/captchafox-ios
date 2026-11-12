# The tests run on the simulator device that scripts/simulator.sh names, created for them when absent;
# SIMULATOR=<udid> chooses another.
ifndef SIMULATOR
SIMULATOR := $(shell scripts/simulator.sh)
endif
# The tests build for the package's deployment target, as CI's Xcode does; a newer Xcode raises it for test targets.
# They run one at a time: web views that start together on a new simulator device can stall WebKit.
XCODEBUILD = xcodebuild -scheme CaptchaFox -destination 'platform=iOS Simulator,id=$(SIMULATOR)' IPHONEOS_DEPLOYMENT_TARGET=15.0 -parallel-testing-enabled NO

.PHONY: test test-live example

test:
	$(XCODEBUILD) test -skip-testing:LiveTests

test-live:
	$(XCODEBUILD) test -only-testing:LiveTests

example:
	xcodebuild -project Example/CaptchaFoxExample.xcodeproj -scheme CaptchaFoxExample -destination 'generic/platform=iOS Simulator' build
