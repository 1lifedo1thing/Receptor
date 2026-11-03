# Receptor 1.7.0b1: experimental Packages frontend

This beta adds native source management, repository-index refresh, package-name search, installed-package browsing, individual install/upgrade and removal. It uses the system’s APT/dpkg database. It is not a separately maintained installation database and is not a complete replacement for every Cydia feature.

**Real device source/package operations are not yet validated.** Test first on a recoverable device with a known-good jailbreak and package-manager setup. Record exact device, iOS, jailbreak, Cydia and APT versions. The supported build remains armv7, SDK 5.0 / minimum iOS 4.0, firmware below 9.0. iOS 7–8 adapters remain experimental.

## Device procedure

1. Install via Cydia. The package depends on `apt7 | apt` and installs `/usr/libexec/receptor-package-helper` as root:wheel, mode 4755. Fully close Cydia through the app switcher. No source/package transaction runs on app launch or boot.
2. Open Packages → Installed packages. Compare package identifiers/versions with Cydia’s Installed view. Filter by name. Inspect a known package’s details without making a change.
3. Open Sources. Compare enabled conventional `.list` entries with Cydia. Add a temporary flat HTTP(S) source with +, then refresh repository indexes. Read all refresh warnings: APT can return success with some sources failing. Do not post private source credentials or logs containing them publicly.
4. Search by package name (2–64 letters/digits/spaces/hyphens/underscores). Up to 500 results are shown. Pick a trusted nonessential test package with known compatibility. Choose Install / Upgrade, scroll through the entire APT plan, then cancel. Verify no installation happened.
5. Preview again and confirm. Keep Receptor in the foreground. Dependencies are resolved by APT; the install target is pinned to its exact candidate version. Check the full result and Installed view afterward. Do not use a root package manager concurrently. A failed/interrupted transaction can require repair through Cydia.
6. Authentication stays enabled by default. A legacy unsigned repository may be rejected by APT. Only if you intend to trust it, choose Allow unsigned… and accept the second per-install warning. Verify the next transaction returns to authenticated defaults. This never changes global trust configuration or TLS verification. Hashes from an unsigned index do not establish repository authenticity.
7. Remove the nonessential test package using Installed → Remove. Review the dependent removals first. Configuration files are kept; no autoremove or purge is run. Core/Essential/package-manager component removals are refused by the helper, including protected transitive removals. Do not intentionally test destructive system removals on a real device; host fixtures exercise that policy.
8. Remove the temporary source. Existing installed packages must remain. Newly added sources are kept in `receptor.list`; Cydia reads that file but may show its entries as read-only. Remove those entries through Receptor. For a Cydia-managed URI, removal includes all distributions for that URI in recognized legacy/root/mobile metadata. Unknown metadata and source symlinks are refused. Keep Cydia closed until the operation finishes, then reopen and verify the source stays removed.
9. Check cancellation of the source-removal confirmation. Refresh after source changes. Test package operations with Cydia still open: mutations must refuse rather than overwrite its in-memory source state. Do not manufacture a database-lock failure by interrupting an actual install.
10. Read Packages → Operation log after reopening the app. The helper records a private durable journal before and after mutations. A pending journal without completion is not proof of success or failure: inspect the package database before retrying. Finite iOS background time is not a persistent service; keep Receptor open.
11. Verify local DEB/IPA installs, package operations and manual Respring cannot overlap. Respring remains explicitly confirmed; no automatic restart detection is added.

## Source state and recovery

Added flat sources are written atomically to `/etc/apt/sources.list.d/receptor.list`. Existing conventional `.list` entries can be selected for removal using an identity derived from the path and full source line; stale selections are rejected. Receptor never accepts an arbitrary filesystem path as a helper argument.

Cydia removal supports recognized `Sources` metadata in `/var/lib/cydia/metadata.plist` and `CydiaSources` in root/mobile Cydia preferences. Unrelated dictionary keys are preserved. Known legacy/root/mobile Cydia cache links are resolved only through an explicit whitelist. On-device preference updates synchronize the corresponding root/mobile CFPreferences domain. That daemon synchronization and Cydia process detection cannot be validated by the GNUstep host tests.

Before removal, `/var/lib/receptor/last-source-removal.plist` stores the original affected files in a root-owned private directory. The helper attempts rollback if any file update or preference synchronization fails. Multi-file edits cannot be atomic across a power loss; retain the backup and use a trusted root maintenance tool/Cydia to inspect or restore it if needed. Do not blindly overwrite newer Cydia state. Source additions do not rewrite Cydia’s generated list or metadata.

`/var/lib/receptor/last-operation.plist` records the last mutating operation and its result. It is private and contains local logs, not telemetry. The app can read it only through the authenticated helper’s fixed log operation. Logs are bounded; a large or incomplete simulation cannot be confirmed. Neither helper deletes package-manager lock files.

## APT and TLS limitations

The device must provide compatible `/usr/bin/apt-get` and `/usr/bin/apt-cache`. HTTPS methods, TLS/certificate support and repository authentication are provided by that APT installation, independently of Receptor’s bundled curl downloader. Missing HTTPS methods or old system TLS can still prevent refresh/downloads. No TLS verification bypass is installed. Unsupported repository layouts and commercial account authentication require their normal Cydia/provider setup.

Bulk upgrades, purge/autoremove, dependency-repair commands, arbitrary APT options, arbitrary executable paths and arbitrary root shell commands are not exposed. Changed source lists, installed state or dependency/version plans require a fresh preview. Other root tools can still change state outside Receptor; do not run them concurrently. Existing modified conffiles are kept with `--force-confold`; architecture, dependency and package-script failures remain APT/dpkg errors.

## Host verification

```sh
# GNUstep is only a host-test dependency, not an iOS package dependency.
sudo apt-get install --no-install-recommends libgnustep-base-dev libssl-dev gobjc
python3 tests/test_package_manager.py
python3 tests/test_deb_helper.py
```

The first test compiles the production Objective-C helper under GNUstep with every path redirected into a private fixture and fake APT executables. Test mode is forbidden on Apple builds. It exercises listing/search/details/refresh, exact-version install/remove previews and confirmation, normal/per-install unsigned policy, changed dependency/status/source/token rejection, dangerous identifiers, protected and transitive removals, native failures, source validation/duplicates/removal, legacy/preferences metadata, rollback, backups, journals and locks. It never invokes the host’s real APT/dpkg or uses the network. The DEB/respring tests use separate fake commands.

The signed armv7 build, package root ownership/modes, caller-authentication markers, legacy linkage and repository checksums are checked separately. These checks do not execute UIKit or the device-only code-hash/CFPreferences/kernel/network paths.

## 1.8.0 background desktop integration

See [Background desktop setup and testing](REMOTE-TESTING.md). The optional root daemon invokes the same fixed package helper; mobile-owned download-folder operation locking now also coordinates IPA, DEB, APT and respring actions. Status/revocation remain available while another package operation holds the lock. No automatic respring or full-filesystem remote access is added. Test foreground and background transaction exclusion on physical devices before relying on unattended changes.
