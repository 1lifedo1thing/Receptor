# Receptor Desktop

A small Windows companion for sending local DEBs to Receptor over Wi-Fi. No Safari, SSH account, root password, USB driver or desktop installer is required. Receptor must already be installed on the device.

## Use

1. Upgrade the iOS package to **Receptor 1.3.0 or later** in Cydia.
2. Run **ReceptorDesktop.exe** on a Windows PC with .NET Framework 4.x (included with Windows 10/11). Choose the PC's Wi-Fi IPv4 address, then **Start sharing**. Allow private-network access if Windows Firewall asks.
3. Choose **Add DEBs…** and select packages downloaded using your desktop browser. Keep enough free disk space for the desktop app's temporary copies.
4. On the iPad/iPhone, open Receptor → **Desktop**. Enter the displayed `address:port` and the pairing code; hyphens/spaces in the code are optional. Tap **Connect / Refresh**.
5. Tap a DEB in the list. Keep Receptor open while receiving it. After verification, choose **Install** on the device or **Keep File** to install later.
6. Installation results are in Receptor → Files → **Install Log**. Reopen Cydia to refresh its Installed list. Desktop's “Sent” message confirms transfer only.
7. **Stop sharing** or close the desktop app when finished. Starting a new session generates a new code and clears the shared list.

Both devices need a private IPv4 LAN (10.x.x.x, 172.16–31.x.x, 192.168.x.x or link-local 169.254.x.x). Guest-network isolation, a VPN, or Windows Firewall can prevent connections; select the correct adapter and permit the app on your private network. IPv6, automatic discovery, USB transfer and installing Receptor itself are not implemented. If the PC changes address, stop and start sharing. There is no automatic dependency download; install dependencies through Cydia as usual.

## Pairing and transfer protocol

Sharing uses local HTTP to remain compatible with iOS 4–6. **File contents and filenames are not encrypted.** The random, 80-bit pairing code is an authentication secret entered directly on the device, is never sent across the network, is held in memory only, and is revoked when sharing stops. Do not publish or share a live session's code. Device address/code fields are not persisted.

Each request contains a fresh 128-bit nonce and an HMAC-SHA256 over `GET\nROUTE\nNONCE`, with the normalized uppercase code's ASCII bytes as key. Routes are `/v1/manifest` and `/v1/files/<32-lowercase-hex-id>`, with `?nonce=<32-lowercase-hex>`. Request authentication is sent in `X-Receptor-Auth` as lowercase hex. Successfully authenticated nonces cannot be reused; after 4096 requests, start a new sharing session.

The XML property-list manifest contains `protocol` (integer 1) and `files` (array of dictionaries with `id`, `name`, `size`, `sha256`). Responses carry `X-Receptor-Auth: HMAC(key, "response\nNONCE\nSHA256_BODY_HEX")`. The iOS client verifies the manifest HMAC, then verifies both the file-response HMAC and the manifest's expected size/SHA-256 before publishing a file or offering installation. This detects network modification and substituted/replayed responses, while permitting observers to read the public DEB bytes.

The PC binds one selected private IPv4 address, serves only explicitly added immutable snapshots, accepts GET only, caps headers/clients/queue size, and never exposes filesystem paths. Up to 32 DEBs, each no larger than 2,147,483,647 bytes, are supported per session. Temporary snapshots are deleted on normal shutdown; a crash can leave `Receptor-<random-id>` under the Windows user's temp folder. The device streams to an exclusive mode-0600 partial file, checks the archive header, flushes it, and publishes without overwriting existing files. Cancellation/failure cleans up that partial; a process crash may leave a hidden partial file.

The transfer protocol cannot execute commands or trigger installation remotely. A received DEB is installed only after on-device confirmation, using Receptor's existing package-manager helper. It runs package scripts as root, so pairing/file integrity does not establish that a package's author or contents are trustworthy. There is no telemetry or cloud relay.

## Build and test

```powershell
./Desktop/build.ps1
python tests/test_companion.py
```

The build uses the Windows .NET Framework C# compiler and produces `build/desktop/ReceptorDesktop.exe`. No NuGet dependencies or downloaded runtimes are used. The EXE is unsigned. The protocol tests start the actual desktop server on loopback and check authenticated transfers, immutable snapshots, replay/code failures, malformed requests, response-tamper detection and listener shutdown. These checks do not execute the iOS app; pairing and DEB installation still require physical-device testing.
