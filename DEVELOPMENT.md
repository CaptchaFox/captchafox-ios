# Development

## Requirements

Xcode with an iOS Simulator runtime, and `jq`. CI uses the Xcode that `DEVELOPER_DIR` in `.github/workflows/ci.yml`
names. The package has no dependencies.

## Build

`make example` builds the example app in `Example/` for the iOS Simulator; CI builds it for every push to `main` and
every pull request. To run it, open `Example/CaptchaFoxExample.xcodeproj` in Xcode, choose a simulator and run.

## Test

| Command | Runs |
|---|---|
| `make test` | The tests on an iOS Simulator, with a fake of the widget's script in place of cdn.captchafox.com, and the test that uses the public interface as an app does. Needs no network. CI runs it for every push to `main` and every pull request. |
| `make test-live` | The tests against the widget of cdn.captchafox.com with the public test site keys. Needs the network. |

Both run on the simulator device `CaptchaFox SDK Tests`, which `scripts/simulator.sh` creates when it is absent (an
iPhone on the newest available iOS runtime), or on the one that `SIMULATOR=<udid>` names. On the first boot of a new
device, WebKit's processes take more than a minute to launch, and the tests wait up to three minutes for a page.
