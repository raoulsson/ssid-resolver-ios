# ssid-resolver-ios - "Get my Wi-Fi Name"

A standalone iOS app that resolves the SSID of the connected Wi-Fi network, or simply: "Get my
Wi-Fi Name". It uses the latest iOS APIs as of January 2026; the deployment target is iOS 15.6.

The app shows exactly which permissions an SSID lookup needs, names the missing one when a lookup
fails, and is the native proving ground for the
[Flutter plugin](https://github.com/raoulsson/ssid_resolver_flutter): run it here first, and the
platform layer is either cleared or convicted before you touch any Dart. Since 2.0 it also carries
`NetworkInterfaceResolver`, which reads the **real netmask** of every IPv4 interface - see
[the netmask and the broadcast address](#the-netmask-and-the-broadcast-address) below.

## What the SSID lookup needs

Everything is already declared in the project, so this is a map of where it lives rather than a
to-do list - and the exact set to replicate if you are wiring the same lookup into your own app:

- **The location usage strings** (`NSLocationWhenInUseUsageDescription` and
  `NSLocationAlwaysAndWhenInUseUsageDescription`) are build settings on the app target - the
  Info.plist is generated, there is no file to edit. iOS ties Wi-Fi identity to Location, so the
  user must also grant the Location prompt at runtime.
- **The `com.apple.developer.networking.wifi-info` entitlement** lives in
  `ssid-resolver-ios/ssid-resolver-ios.entitlements`, wired up via the target's
  "Access WiFi Information" capability under "Signing & Capabilities":

| Add WiFi Capability 1                                                              | Add WiFi Capability 2                                                              |
|------------------------------------------------------------------------------------|------------------------------------------------------------------------------------|
| <img src="res/add-wifi-capability-1.png" alt="Add WiFi Capability 1" width="400"/> | <img src="res/add-wifi-capability-2.png" alt="Add WiFi Capability 2" width="400"/> |

> [!WARNING]
> **The `wifi-info` entitlement cannot be provisioned by a personal development team.** To run on a
> device, open `ssid-resolver-ios.xcodeproj`, change the development team under
> "Signing & Capabilities" to your own **paid** Apple Developer team, and build - or the SSID half
> will not sign. The network interface half needs no entitlement and no runtime permission at all.

One neighbouring gate is worth knowing about even though this app never sends: iOS also has the
Multicast Networking Entitlement (`com.apple.developer.networking.multicast`) for apps that send
multicast or broadcast traffic. It is granted by describing your use case to Apple, not by paying
for a team - the Flutter plugin's README
[tells the three iOS gates apart](https://github.com/raoulsson/ssid_resolver_flutter#the-three-ios-gates-told-apart).

### What it looks like

The full permission path on a physical iPhone, left to right, top to bottom.

|                                                                                                                        |                                                                                                                                    |
|------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------|
| <img src="res/ios-1-nothing-granted.jpeg" alt="Nothing granted" width="400"/><br />**1.** Nothing granted yet - the SSID is simply unknown | <img src="res/ios-2-why-it-failed.jpeg" alt="Why it failed" width="400"/><br />**2.** Tapping Resolve says exactly what is missing: Location Access |
| <img src="res/ios-3-location-prompt.jpeg" alt="Location prompt" width="400"/><br />**3.** The OS prompt, explained by `NSLocationWhenInUseUsageDescription` | <img src="res/ios-5-ssid-resolved.jpeg" alt="SSID resolved" width="400"/><br />**4.** Resolved: `ZH1082Guest` |
| <img src="res/ios-6-network-interfaces.jpeg" alt="Network interfaces" width="400"/><br />**5.** Interfaces with real netmasks - no permission needed for this list | |

### When a lookup fails, the app tells you why - honestly

`NEHotspotNetwork.fetchCurrent()` returns `nil` for at least three reasons: no entitlement, no
Wi-Fi connection, or a network that withholds its name - which captive portals, enterprise and many
guest networks do. Before 2.0 the app reported every `nil` as a missing entitlement, so on a guest
network it sent you hunting for something you already had. It now attempts the real fetch and, when
that comes back empty, tells "not on Wi-Fi" apart from "on Wi-Fi, name withheld".

## The netmask and the broadcast address

While building the SSID part, a related thing turned out to be quietly broken almost everywhere,
and 2.0 solves it too: `NetworkInterfaceResolver` lists every IPv4 interface with its **real
netmask** and the broadcast address derived from it, via `getifaddrs`. No entitlement and no
runtime permission - nothing for the user to grant - so the list works even where Location is
denied and the SSID cannot be resolved at all.

Why it matters: without a netmask there is no way to compute a UDP broadcast address, and the usual
workaround - take the first three octets, append `.255` - is only correct on a `/24` and silently
wrong on anything **wider**. Wrong in the worst way: the send succeeds, nothing throws, and the
packet reaches nobody. On the `/20` in screenshot 5 above, `en0`'s real broadcast is `10.8.15.255`,
while the shortcut yields `10.8.2.255`: an ordinary unused host address that swallows everything
sent to it, with no error to go on.

The same screenshot shows `pdp_ip0`, cellular on a `/32`, where the derived broadcast equals the
interface's own address - which is why cellular has to be excluded from any list of broadcast
targets rather than merely looking odd. (Android cellular sits on a tiny point-to-point subnet
instead - a `/30` on the device in the sibling repo.)

## Related repositories

This app is the iOS source for a three-repo family. `NetworkInterfaceResolver.swift` in `src/core`
is kept in lockstep with the copy in the Flutter plugin - a fix here belongs there too, and vice
versa. `CoreSSIDResolver.swift` shares its approach with the plugin's copy but the two have diverged
in the details, so a fix there needs a look rather than a blind paste.

| | |
|---|---|
| **Flutter plugin** (published) | [ssid_resolver_flutter](https://github.com/raoulsson/ssid_resolver_flutter) - [pub.dev](https://pub.dev/packages/ssid_resolver_flutter) |
| **Android counterpart** | [ssid-resolver-android](https://github.com/raoulsson/ssid-resolver-android) |

Running the native app first is the fastest way to tell a platform bug from a Flutter channel bug:
if the value is right here and wrong in the plugin, the fault is in the Dart layer.

## Fixed in 2.0

- **A failed SSID lookup blamed the wrong thing** - the `fetchCurrent()` story above. The
  pre-flight "entitlement check" was itself a `fetchCurrent()` call, so it could only ever reach
  that one conclusion; it is gone rather than patched.
- **Four labels were invisible.** The SSID box, the permission status and both permission lists sit
  on light backgrounds inside a dark screen and had no explicit colour, so they inherited the
  screen's white. This rendered correctly under an older SwiftUI and rotted silently.
- **The app could not be built for a device.** It carries the `wifi-info` entitlement, which a
  personal development team cannot provision. Signing now uses a team that can.
- **`NetworkInterfaceResolver` added** - the netmask and broadcast API above.

# License

Copyright 2026 Raoul Marc Schmidiger (hello@raoulsson.com)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
