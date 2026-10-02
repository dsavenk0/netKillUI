# netKillUI

A native macOS ARP-spoofing tool written in Swift — an `arpspoof`-style LAN
utility (MITM / connection cutting) with a SwiftUI front end. Zero third-party
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
> By running this tool you confirm you are acting lawfully and with permission.

## Features

- **Device discovery** — ARP sweep of the local subnet; hosts appear instantly
  and **names resolve in parallel** via Bonjour/mDNS (e.g. `redmi-12`,
  `desktop-…`), with reverse-DNS fallback and vendor lookup by OUI.
- **MAC-based targeting** — targets are tracked by MAC (stable); the current IP
  is followed live, so DHCP changes don't drop the target.
- **Transparent MITM** — enables `ip.forwarding` by default (intercept without
  cutting); a cut mode (`--no-forward`) is available for your own devices.
- **Multi-target** — spoof one device, a selection, or all at once.
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

Click **Start engine** inside the app — macOS asks for your password once (the
privileged daemon runs as root), then the network is scanned. Toggle a device
to spoof it. Quitting the app restores every ARP cache automatically.

**Requirements:** macOS 13+, Xcode (to build). Apple Silicon or Intel.

## Command line

The engine also runs standalone (needs root for `/dev/bpf*` and
`net.inet.ip.forwarding`):

```sh
cd netspoof
swift build -c release

sudo .build/release/netspoof scan                     # list live hosts + names
sudo .build/release/netspoof spoof -t <mac|ip>        # MITM one target
sudo .build/release/netspoof serve --socket <path>    # JSON daemon (used by the GUI)
```

`spoof` / `serve` options:

| Option             | Meaning                                                  |
|--------------------|----------------------------------------------------------|
| `-i <iface>`       | interface (auto-detected if omitted)                     |
| `-t <mac\|ip>`     | target — MAC (recommended, stable) or IP                 |
| `-g <ip>`          | gateway IP (auto-detected by default)                    |
| `--oneway`         | poison only the target, not the gateway                  |
| `--interval <ms>`  | ARP re-send period (default 2000)                        |
| `--no-forward`     | don't enable ip forwarding (cuts the target's traffic)   |

`Ctrl-C` restores both ARP caches and disables forwarding.

## How it works

```
CBPF (C shim)       BPF ioctls (BIOCSETIF/BIOCIMMEDIATE/BIOCSETF…), default
                    gateway via PF_ROUTE, single-instance process control.
ARPSpoofCore
  MACAddress/IPv4   address types + subnet math
  NetworkInterface  getifaddrs → MAC/IP/mask, active-interface detection
  RouteTable        default gateway, ip-forwarding (sysctl)
  ARPPacket         build/parse Ethernet+ARP frames
  BPFDevice         open /dev/bpfN, inject (write) and capture (poll+read)
  Bonjour/Hostname  device names via mDNS + reverse DNS
  SpoofEngine       multi-target, MAC→IP bindings, live re-targeting
netspoof (CLI)      scan / spoof / serve
NetKillUI (SwiftUI) device list, targeting, osascript privilege elevation
```

Poisoning: the target is told "`gatewayIP` is at my MAC" and the gateway is
told "`targetIP` is at my MAC"; both update their caches and traffic flows
through this Mac. With `ip.forwarding` on it is relayed transparently (MITM);
without it, the target loses connectivity.

The GUI (unprivileged) launches `netspoof serve` as root via an osascript admin
prompt and talks to it over a unix socket (JSON, line-delimited). No code
signing or Apple Developer ID is required — the trade-off versus
`SMAppService` is the password prompt on launch.

## License

MIT, with an authorized-use notice — see [`LICENSE`](LICENSE).

Русская версия README: [`README.ru.md`](README.ru.md).
