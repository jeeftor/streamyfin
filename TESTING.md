# Testing

This project has three practical testing layers:

- Static and unit checks for TypeScript, Biome, and Bun tests.
- A local Jellyfin fixture for repeatable media/API state.
- Maestro UI flows that drive the app against that fixture.

The Maestro/Jellyfin harness is primarily meant for validating login, custom headers, media discovery, and basic playback paths without depending on a personal Jellyfin server.

## Prerequisites

Install the normal project dependencies, reload submodules, and install Maestro:

```bash
make install-dependencies
```

For fixture and UI tests you also need:

- Docker with Compose support.
- Android Studio/ADB for Android emulator or device testing.
- Xcode command line tools for iOS simulator testing.
- Maestro CLI. `make install-dependencies` installs it if `~/.maestro/bin/maestro` is missing.
- `ffmpeg` for downloading/transcoding fixture media.

If you only need to install Maestro without reinstalling project dependencies, use:

```bash
make e2e-setup
```

The Makefile automatically adds `~/.maestro/bin` to `PATH` for its targets. If you run scripts directly, make sure `maestro` is on your shell `PATH`.

## Platform Support

The current harness supports Maestro flows on:

| Platform | Status | Notes |
| --- | --- | --- |
| Android phone emulator/device | Supported | Primary path used by GitHub Actions. |
| iOS simulator | Supported locally | Requires Xcode and a booted simulator. |
| Physical Android device | Supported locally | Use `MAESTRO_TARGET=device` when the device must reach the host over LAN. |
| Physical iOS device | Not covered | Maestro's normal local iOS path is simulator-oriented. |
| Android TV | Supported experimentally | Use `run-android-tv`, `install-android-tv`, `test-login-android-tv`, and `test-play-steamboat-android-tv` with a TV emulator/device. |
| Apple TV/tvOS | Blocked by Maestro support | tvOS Maestro automation is not covered by this harness. Upstream Maestro tvOS support is being tracked in mobile-dev-inc/Maestro#3021. |

Android TV Cloudflare and recording targets are still placeholders until those flows are implemented. The Apple TV/tvOS limitation applies only to tvOS automation, not Android TV.

## Repo Checks

Run the narrow checks before pushing test harness changes:

```bash
bun run typecheck
bun run test:unit
bun run check
```

Useful optional checks:

```bash
bun run doctor
git diff --check
```

## Makefile Target Map

Run `make help` for the current target list. The important target groups are:

| Group | Targets | Purpose |
| --- | --- | --- |
| Setup | `install-dependencies`, `e2e-setup`, `clean-artifacts`, `media-list` | Install project/Maestro dependencies, clear local test output, inspect generated media. |
| App build/install | `install-android`, `install-android-tv`, `install-ios`, `run-android`, `run-android-tv`, `run-ios` | Build/install or run the app for UI tests. |
| Jellyfin fixture | `jellyfin-download-media`, `jellyfin-up`, `jellyfin-api-test`, `jellyfin-down` | Prepare media, start the fixture, verify API access, and stop the fixture. |
| Fixture maintenance | `jellyfin-up-clean`, `jellyfin-reset`, `jellyfin-save-config`, `jellyfin-clean-media` | Rebuild or snapshot fixture config/media. |
| Fixture routing | `jellyfin-configure-urls`, `jellyfin-configure-maestro-ids`, `jellyfin-scan-library` | Write reachable URLs and deterministic media IDs into the Maestro env file. |
| Android flows | `test-login-android`, `test-cf-android`, `test-play-steamboat-android` | Run Android simple login, custom-header login, and playback smoke flows. |
| Android TV flows | `test-login-android-tv`, `test-play-steamboat-android-tv` | Run Android TV simple login and playback smoke flows. |
| iOS flows | `test-login-ios`, `test-cf-ios`, `test-play-steamboat-ios` | Run iOS simulator simple login, custom-header login, and playback smoke flows. |
| Recording | `record-simple-*`, `record-cf-*`, `test-android-record`, `test-ios-record` | Capture videos with Maestro, ADB, or `simctl`. |
| Legacy | `e2e` | Starts a Maestro Android device and runs `login.yaml` if present. |

Prefer root Makefile targets over invoking scripts directly. They pass the shared `ENV_FILE`, `MAESTRO_APP_ID`, `MAESTRO_PLATFORM`, and `MAESTRO_TARGET` values consistently.

Android TV install/run targets default to the `Television_1080p` AVD. Override that with `ANDROID_TV_DEVICE=<avd-name-or-emulator-serial>` when needed; the runner resolves emulator serials back to AVD names before invoking Expo.

## Maestro Environment

Maestro flows read values from shell environment variables or an env file. The default env file is:

```text
tests/maestro/.env.local
```

That file is ignored by Git. Start from the example:

```bash
cp tests/maestro/.env.example tests/maestro/.env.local
```

For the local Jellyfin fixture, use:

```dotenv
MAESTRO_APP_ID=com.fredrikburmester.streamyfin
MAESTRO_USERNAME=admin
MAESTRO_PASSWORD=admin
```

You usually do not need to set `MAESTRO_SERVER_URL` manually for the fixture. `make jellyfin-up` detects the best URL for the selected target and writes it into the env file.

For Cloudflare/custom-header flows, also set:

```dotenv
MAESTRO_CF_ACCESS_CLIENT_ID=example-client-id
MAESTRO_CF_ACCESS_CLIENT_SECRET=example-client-secret
```

Do not commit real secrets or personal server credentials.

The runners intentionally allow shell variables to override env-file values. This is useful for one-off runs:

```bash
MAESTRO_USERNAME=admin MAESTRO_PASSWORD=admin make test-login-android
```

Supported env variables include:

| Variable | Required for | Purpose |
| --- | --- | --- |
| `MAESTRO_APP_ID` | all flows | Native app ID under test. Defaults to `com.fredrikburmester.streamyfin` in scripts/Makefile. |
| `MAESTRO_SERVER_URL` | all flows | Jellyfin URL the device can reach. Usually written by `make jellyfin-up`. |
| `MAESTRO_USERNAME` | all login/playback flows | Jellyfin username. The fixture default is `admin`. |
| `MAESTRO_PASSWORD` | optional for simple flows | Jellyfin password. The fixture default is `admin`; blank passwords are allowed by the runner. |
| `MAESTRO_CF_ACCESS_CLIENT_ID` | custom-header flows | Cloudflare Access client ID header value. |
| `MAESTRO_CF_ACCESS_CLIENT_SECRET` | custom-header flows | Cloudflare Access client secret header value. |
| `MAESTRO_PLATFORM` | direct script runs | Maestro platform: `android` or `ios`. Make targets set this. |
| `MAESTRO_TARGET` | fixture URL routing | URL target: `android`, `ios`, or `device`. |
| `MAESTRO_DEVICE` | multi-device setups | Emulator/simulator/device ID passed to `maestro --device`. |
| `MAESTRO_CLEAR_CLIPBOARD` | optional | Set to `0` to skip best-effort clipboard clearing. |
| `MAESTRO_MOVIES_LIBRARY_ID` | playback flows | Movies library test ID, generated by `make jellyfin-configure-maestro-ids`. |
| `MAESTRO_STEAMBOAT_WILLIE_ID` | playback flows | Fixture movie test ID, generated by `make jellyfin-configure-maestro-ids`. |

### Target Selection

The root Makefile sets sensible defaults:

| Target | Default URL behavior |
| --- | --- |
| Android emulator | `MAESTRO_TARGET=android`, usually `http://10.0.2.2:8096` |
| iOS simulator | `MAESTRO_TARGET=ios`, usually `http://localhost:8096` |
| Physical device | `MAESTRO_TARGET=device`, uses the host LAN IP |

Override the env file or target when needed:

```bash
make jellyfin-up ENV_FILE=tests/maestro/.env.local MAESTRO_TARGET=ios
make test-login-ios ENV_FILE=tests/maestro/.env.local
```

If you have multiple simulators or emulators connected, pass the device ID:

```bash
MAESTRO_DEVICE=<device-id> make test-login-android
```

Use separate env files if you switch between local fixture, personal server, and protected-server flows:

```bash
cp tests/maestro/.env.example tests/maestro/.env.local
cp tests/maestro/.env.example tests/maestro/.env.cloudflare.local

make jellyfin-up ENV_FILE=tests/maestro/.env.local
ENV_FILE=tests/maestro/.env.cloudflare.local make test-cf-android
```

## Testing Against Your Own Jellyfin Server

You do not have to use the bundled Docker fixture for simple login or custom-header flows. You can point Maestro at any Jellyfin server that the emulator, simulator, or device can reach.

Use this path when you want to test against:

- an existing Jellyfin server on your development machine
- a Jellyfin server on another LAN machine
- a personal remote Jellyfin server
- a Jellyfin server behind Cloudflare Access/custom headers

Create a separate env file so fixture runs do not overwrite your personal server settings:

```bash
cp tests/maestro/.env.example tests/maestro/.env.local-server
```

Then edit `tests/maestro/.env.local-server`:

```dotenv
MAESTRO_APP_ID=com.fredrikburmester.streamyfin
MAESTRO_SERVER_URL=http://10.0.2.2:8096
MAESTRO_USERNAME=your-jellyfin-user
MAESTRO_PASSWORD=your-jellyfin-password
```

Choose `MAESTRO_SERVER_URL` from the device's point of view:

| Jellyfin location | Android emulator URL | iOS simulator URL | Physical device URL |
| --- | --- | --- | --- |
| Same dev machine | `http://10.0.2.2:8096` | `http://localhost:8096` | `http://<host-lan-ip>:8096` |
| Another LAN machine | `http://<server-lan-ip>:8096` | `http://<server-lan-ip>:8096` | `http://<server-lan-ip>:8096` |
| Remote HTTPS server | `https://jellyfin.example.com` | `https://jellyfin.example.com` | `https://jellyfin.example.com` |

Do not run `make jellyfin-up` for this env file. That target is for the bundled fixture and rewrites `MAESTRO_SERVER_URL` for the selected fixture target.

Run Android against your own server:

```bash
make install-android
ENV_FILE=tests/maestro/.env.local-server make test-login-android
```

Run iOS simulator against your own server:

```bash
make install-ios
ENV_FILE=tests/maestro/.env.local-server make test-login-ios
```

For a physical Android device on the same network as your Jellyfin server:

```dotenv
MAESTRO_SERVER_URL=http://192.168.1.25:8096
```

```bash
MAESTRO_DEVICE=<adb-device-id> MAESTRO_TARGET=device ENV_FILE=tests/maestro/.env.local-server make test-login-android
```

For Cloudflare Access/custom-header testing, use a separate env file and include the Access client credentials:

```dotenv
MAESTRO_APP_ID=com.fredrikburmester.streamyfin
MAESTRO_SERVER_URL=https://jellyfin.example.com
MAESTRO_USERNAME=your-jellyfin-user
MAESTRO_PASSWORD=your-jellyfin-password
MAESTRO_CF_ACCESS_CLIENT_ID=your-access-client-id
MAESTRO_CF_ACCESS_CLIENT_SECRET=your-access-client-secret
```

```bash
ENV_FILE=tests/maestro/.env.cloudflare.local make test-cf-android
ENV_FILE=tests/maestro/.env.cloudflare.local make test-cf-ios
```

The playback smoke flows are fixture-oriented. They expect selector values such as `MAESTRO_STEAMBOAT_WILLIE_ID`, which are normally discovered from the bundled fixture media. For a personal server, use the simple login or custom-header flows unless your server has matching media and you provide the required selector IDs in the env file.

## Jellyfin Fixture

The fixture lives under:

```text
tests/fixtures/jellyfin
```

It provides a small deterministic media set with movies, shows, and music. The saved Jellyfin config uses:

```text
Username: admin
Password: admin
```

Jellyfin itself runs the same way for Android and Apple platforms: Docker exposes port `8096` on the host. The difference is the URL each simulator/device must use to reach that host:

| Test target | Device view of host Jellyfin |
| --- | --- |
| Android emulator | `http://10.0.2.2:8096` |
| iOS simulator | `http://localhost:8096` |
| Physical Android/iOS device | `http://<host-lan-ip>:8096` |

`tests/fixtures/jellyfin/scripts/detect-access-urls.sh` owns that mapping. The `jellyfin-up` and `jellyfin-configure-urls` targets call it and write the selected value to `MAESTRO_SERVER_URL`.

Prepare media and start the fixture:

```bash
make jellyfin-download-media
make jellyfin-up
make jellyfin-api-test
```

`make jellyfin-up` does the following:

- Starts Docker Compose from `tests/fixtures/jellyfin/docker-compose.yml`.
- Copies the saved `base_config` into runtime config.
- Waits for Jellyfin to respond.
- Detects the correct URL for Maestro.
- Writes `MAESTRO_SERVER_URL` into the selected env file.
- Triggers a Jellyfin library scan.

For Android emulator testing, the default is enough:

```bash
make jellyfin-up
```

For iOS simulator testing, select the iOS target so the env file gets `localhost`:

```bash
make jellyfin-up MAESTRO_TARGET=ios
```

For physical devices, select the device target and provide the host IP if auto-detection is wrong:

```bash
make jellyfin-up MAESTRO_TARGET=device JELLYFIN_HOST_IP=192.168.1.25
```

If the fixture is already running and you only need to rewrite `MAESTRO_SERVER_URL`, run:

```bash
make jellyfin-configure-urls MAESTRO_TARGET=android
make jellyfin-configure-urls MAESTRO_TARGET=ios
make jellyfin-configure-urls MAESTRO_TARGET=device JELLYFIN_HOST_IP=192.168.1.25
```

Stop and clean up the fixture:

```bash
make jellyfin-down
```

Inspect the fixture:

```bash
make jellyfin-status
make jellyfin-logs
make media-list
```

Refresh media selectors for direct script runs or after changing fixture media/config:

```bash
make jellyfin-configure-maestro-ids
```

This writes IDs such as `MAESTRO_STEAMBOAT_WILLIE_ID` into the Maestro env file.

The root playback targets call this automatically before running Maestro. Simple login and custom-header login flows do not need media IDs.

## Android Maestro Flow

Start an Android emulator first. The full local Android path is:

```bash
cp tests/maestro/.env.example tests/maestro/.env.local
make jellyfin-download-media
make jellyfin-up
make jellyfin-api-test
make install-android
make test-login-android
```

`make install-android` checks whether the native project is a phone prebuild and runs `bun run android:ui-test`, which installs the release variant:

```bash
make install-android
```

Run the simple login flow:

```bash
make test-login-android
```

Run the custom-header login flow:

```bash
make test-cf-android
```

Run the authenticated playback smoke flow:

```bash
make test-play-steamboat-android
```

Run against a physical Android device:

```bash
make jellyfin-up MAESTRO_TARGET=device JELLYFIN_HOST_IP=192.168.1.25
MAESTRO_DEVICE=<adb-device-id> MAESTRO_TARGET=device make test-login-android
```

Artifacts are written under:

```text
tests/maestro/artifacts/<timestamp>-<flow-name>/
```

Clean local screenshots and recordings:

```bash
make clean-artifacts
```

## iOS Maestro Flow

Start an iOS simulator first. The full local iOS simulator path is:

```bash
cp tests/maestro/.env.example tests/maestro/.env.local
make jellyfin-download-media
make jellyfin-up MAESTRO_TARGET=ios
make jellyfin-api-test
make install-ios
make test-login-ios
```

`make install-ios` checks whether the native project is a phone prebuild and runs `bun run ios:ui-test`:

```bash
make install-ios
```

Start the fixture for iOS URL routing and run the flow:

```bash
make jellyfin-up MAESTRO_TARGET=ios
make test-login-ios
```

Run the custom-header flow:

```bash
make test-cf-ios
```

Run the playback smoke flow:

```bash
make test-play-steamboat-ios
```

If multiple simulators are booted, pass the simulator UDID:

```bash
MAESTRO_DEVICE=<simulator-udid> make test-login-ios
```

Do not use Apple TV/tvOS simulators for these flows yet. Android TV flows use Android emulators or devices; tvOS automation remains unsupported until Maestro tvOS support lands.

## Recording Flows

Maestro and platform recorders are available for manual evidence capture.

Android examples:

```bash
make record-simple-maestro-android
make record-simple-adb-android
make record-cf-simple-maestro-android
make record-cf-simple-adb-android
```

iOS examples:

```bash
make record-simple-maestro-ios
make record-simple-simulator-ios
make record-cf-simple-maestro-ios
make record-cf-simple-simulator-ios
```

Recordings are saved under `tests/maestro/artifacts/`.

## GitHub Actions

The `Maestro Simple Login` workflow currently runs the Android simple-login path:

1. Downloads/prepares fixture media.
2. Builds an Android release APK.
3. Starts the Jellyfin fixture.
4. Runs the Android Maestro simple-login flow in an emulator.
5. Uploads Maestro screenshots and the Gradle build log.

The workflow does not yet exercise iOS, tvOS, Android TV, Cloudflare/custom-header, or playback flows in GitHub Actions.

Successful run artifacts should include:

```text
gradle-assemble-release.log
<timestamp>-simple/01-launched.png
<timestamp>-simple/02-server-url-entered.png
<timestamp>-simple/03-login-screen.png
<timestamp>-simple/04-credentials-entered.png
<timestamp>-simple/05-intro-screen.png
<timestamp>-simple/06-home.png
```

## Troubleshooting

If Android cannot reach Jellyfin:

- Use `make jellyfin-configure-urls MAESTRO_TARGET=android`.
- Confirm `MAESTRO_SERVER_URL` is `http://10.0.2.2:8096` for the emulator.
- Run `make jellyfin-api-test`.

If iOS cannot reach Jellyfin:

- Use `make jellyfin-configure-urls MAESTRO_TARGET=ios`.
- Confirm `MAESTRO_SERVER_URL` is `http://localhost:8096` for the simulator.

If a physical device cannot reach Jellyfin:

- Use `MAESTRO_TARGET=device`.
- Make sure the device and host are on the same network.
- Set `JELLYFIN_HOST_IP=<host-lan-ip>` if auto-detection chooses the wrong IP.

If Maestro cannot find elements:

- Check screenshots in `tests/maestro/artifacts/`.
- Confirm the app installed is the phone app, not the TV variant.
- Confirm the env file has the right server URL and username.

If fixture media is missing:

```bash
make jellyfin-download-media
make jellyfin-scan-library
make jellyfin-configure-maestro-ids
```
