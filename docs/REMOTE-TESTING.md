# Background desktop access: 1.8.0 beta 2

This beta needs physical-device testing. Host tests cover the production native agent, Windows broker, crypto, file helper and setup validation, using disposable credentials and fake package commands. They do not establish that launchd, locked Wi-Fi, root/mobile permissions or APT work on every supported jailbreak.

## One-time setup

1. Update Receptor to **1.8.0b2** and use **ReceptorDesktop.exe 1.8.0 beta 1** (unchanged). Keep Cydia closed during package operations.
2. On Windows, enable **Allow background device access** and **Start sharing**. Open **Manage device…** to see the PC key fingerprint.
3. In Receptor → **Desktop**, connect/refresh using your saved pairing (or pair once with the address/code).
4. Open **Background desktop access…**, tap Enable and compare the displayed PC key with Windows. Confirm only the intended PC.
5. Leave Receptor or lock the device. Keep the Windows companion running and sharing enabled. In **Manage device…**, select the device, then use Packages, Sources or Files. Files exposes only `/var/mobile/Media/Receptor/`, not the Filesystem tab.

The grant authorizes the paired PC to install/remove packages, edit sources, request a respring and transfer download-folder files without touching the iPad again, including while locked. APT plans still require confirmation on the PC. It persists across app closure and reboots until revoked. Do not enable it on a shared or untrusted PC. No root password or arbitrary remote shell is exposed.

## If Windows says no background device is connected

Beta 1's enabled label only meant that permission was saved. It relied on the launchd PathState trigger and did not explicitly load/start the service when enabling. Beta 2 adds fixed launchctl load/start calls, refreshed status and network/authentication diagnostics. It does not establish the cause of every connection failure.

For an existing grant, open Background desktop access and tap **Restart service / Retry connection** once. This does not kill/restart a running agent or package operation. Wait up to 30 seconds, then read the text **below the buttons**. The top label now says **Background permission saved**, not connected. Capture the diagnostic text and exact iOS/device if it still fails. A PC rejection requires checking the Windows background checkbox, Connect / Refresh, then enabling the grant again. A stopped/unloaded service or failed load/start is reported separately. Recent diagnostic messages must match this grant; stale status from an earlier grant is ignored.

## Device checklist

- Test first on iPad 1 / iOS 5.1.1 and a 32-bit iOS 7–8 device. Record exact device, OS and jailbreak. Install through Cydia so dependencies, daemon and helper permissions are configured.
- Before enabling, reboot and confirm there is no active remote agent/network access. Merely installing the package must not respring or enroll a PC.
- Compare fingerprints, enable once, then fetch Installed, Sources and Files with Receptor closed. Try supported binary, empty, Unicode and extensionless files in both directions; compare hashes and check duplicate names do not overwrite. Hidden files, symlinks, folders and protected filesystem paths must not be exposed.
- Repeat at Home, locked on power, locked on battery and after reboot/unlock. The device must stay powered and reachable on Wi-Fi. Legacy iOS may suspend Wi-Fi while asleep; no wake lock or guaranteed battery/sleep connectivity is claimed.
- Stop/start sharing, close/reopen Windows, restart Receptor, interrupt Wi-Fi and restart the device. Saved grants should reconnect when the same PC/address is reachable. A changed PC IP requires foreground reconnect and re-enabling the grant. Changing the IP alone does not change the key.
- Test a known harmless package: preview dependency changes, cancel, then confirm. Check APT output and Installed. Test source add/remove and Cydia metadata synchronization. Source refresh uses system APT networking/certificates, not Receptor's download TLS stack. Do not run Cydia or another package manager concurrently.
- Start a long operation, lose the connection, then inspect **Log → Device operation log** and Installed before repeating it. An interrupted result is uncertain; commands must not be replayed automatically. A command already running may finish after Stop sharing or revocation. Receptor never deletes dpkg/APT lock files.
- Try an app IPA/DEB installation while remote APT is active: the shared operation lock must refuse concurrent changes. Respring needs explicit desktop confirmation and must respect package-manager locks. Finish transfers before restarting the UI.
- Disable background access on the device: Windows must stop receiving results/dispatching further work. Repeated Disable is safe. **Forget saved connection** revokes background access before deleting the Keychain pairing. **Reset pairing** on Windows revokes old enrollment proofs and replaces its RSA identity; a fresh foreground grant is required.
- Close Windows while sharing is enabled and reopen: its saved sharing preference resumes, but the companion does not install a Windows service or register automatic sign-in startup. Allow private-network firewall access if asked.
- Remove Receptor: the grant is deleted and the launchd job unloaded. Upgrade while no operation is active and verify reconnection. Do not interrupt a device package-manager transaction to test upgrades.

## Host checks

```powershell
./Desktop/build.ps1
./tests/build_remote_host.ps1
python tests/test_companion.py
python tests/test_companion_ui.py
```

```sh
# WSL: GNUstep development files, OpenSSL, libcurl development files and Mono
python3 tests/test_remote_configuration.py
python3 tests/test_remote_access.py
python3 tests/test_package_manager.py
python3 tests/test_deb_helper.py
```

Tests redirect all privileged paths to temporary fixtures. Never build test-mode helpers into a device package.
