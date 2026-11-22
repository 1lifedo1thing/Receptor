# Receptor for iPhone OS 3.2 — experimental beta 1

Separate package: **Receptor (iPhone OS 3.2)**, ID `com.receptor.downloadmanager.ios32`, version `1.8.0b1`. Targets the **armv7 iPad 1 on 3.2–3.2.2**; install metadata requires firmware >=3.2 and <4.0 and iPad device family. This is a compiled compatibility port, **not yet physically device-validated**. The regular iOS 4–8 package remains separate and unchanged in the Cydia indexes.

Install from `https://jajaengland.github.io/repo/`, choosing the explicitly named 3.2 package. If Cydia cannot fetch the HTTPS source, the GitHub test release includes the DEB for manual transfer/installation through your existing jailbreak tools. It conflicts with/replaces the regular Receptor package because both use the same app/tweak paths. Do not force the normal package onto 3.2. Keep a copy of important files before changing packages. Downloads remain in `/var/mobile/Media/Receptor/`.

## Included behavior

- Safari legacy WebView download interception, with runtime delegate-signature checks; direct URL downloads in the standalone app.
- Bundled curl/Mbed TLS rebuilt with a 3.2 minimum, retaining certificate and hostname verification. This does not upgrade Safari webpage or Cydia/APT TLS.
- Grid/list file browsing, search, deletion, read-only filesystem navigation and Open In using the 3.2 document interaction APIs.
- Foreground two-way PC transfers with the existing **Receptor Desktop 1.8.0 beta 1**. Saved pairing remains in Keychain using the OS 3.2 default policy; iOS 4 device-only accessibility attributes are not used. Forget still requires confirmation.
- PNG/JPEG image preview and Save to Photos, limited to **3 megapixels / 8 MB**, using bounded file reads. Grid uses generic file icons instead of ImageIO thumbnails. Videos use the legacy Photos API when its compatibility check accepts them. Other/large images can be opened in a compatible app or sent to the PC.
- Native document preview through UIDocumentInteractionController instead of Quick Look. Supported formats depend on 3.2.
- Existing fixed-operation IPA/DEB installation, APT/source management and confirmed respring paths. Real 3.2 MobileInstallation ABI, APT metadata and kernel caller-code-hash authorization remain unverified. Missing authorization fails closed; it is not replaced with a root password or path-only check.

## Background sync is disabled

As requested, this package installs **no background desktop agent, remote file helper or LaunchDaemon**. Background enrollment/start operations are refused. The UI labels the feature unavailable. Keep Receptor open for desktop transfers and app downloads; closing the owning app can interrupt a transfer, leaving an incomplete hidden partial. There is no iOS 4 finite-background-task API or resume after process exit. Safari-owned downloads likewise require Safari to remain open. No local notifications are used; completion messages queue for the owning app when possible.

## Compatibility work

The 3.2 flavor uses old plist serializers with MRC error ownership, a bounded cache in place of NSCache, a window root-controller/lifecycle adapter and legacy UIKit drawing/Photos/document APIs. Blocks expressions for background tasks and newer activity sharing are compiled out. Its four binaries have no startup imports from Blocks/GCD, Quick Look, ImageIO, AssetsLibrary, local notifications or newer Keychain accessibility constants. All 309 bundled TLS objects also have a 3.2 deployment target. The code is built with the available **SDK 5.0**, not a recovered SDK 3.2; dependency checks are not proof of on-device compatibility.

## Build and checks

```sh
THEOS=/path/to/theos RECEPTOR_MIN_IOS=3.2 bash scripts/build-tls.sh
THEOS=/path/to/theos RECEPTOR_LEGACY32=1 bash scripts/build-wsl.sh
python3 tests/check_ios32.py
python3 tests/test_legacy32_foundation.py
```

Despite its name, the build script also runs on Linux. Use the script so legacy control/app metadata and daemon-free layout are staged together; direct `make RECEPTOR_LEGACY32=1` against the regular metadata is rejected. Artifacts go to `build/ios32/` and `packages/com.receptor.downloadmanager.ios32_1.8.0b1_iphoneos-arm.deb`. The normal build omits these environment flags and uses its original libraries/target.

## First device test

1. Record exact firmware/jailbreak. Install through Cydia so Substrate and compatible APT dependencies are present; close/reopen Safari and launch Receptor. Report a crash log if either fails to load.
2. Test a small HTTP file, a verified HTTPS file, direct URL entry and a Safari download. Check bytes and completion/error output. Retry an untrusted TLS endpoint: it must fail rather than ignore verification.
3. Pair with the existing PC app, receive/send a small file, close/reopen Receptor and confirm the pairing was saved. Test Forget → Cancel, then confirmed Forget and re-pair. No background connection should appear and no agent should be installed.
4. Test rotation, grid/list/search/deletion, a small PNG/JPEG preview, document preview, Open In and Save to Photos. Unsupported/oversized images must show the stated limit.
5. Test read-only filesystem navigation and PC export with a harmless readable regular file. Protected paths/special files must not become accessible through a privileged browser.
6. Only after basic UI/transfers work, test a known compatible harmless IPA/DEB and a small APT operation with Cydia closed. Inspect logs and check installed state; do not retry an uncertain package transaction blindly. Test respring last, explicitly, after all transfers finish.

Report exact failing action, error and device crash log if available. Do not post pairing credentials or private files.
