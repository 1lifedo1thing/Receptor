# Manual respring: 1.6.0b3 device checks

Host tests use fake services. They verify command/lock handling but cannot verify a real iOS UI restart or the device’s setuid/caller-code-hash checks. Test iOS 4–5 and 6–8 separately. iOS 7–8 remains experimental; this package is armv7 only.

1. Upgrade through Cydia so the helper has its required root ownership and mode 4755. Open Receptor; verify normal launch does not restart the interface. Confirm Files still exposes Desktop and Install Log.
2. Tap Files → Respring → Cancel. Nothing should restart. Repeat in Install Log, where Cydia is also available. Backgrounding while confirmation is open should cancel it.
3. After finishing transfers and closing Cydia, tap Respring and confirm. iOS 4–5 should request the SpringBoard launchd job; 6–8 should request backboardd. Expect a brief interface restart and return to the lock screen, without a device reboot. Verify no automatic repeat. Record exact device, firmware and jailbreak.
4. Attempt the action during a trusted DEB or IPA install: it must refuse. During an active Receptor download, confirm must refuse. Do not deliberately interrupt a real package transaction. An unrelated package manager holding the dpkg lock should cause the helper to refuse; the host fixture covers this without touching a real package manager.
5. Open a trusted DEB and complete installation. Its completion message should point to the manual button, without claiming a respring was detected or required. Respring only if the package’s instructions call for it. A package requiring a reboot still requires that reboot.
6. If the helper or launchctl request fails, the app should show a failure message and allow retry. Verify normal package installation still works afterward. Inspect system logs for device-only failures; never replace system launchctl or alter its launchd jobs to create a failure fixture.

No respring is scheduled at app startup, installation or boot. No automatic Cydia finish-channel detection is implemented. These checks do not establish why a device might independently show a spinner during normal boot.
