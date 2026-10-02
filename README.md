![netKillUI](docs/banner.png)

# netKillUI

A native macOS ARP-spoofing tool written in Swift — an `arpspoof`-style LAN
utility with a SwiftUI front end. By default it **cuts** a target's connection
(the "kill" in netKillUI); transparent MITM is optional. Zero third-party
dependencies; packets are injected directly into `/dev/bpf*` (Berkeley Packet
Filter).

> ## ⚠️ Authorized use only
>
> **netKillUI performs ARP cache poisoning**, which intercepts and can disrupt
> traffic on a local network.
>
> - Use it **only** on a network you own or have **written permission** to test.
> - Using it against devices or networks without consent is **illegal** in most
>   jurisdictions and may carry civil and criminal liability.
> - You are solely responsible for how you use it. The authors accept no
>   liability for misuse (see also [`LICENSE`](LICENSE)).
>
> The app shows this agreement on every launch. By running the tool you confirm
> you are acting lawfully and with permission.

## Features

- **Cut by default** — spoofing drops the target's traffic (IP forwarding stays
  **off**). A transparent **intercept** mode (forwarding on, MITM) is available.
- **Device discovery** — ARP sweep of the local subnet; hosts appear instantly
  and **names resolve in parallel** via Bonjour/mDNS, with reverse-DNS fallback
  and vendor lookup by OUI.
- **Device cache, online/offline & auto-scan** — known devices are remembered
  **per network** (keyed by the gateway's MAC, so different networks never mix);
  the list auto-refreshes every 60 s and marks who is online vs. offline.
- **Persistent block / block-on-appearance** — block a device (even an offline
  one); it stays blocked across restarts and is cut **the moment it reconnects**,
  caught passively from its ARP.
- **MAC-based targeting** — targets are tracked by MAC (stable); the current IP
  is followed live, so DHCP changes don't drop the target.
- **🥷 Ninja (stealth) mode** — passive discovery (no ARP sweep; also reads the
  OS ARP cache) and a gentler re-poison cadence. Honest scope: the *recon* is
  quiet — ARP poisoning itself is still detectable by DAI / 802.1X / IDS.
- **🛡 MAC masking** — optionally replace your own hardware MAC with a plausible
  one (vendor OUI + random tail) at engine start, to hide your device's identity;
  verified and honestly reported (may be rolled back by the OS on Wi-Fi), and
  restored on exit.
- **Foreign ARP-spoofer detection** — passively warns if *another* device on the
  network is impersonating the gateway or you.
- **Multi-target** — block one device, a selection, or all online hosts at once.
- **Safe by design** — your own machine and the gateway can't be targeted; ARP
  caches are restored and forwarding is disabled when you stop or quit.
- **Native GUI** — SwiftUI app with dark/light themes; no Terminal needed.

## Quick start (the app)

Build the double-clickable `.app` (ad-hoc signed — no Apple Developer ID
required):

```sh
./build-app.sh           # produces NetKillUI.app
open NetKillUI.app        # or drag it into /Applications
```

Accept the usage agreement, then click **Start engine** — macOS asks for your
password once (the privileged daemon runs as root) and the network is scanned.
Click a device to **block** it. Quitting restores every ARP cache automatically.

**Requirements:** macOS 13+, Xcode (to build). Apple Silicon or Intel.

## Command line

The engine also runs standalone (needs root for `/dev/bpf*` and
`net.inet.ip.forwarding`):

```sh
cd netspoof
swift build -c release

sudo .build/release/netspoof scan                     # list live hosts + names
sudo .build/release/netspoof spoof -t <mac|ip>        # one target (MITM; --no-forward to cut)
sudo .build/release/netspoof serve --socket <path>    # JSON daemon (used by the GUI; cuts by default)
```

Options:

| Option             | Meaning                                                      |
|--------------------|--------------------------------------------------------------|
| `-i <iface>`       | interface (auto-detected if omitted)                         |
| `-t <mac\|ip>`     | target — MAC (recommended, stable) or IP (`spoof`)           |
| `-g <ip>`          | gateway IP (auto-detected by default)                        |
| `--oneway`         | poison only the target, not the gateway                      |
| `--interval <ms>`  | ARP re-send period (default 2000)                            |
| `--no-forward`     | `spoof`: cut the target instead of relaying                  |
| `--intercept`      | `serve`: transparent MITM instead of the default cut         |
| `--mask-mac`       | `serve`: mask own MAC at startup (verified; restored on exit)|

`Ctrl-C` restores both ARP caches and disables forwarding.

## How it works

```
CBPF (C shim)       BPF ioctls (BIOCSETIF/BIOCIMMEDIATE/BIOCSETF…), default
                    gateway + ARP cache via PF_ROUTE, MAC get/set, process control.
ARPSpoofCore
  MACAddress/IPv4   address types + subnet math
  NetworkInterface  getifaddrs → MAC/IP/mask, active-interface detection
  RouteTable        default gateway, ip-forwarding (sysctl)
  ARPPacket         build/parse Ethernet+ARP frames
  BPFDevice         open /dev/bpfN, inject (write) and capture (poll+read)
  Bonjour/Hostname  device names via mDNS + reverse DNS
  MACMasker         plausible random MAC, apply + verify
  TrafficMeter      per-MAC byte accounting over a transparent MITM
  SpoofEngine       multi-target, MAC→IP bindings, live re-targeting, spoof detect
netspoof (CLI)      scan / spoof / serve
NetKillUI (SwiftUI) device list, blocking, osascript privilege elevation
```

Poisoning: the target is told "`gatewayIP` is at my MAC" (and, two-way, the
gateway is told "`targetIP` is at my MAC"); their caches update and traffic flows
through this Mac. In **cut** mode forwarding is off, so the target's traffic dies;
in **intercept** mode it is relayed transparently (MITM).

The GUI (unprivileged) launches `netspoof serve` as root via an osascript admin
prompt and talks to it over a unix socket (JSON, line-delimited). No code signing
or Apple Developer ID is required — the trade-off versus `SMAppService` is the
password prompt on launch. Note: if the daemon is `SIGKILL`ed, a masked MAC is
restored only on the next start.

## License

MIT, with an authorized-use notice — see [`LICENSE`](LICENSE).

Русская версия README: [`README.ru.md`](README.ru.md).
