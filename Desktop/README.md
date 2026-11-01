# Receptor Desktop

A small Windows companion for sending local files to Receptor over Wi-Fi. No Safari, SSH account, root password, USB driver or desktop installer is required. Receptor must already be installed on the device.

## Use

1. Upgrade both the iOS package and Windows companion to **1.4.0 or later**. Existing saved pairings from 1.3.1 are preserved; 1.3.0 used an incompatible pairing protocol.
2. Run **ReceptorDesktop.exe** on Windows with .NET Framework 4.x (included with Windows 10/11). Choose the Wi-Fi IPv4 address, then **Start sharing**. Allow private-network access if Windows Firewall asks.
3. Choose **Add files…** and select any local files: images, documents, music, videos, archives, IPAs or DEBs. Keep enough free disk space for temporary snapshots.
4. On the iPad/iPhone, open Receptor → **Desktop**. Enter the displayed `address:49176` and the **8-character code** (shown as `ABCD-EFGH`). The hyphen and spaces are optional; upper/lowercase both work. Tap **Connect / Refresh**.
5. After successful authenticated pairing, Receptor saves the connection. Next time you open Desktop or return to the app with that screen open, it reconnects automatically. Leave the code blank to use the saved pairing.
6. Tap a file to receive it and keep Receptor open until it finishes. Return to **Browse** to view it in the grid or list, preview supported images/documents, or use **••• → Open In…** to send it to a compatible installed app. DEBs retain a separate installation confirmation; IPAs can be installed from their file menu. Installation output is in **Install Log**. The PC's “Sent” message confirms transfer only.

Windows remembers the selected address, code and sharing preference. If you close it while sharing, it resumes sharing when you reopen it. **Stop sharing** pauses access and disables that automatic restart; it preserves the pairing. It does not register a Windows startup task or background service. Shared file selections are session-only and need to be added again after closing the PC app.

Use **Forget saved connection** on the iPad to erase its local credential. To revoke all previously paired devices, stop sharing on the PC and click **Reset pairing**. This generates a different code and key. Every device then needs to enter the new short code once.

Both devices need a private IPv4 LAN (10.x.x.x, 172.16–31.x.x, 192.168.x.x or link-local 169.254.x.x). Guest isolation, a VPN or Windows Firewall can block connections. If the PC's IP changes, edit the address in Receptor and connect with the code blank to reuse the saved pairing. The address is updated only after authentication succeeds. If port 49176 is occupied, close the other application using it and retry. IPv6, discovery, USB and installing Receptor itself are not implemented. Dependencies still need installing through Cydia.

## Saved pairing and protocol v2

Local HTTP remains compatible with iOS 4–6. **File contents and filenames are not encrypted.** The short code is an authentication secret; do not post a real pairing code publicly. It consists of eight independently random characters from a 32-character alphabet (40 bits), without I/O/0/1. PBKDF2-HMAC-SHA256 with a random per-pairing 16-byte salt and 100,000 iterations derives the 32-byte key. This slows offline guessing but is not a password-authenticated key-exchange protocol; use a trusted private network. The code is never transmitted.

Windows stores the code, salt, derived key, last address and sharing preference in `%LOCALAPPDATA%\Receptor\pairing-v2.dat`, encrypted for the current Windows user with DPAPI. The iOS app stores the address, derived key and salt in its own Keychain access group, accessible while unlocked and limited to that device. It does not save the short code. Saving occurs only after an authenticated, valid manifest. Failed connections retain the previous saved record. Saving errors are shown explicitly. The iOS Keychain item can survive uninstall; Forget saved connection removes it.

`GET /v2/pairing?nonce=<32-lowercase-hex>` returns the public bootstrap text `2\nSALT_HEX\nSESSION_HEX`. The 128-bit server session changes on every sharing start. Bootstrap data alone is not trusted: the subsequent manifest must authenticate, and a saved credential requires its stored salt to match.

Authenticated routes are `/v2/manifest` and `/v2/files/<32-lowercase-hex-id>`, each with a fresh `?nonce=<32-lowercase-hex>`. `X-Receptor-Auth` is lowercase hex HMAC-SHA256 over `GET\nROUTE\nNONCE\nSESSION_HEX`, using the lowercase hex derived key's ASCII bytes as the HMAC key. Successfully authenticated nonces are rejected if reused; after 4096 requests, restart sharing. The new server session prevents old authenticated requests from becoming usable again after a PC restart, even though the saved key persists.

The XML plist manifest has `protocol` (integer 2) and `files` (dictionaries containing `id`, `name`, `size`, `sha256`). Responses carry `X-Receptor-Auth: HMAC(key, "response\nNONCE\nSHA256_BODY_HEX\nSESSION_HEX")`. Receptor verifies the manifest HMAC and then the file-response HMAC, expected size and SHA-256 before publishing or offering installation. Failed or cancelled authentication cannot replace a saved pairing or trigger installation.

The PC binds one selected private IPv4 address, serves only selected immutable file snapshots, accepts GET only and caps headers, clients and the queue. Up to 32 files, each at most 2,147,483,647 bytes, are supported; empty files and files without extensions are supported too. Snapshots are deleted on normal shutdown; a crash can leave a `Receptor-<random-id>` directory in the Windows user's temp folder. The device streams to an exclusive mode-0600 partial, flushes it and publishes without overwriting existing files. Failure/cancellation cleans up the partial; a process crash may leave a hidden partial.

Only on-device confirmation can initiate installation through the existing helper. DEB scripts run as root, so authentication does not establish that a package's author or contents are trustworthy. There is no telemetry or cloud relay.

## Build and test

```powershell
./Desktop/build.ps1
python tests/test_companion.py
```

```sh
# Linux/WSL, with cc and OpenSSL headers:
python3 tests/test_pairing_crypto.py
```

The desktop build uses the Windows .NET Framework compiler and produces `build/desktop/ReceptorDesktop.exe`. No NuGet dependencies or downloaded runtimes are used. The EXE is unsigned. Protocol tests exercise the actual server, DPAPI save/load, remembered pairing across restart, stale-session rejection, explicit reset, authenticated immutable transfers of image/text/ZIP/IPA/DEB/binary/extensionless/empty files, malformed requests and shutdown. Native tests compare the production C PBKDF2 loop with independent Python vectors. Keychain behavior, automatic reconnect, the iOS grid/image previews, Open In and installation still require physical-device testing. Transfer support does not imply that legacy iOS or an installed app can preview every format.

## iOS 1.4.1 sharing update

The Windows app is unchanged at 1.4.0. On the device, 1.4.1 adds Share (system activity sheet on iOS 6; a legacy action menu on iOS 4–5), Save to Photos for supported images/videos, and separate Open In app selection. Save to Photos also appears directly in image preview. Open In only lists installed apps registered for the file type. Safari profile/certificate downloads are passed through to the native installer; retry an original profile link in Safari after updating and restarting Safari. The 1.4.1 Photos/share/profile fixes still require on-device validation.
