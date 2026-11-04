# Receptor Desktop

A small Windows companion for transferring files and managing Receptor devices over private Wi-Fi. No Safari, SSH account, root password, USB driver or desktop installer is required. Receptor must already be installed on the device.

## Background access and package management (1.8.0 beta 1)

Use iOS **1.8.0b3** for explicit background-service startup, legacy launchctl query compatibility, a service Retry button and automatic connection diagnostics. Beta 3 fixes the misleading launchctl 0 verification error and adds confirmation before Forget saved connection. The Windows **1.8.0 beta 1** executable is unchanged. If a device grant is enabled but no device appears, upgrade iOS and tap **Restart service / Retry connection** on its Background desktop access screen. Saved permission alone is not proof of a live connection.

Update both apps to 1.8.0 beta 1. Enable **Allow background device access**, click **Start sharing**, then **Manage device…**. On the iPad, connect/refresh in Desktop, open **Background desktop access…** and compare the PC key before enabling it once. The saved grant reconnects with the app closed or after reboot whenever Wi-Fi is reachable. Keep this Windows app running (it can be minimized); no Windows service or sign-in startup is installed. iOS sleeping Wi-Fi behavior depends on power/OS, so unattended reachability is not guaranteed.

Manage device has Packages, Sources, Files and Log tabs. Review dependency previews before confirming installs/removals. Source add/remove and refresh run the same fixed APT helper as the native Packages tab. Close Cydia and other package managers first. Files lists and transfers regular visible files only in `/var/mobile/Media/Receptor/`; it does not expose the device's full filesystem or automatically install uploaded DEBs. To install repository packages use Packages. APT retains the system's TLS/certificate behavior.

This grants unattended package/source changes and confirmed desktop resprings, including while the device is locked. Disable on-device or Forget saved connection to revoke the device grant. Stop sharing or uncheck background access to pause desktop control; Reset pairing replaces the PC identity and revokes old grants. Already dispatched operations can finish; use Device operation log and Installed before retrying an uncertain operation. See the [device test checklist](../docs/REMOTE-TESTING.md). Physical-device validation is still pending.

The older Add files / Send to PC flow remains compatible and uses authenticated, **unencrypted** protocol v2. Manage device uses encrypted v3, including its Files transfers. The older sections below describe v2 unless stated otherwise.

## Background management protocol v3

The Windows `.remote` sidecar beside `%LOCALAPPDATA%\\Receptor\\pairing-v2.dat` stores a persistent RSA-2048 CSP private key encrypted with DPAPI for the current user, plus the opt-in preference. No private key is published. An authenticated v2 manifest advertises the SPKI PEM public key only when remote access is enabled. Compare the first 16 hexadecimal SHA-256 fingerprint characters on both screens during explicit device enrollment. The separate `.receive` sidecar and legacy pairing format are unchanged.

The device generates a random 32-byte seed, derives its ID from the first 32 hex characters of SHA-256(seed), and seals the seed with RSA-OAEP/SHA-1 for legacy .NET CSP compatibility. Its enrollment proof is `HMAC-SHA256(pairingKey, "enroll\\nDEVICE_ID\\nSHA256(sealedSeed)")`; pairingKey is the existing lowercase-hex ASCII v2 key. Root-only `/var/lib/receptor/remote.plist` stores the seed, sealed seed, proof, pinned key and PC address; it does not retain the legacy pairing key. Setup files are consumed and removed. On-device status exposes no secrets.

The daemon initiates `POST /v3/control` to the paired private IPv4 address, without proxies or redirects. Headers are `X-RC-Device`, `X-RC-Nonce` (32 fresh random hex), `X-RC-Sealed` (base64 RSA ciphertext), `X-RC-Enrollment` and `X-RC-Auth`. Payloads are bounded XML plists encrypted as byte `3`, IV16, AES-256-CBC/PKCS7 ciphertext. Encryption/authentication keys are `HMAC-SHA256(seed, "Receptor remote v3 encryption")` and the corresponding `authentication` string. The MAC is HMAC-SHA256(authKey, `DIRECTION\\n/v3/control\\nDEVICE_ID\\nNONCE\\nSHA256(frame)`), with request/response directions. The response MAC is `X-Receptor-Auth`. Authentication is checked before decryption. The protocol's authenticated key pinning and record encryption are separate from HTTPS; no certificate checks are bypassed.

Each device persists a monotonic counter and peer session. An authenticated counter-zero/empty-session request retrieves a counter floor and session without collecting a command; regular requests must advance the counter. Each PC server start or enable/disable transition changes the session. Up to eight enrolled devices can poll, with one in-flight poll/job per device. Polls wait up to 10 seconds; network requests time out after 25 seconds. Restart sharing to clear the device list. The root daemon sleeps/retries when offline; it has no inbound listener and no network activity without an explicit grant.

Commands contain a random ID and fixed `packages`, `files` or `respring` operation. No executable paths or shell commands are accepted. The daemon durably records a job before invoking a fixed helper and caches its reply. Redelivery returns that reply; an interrupted pending job is reported uncertain without repeating the command. Undispatched expired desktop jobs are cancelled; dispatched expired jobs are never resent, and a read-only Installed/Sources/operation-log recovery query is required before further mutations. This prevents automatic duplicate execution, but cannot guarantee delivery of a completion after a crash. The package operation log is the recovery record.

Files use 64 KiB chunks, metadata tokens, SHA-256 validation, private partial files and no-overwrite publication, up to 2 GB each. Remote file operations drop root to mobile before starting the non-setuid helper. Hidden names, traversal, symlinks, hardlinks, nonregular files and group/world-writable entries are refused. No deletion, arbitrary filesystem browser or automatic DEB execution is exposed. Package/IPA/DEB/respring changes share operation locks; grant revocation is allowed during an active package operation and prevents new work while that operation finishes.

## Receive files from the iPad/iPhone (1.6.0 beta 2)

Upgrade the iOS package to **1.6.0b2** and the Windows companion to **1.6.0 beta 2**. Existing saved pairings continue working. Enable **Receive files sent from the device**, choose a folder, and keep sharing running. You can enable receiving or choose its folder while the server is running, without disconnecting or changing the pairing. In Receptor’s **Files** tab, hold a file or use **••• → Send to PC**. Alternatively, select a readable regular file in the new **Filesystem** tab and choose **Send to PC**. Tap Send on the next screen. Manage pairing there if needed. Keep both apps open until delivery is verified; use **Open folder** on the PC to find the received file. Nothing is automatically opened, installed or executed. Receiving is disabled until explicitly enabled, then its enabled state/folder are saved for future starts. Changes apply to new requests; an active upload finishes in its original folder. Stop sharing cancels active transfers. The address/code stay visible while paused and before starting; press Start sharing before trying to connect.

The legacy receiver receives only explicitly selected files; download-folder browsing is available separately through the opt-in 1.8.0 background grant. The filesystem tab is read-only and uses the iOS app’s existing permissions, including their restrictions. It does not invoke the root DEB helper. Upload preparation uses an anonymous device-local snapshot, requiring additional free space equal to the source size. Changing files and non-regular files are rejected. Sending stops on backgrounding or leaving the screen. A fully delivered copy may remain after a cancelled/lost receipt. The PC publishes verified uploads without overwriting existing files. The maximum is 32 incoming files per sharing session, each at most 2,147,483,647 bytes. Restart sharing for a new session. Local transfers remain unencrypted.

## Send files to the iPad/iPhone

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

The XML plist manifest has `protocol` (integer 2), `files` (dictionaries containing `id`, `name`, `size`, `sha256`) and, since 1.6.0, `accepts_uploads` (boolean). An absent flag means receiving is unavailable. Responses carry `X-Receptor-Auth: HMAC(key, "response\nNONCE\nSHA256_BODY_HEX\nSESSION_HEX")`. Receptor verifies the manifest HMAC and then the file-response HMAC, expected size and SHA-256 before publishing or offering installation. Failed or cancelled authentication cannot replace a saved pairing or trigger installation.

The PC binds one selected private IPv4 address, serves only selected immutable file snapshots and caps headers, clients and the queue. Up to 32 files, each at most 2,147,483,647 bytes, are supported; empty files and files without extensions are supported too. Snapshots are deleted on normal shutdown; a crash can leave a `Receptor-<random-id>` directory in the Windows user's temp folder. The device streams to an exclusive mode-0600 partial, flushes it and publishes without overwriting existing files. Failure/cancellation cleans up the partial; a process crash may leave a hidden partial.

In the legacy v2 transfer flow, installation requires on-device confirmation; the separate v3 grant permits confirmed desktop APT operations. DEB scripts run as root, so authentication does not establish that a package's author or contents are trustworthy. There is no telemetry or cloud relay.

### Authenticated uploads (1.6.0 extension)

When receiving is enabled, `PUT /v2/uploads?nonce=NONCE` accepts a fixed-length body. Required headers are `Content-Length` (canonical decimal), `X-Receptor-SHA256` (lowercase hex), `X-Receptor-Name` (base64 of a UTF-8 basename) and `X-Receptor-Auth`. The authentication text is `PUT\n/v2/uploads\nNONCE\nSESSION_HEX\nCONTENT_LENGTH\nSHA256_HEX\nBASE64_NAME`, using the same ASCII hex key. Authentication binds all metadata before any file is written. Nonces are single-use across GET and PUT. Chunked bodies, invalid UTF-8, path separators and control characters are rejected. Windows-invalid filename characters are replaced and reserved device names prefixed; collisions get numbered suffixes.

Only one inbound upload runs at once. The server streams to a unique `.receptor-receive-<random>.part` in the chosen folder, verifies the digest, flushes, then renames without replacing another file. HTTP 201 returns the UTF-8 saved basename and the standard signed response header. The iOS client verifies that receipt before reporting delivery. Incomplete files are removed on cancellation/disconnect/stop; a PC crash can leave a partial. Receiving disabled returns 403, a busy/replayed request 409, the per-session limit 429, and a digest mismatch 422. A connection closed with an unread rejected body can appear as a TCP reset.

Receive preferences use a DPAPI-encrypted `pairing-v2.dat.receive` sidecar; the original six-field pairing file stays compatible with older companions. Older clients ignore the new manifest flag and continue receiving PC files. Reverse transfers require both apps at 1.6.0 or later. Beta 2 adds live receive configuration without changing the server session or clearing the outgoing file list. The native-control regression test enables receiving, uploads a file in the same session and checks visible pairing details across pause/restart using isolated settings.

## Build and test

```powershell
./Desktop/build.ps1
python tests/test_companion.py
python tests/test_companion_ui.py
```

```sh
# Linux/WSL, with cc and OpenSSL headers:
python3 tests/test_pairing_crypto.py
```

The desktop build uses the Windows .NET Framework compiler and produces `build/desktop/ReceptorDesktop.exe`. No NuGet dependencies or downloaded runtimes are used. The EXE is unsigned. Protocol tests exercise the actual server, DPAPI save/load, remembered pairing across restart, stale-session rejection, explicit reset, authenticated immutable transfers of image/text/ZIP/IPA/DEB/binary/extensionless/empty files, malformed requests and shutdown. Upload tests cover signed receipts, binary/empty/Unicode files, safe Windows names, no overwrite, authentication/metadata/digest/session failures, path traversal, partial cleanup, disabled receiving, concurrency and the session cap. Native tests compare the production C PBKDF2 loop with independent Python vectors. Keychain behavior, automatic reconnect, the iOS grid/image previews, Open In and installation still require physical-device testing. Transfer support does not imply that legacy iOS or an installed app can preview every format.

## iOS 1.4.1 sharing update

The Windows app stayed at 1.4.0 for the iOS 1.4.1 update; 1.6.0 now adds two-way transfers. On the device, 1.4.1 adds Share (system activity sheet on iOS 6; a legacy action menu on iOS 4–5), Save to Photos for supported images/videos, and separate Open In app selection. Save to Photos also appears directly in image preview. Open In only lists installed apps registered for the file type. Safari profile/certificate downloads are passed through to the native installer; retry an original profile link in Safari after updating and restarting Safari. The 1.4.1 Photos/share/profile fixes still require on-device validation.
