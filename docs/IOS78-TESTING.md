# Receptor 1.5.0: experimental 32-bit iOS 7–8 support

This is a first test build for armv7 devices such as iPad 4, iPhone 4/4S/5/5c and other compatible 32-bit hardware. Firmware must be at least 4.0 and below 9.0. Device-specific firmware availability still applies. **iOS 7–8 behavior is not yet device-validated. arm64 Safari injection is not included.**

The package still contains armv7 executables built with SDK 5.0 and a minimum iOS 4.0 deployment target. Existing 1.4.1 packages and release files remain available unchanged for iOS 4–6 users. The 1.6.0 companion adds optional device-to-PC transfers; existing pairing credentials are retained. See [two-way transfer tests](TRANSFER-TESTING.md).

## Runtime paths

| Feature | iOS 4–6 | iOS 7 | iOS 8 |
| --- | --- | --- | --- |
| Safari interception | Existing guarded WebView policy adapter | Same legacy adapter; needs device test | New WKWebView navigation-delegate adapter; needs device test |
| Safari download | Existing in-Safari downloader | Opens Receptor; confirm Download in app | Opens Receptor; confirm Download in app |
| Direct URL / PC transfers | Existing app engine | Same app engine; needs device test | Same app engine; needs device test |
| IPA installer | MobileInstallationInstall | MobileInstallationInstall; needs device test | LSApplicationWorkspace; needs device test |
| Notifications | Existing local notification API | Existing local notification API | Requests alert/sound notification permission |
| Native installer content | Profiles/certificates pass through; Passbook on iOS 6+ | Profiles/certificates/Passbook pass through | Profiles/certificates/Passbook pass through |

The WK adapter uses iOS 8's original action/response policy callbacks (cancel=0, allow=1), validates delegate signatures, and retains Safari's original delegate only temporarily through the Objective-C runtime's zeroing-weak APIs. New interfaces and weak functions are resolved dynamically so iOS 4 does not need to load iOS 8-only symbols. Unknown interfaces are left with Safari's original delegate. Optional callbacks and both public/private authentication paths are forwarded; the adapter never accepts a certificate challenge itself.

Downloads on iOS 7–8 continue in the standalone app to avoid relying on Safari's sandbox and process lifetime. Only the HTTP(S) GET URL is handed off; request headers, POST bodies and private Safari/WK cookies are not transferred. The app confirms every incoming download URL, including URLs invoked by other apps. Public file links are the supported first test case. Login-dependent downloads, one-time responses, blob/data URLs and POST replays are not supported by this handoff. Cross-origin WK response replays discard credentials/custom headers, and HTTPS-to-HTTP responses are not replayed by Receptor.

The iOS 8 installer reads one `Payload/<app>.app/Info.plist` without extracting files, obtains the bundle identifier, and invokes the dynamically checked workspace installation method. The reader accepts stored/deflated ZIP entries, checks local/central metadata and CRC, rejects ambiguous roots, limits plist/compressed data to 2 MB, and rejects unsupported encryption/ZIP64/compression. The OS still performs installation, compatibility and signing checks. AppSync/signing requirements and FairPlay authorization still apply. Keep Receptor open during installation; finite background time is not a persistent service.

## Device test checklist

Record the exact device, iOS version, jailbreak and Receptor version. Test iOS 7 and iOS 8 separately; results for one do not certify the other.

1. Install through Cydia, close/reopen Safari, and open the Receptor Home screen app. Verify the grid/list, search, image preview/rotation and existing files still work.
2. In Receptor, use + with a public HTTPS file URL. Check success, byte length and a duplicate filename. Cancel another download and check the completed file remains intact.
3. In Safari, tap a public ZIP/IPA link. Expect a Receptor prompt, Open Receptor, then an in-app Download confirmation. Verify the file is saved. Test an attachment URL without an extension and an unsupported MIME response separately.
4. Test normal web navigation, new-tab file links and subframes. Normal pages, sign-in/challenge handling and subframe content should keep Safari's original behavior.
5. Open a trusted configuration-profile/certificate link and verify the native installer appears; cancelling is sufficient for this handoff test. Check a Passbook link if applicable.
6. Pair with the existing Windows companion, send an image/text/empty file and reconnect after restarting the PC app.
7. With an app known to be compatible with this device/iOS and signing setup, confirm an IPA install. On iOS 8 the workspace path is used. Report the exact native error/domain/code on failure. A ZIP fixture is not an installable IPA.
8. Save a supported image/video to Photos; test Share and Open In with a registered receiving app. On iOS 8, allow notifications if you want background completion alerts and test them separately.
9. If testing DEB installation, use a trusted package with satisfied dependencies and verify its result in Install Log and Cydia. The existing fixed-operation helper is unchanged; this path still needs device validation.

For controlled HTTP fixtures, run `python tests/fixture_server.py --bind 0.0.0.0 --port 8080` on a reachable PC. It provides ZIP, attachment, raw-text, unknown-MIME, error, redirect and cancellation cases. It does not supply an installable app. iOS 8 Safari's system log should contain the constant message `[Receptor] iOS 8 WKWebView interception enabled (experimental, 32-bit)` when its runtime setter was found. Do not post cookies, pairing codes or private download links with test results.

## Host checks performed

- armv7 app/tweak/helper compile and signing with SDK 5.0 / minimum iOS 4.0.
- Mach-O import checks: no hard startup dependency on WKWebView, workspace, notification-settings classes or weak-runtime entry points.
- Production C ZIP-reader tests: stored/deflated XML/binary plist, comments/data descriptors, truncation, duplicate/multiple app roots, traversal-shaped roots, bad CRC/offsets, size limits, unsupported methods/encryption/ZIP64, and 1000 deterministic corrupted archives.
- Production shared file/native-installer classification tests, including Passbook availability by iOS version.
- Existing project/package/repository integrity checks.

These do not execute UIKit, Safari, installd or the iOS kernel. No iOS 7/8 device result is claimed.

## Interface references

- Apple's [iOS 8-era WKNavigationDelegate header](https://github.com/apple-oss-distributions/WebKit2/blob/WebKit2-7600.1.4.11.10/UIProcess/API/Cocoa/WKNavigationDelegate.h), [response properties](https://github.com/apple-oss-distributions/WebKit2/blob/WebKit2-7600.1.4.11.10/UIProcess/API/Cocoa/WKNavigationResponse.h), and [navigation dispatch implementation](https://github.com/apple-oss-distributions/WebKit2/blob/WebKit2-7600.1.4.11.10/UIProcess/Cocoa/NavigationState.mm).
- The upstream [appinst installation API usage](https://github.com/akemin-dayo/AppSync/blob/master/appinst/appinst.m) and [installer entitlement list](https://github.com/akemin-dayo/AppSync/blob/master/appinst/appinst_entitlements.plist). Receptor implements its own bounded plist reader and staging/error handling; it does not embed appinst/libzip.
- WebKit's [private-cookie/download replay limitation](https://bugs.webkit.org/show_bug.cgi?id=158801).
