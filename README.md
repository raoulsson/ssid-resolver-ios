# ssid-resolver-ios - "Get my Wi-Fi Name" 

A standalone app to resolve the SSID of the connected Wi-Fi network on iOS, or simply: "Get my Wi-Fi Name". This implementation uses the
latest iOS APIs as of January 2026; the app target's deployment target is iOS 15.6.

**Reading the Wi-Fi SSID on iOS, and the netmask Dart and Swift apps usually guess.**
A standalone iOS app showing exactly which permissions an SSID lookup needs, plus
`NetworkInterfaceResolver`: every IPv4 interface with its **real netmask** and the **broadcast
address** derived from it, via `getifaddrs`, with **no entitlement and no runtime permission** -
nothing for the user to grant. SSID resolution is the part that needs both. If your code
builds a UDP broadcast address as "first three octets + `.255`", it is silently wrong on anything
wider than a `/24`, and it fails without an error.

> [!WARNING]
> **The `wifi-info` entitlement cannot be provisioned by a personal development team.** Building this
> app for a device needs a paid Apple Developer team, or the SSID half will not sign. The network
> interface half needs no entitlement and no runtime permission at all.

> [!IMPORTANT]
> **2.0 - the delta, in two parts.**
>
> **It tells you the truth about a failed SSID lookup.** `fetchCurrent()` returning `nil` used to be
> reported as a missing entitlement every time. It has at least three causes, and on a guest or
> captive network the entitlement is usually not the one - so it sent you hunting for something you
> already had.
>
> **And it can read the real netmask**, so a broadcast address is derived rather than guessed. The
> universal guess - first three octets plus `.255` - is correct on a `/24` and silently wrong on the
> `/20`, `/22` and `/16` that corporate, campus and guest networks hand out. Wrong in the worst way:
> the send succeeds, nothing throws, the packet reaches nobody. Needs no entitlement and no
> runtime permission. [The details, with the numbers](#the-netmask-problem-in-detail).

## Fixed in 2.0

- **A failed SSID lookup blamed the wrong thing.** `NEHotspotNetwork.fetchCurrent()` returning `nil`
  was reported as a missing Access WiFi Information entitlement every time. It returns `nil` for at
  least three reasons - no entitlement, no Wi-Fi connection, or a network that withholds its name -
  so on a guest network it sent you looking for an entitlement you already had. The pre-flight
  "entitlement check" was itself a `fetchCurrent()` call and could only ever reach that conclusion.
- **Four labels were invisible.** The SSID box, the permission status and both permission lists sit on
  light backgrounds inside a dark screen and had no explicit colour, so they inherited the screen's
  white. This rendered correctly under an older SwiftUI and rotted silently.
- **The app could not be built for a device.** It carries the `wifi-info` entitlement, which a
  personal development team cannot provision. Signing now uses a team that can.

## Related repositories

This app is the iOS source for a three-repo family. `NetworkInterfaceResolver.swift` in `src/core`
is kept in lockstep with the copy in the Flutter plugin - a fix here belongs there too, and vice
versa. `CoreSSIDResolver.swift` shares its approach with the plugin's copy but the two have diverged
in the details, so a fix there needs a look rather than a blind paste.

| | |
|---|---|
| **Flutter plugin** (published) | [ssid_resolver_flutter](https://github.com/raoulsson/ssid_resolver_flutter) - [pub.dev](https://pub.dev/packages/ssid_resolver_flutter) |
| **Android counterpart** | [ssid-resolver-android](https://github.com/raoulsson/ssid-resolver-android) |

Running the native app first is the fastest way to tell a platform bug from a Flutter channel bug: if
the value is right here and wrong in the plugin, the fault is in the Dart layer.

## Quick Info

A small standalone app that resolves the SSID of the connected Wi-Fi network on iOS. It is the
native proving ground for the Flutter plugin and stays that way: run it here first, and the platform
layer is either cleared or convicted before you touch any Dart.

### What it looks like

The full permission path on a physical iPhone, left to right, top to bottom.

|                                                                                                                        |                                                                                                                                    |
|------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------|
| <img src="res/ios-1-nothing-granted.jpeg" alt="Nothing granted" width="400"/><br />**1.** Nothing granted yet - the SSID is simply unknown | <img src="res/ios-2-why-it-failed.jpeg" alt="Why it failed" width="400"/><br />**2.** Tapping Resolve says exactly what is missing: Location Access |
| <img src="res/ios-3-location-prompt.jpeg" alt="Location prompt" width="400"/><br />**3.** The OS prompt, explained by `NSLocationWhenInUseUsageDescription` | <img src="res/ios-5-ssid-resolved.jpeg" alt="SSID resolved" width="400"/><br />**4.** Resolved: `ZH1082Guest` |
| <img src="res/ios-6-network-interfaces.jpeg" alt="Network interfaces" width="400"/><br />**5.** Interfaces with real netmasks - no permission needed for this list | |

The interface list is worth a second look. `en0` is on a `/20`, so its broadcast is `10.8.15.255` and not
the `10.8.2.255` a `.255` shortcut would produce. `pdp_ip0` is cellular on a `/32`, where the derived
broadcast equals the interface's own address - which is why cellular has to be excluded from any list
of broadcast targets rather than merely looking odd.

## The netmask problem in detail

A failed lookup used to blame one thing every time. `NEHotspotNetwork.fetchCurrent()` returning `nil`
was treated as proof that the Access WiFi Information entitlement was missing.

It returns `nil` for at least three reasons: no entitlement, no Wi-Fi connection, or a network that
withholds its name - which captive portals, enterprise and many guest networks do. So on a guest
network the app sent you hunting for an entitlement you already had. It now attempts the real fetch
and, when that comes back empty, tells "not on Wi-Fi" apart from "on Wi-Fi, name withheld".

Version 2.0 also adds `NetworkInterfaceResolver`: every IPv4 interface with its **real netmask** and
the broadcast derived from it. `getifaddrs` needs no entitlement and no runtime permission, so the list works
even where Location is denied and the SSID cannot be resolved at all.

That matters because without a netmask there is no way to compute a broadcast address, and the usual
workaround - first three octets plus `.255` - is only correct on a `/24`. On the `/20` in the
screenshots above the real broadcast is `10.8.15.255`, while the shortcut yields `10.8.2.255`: an
ordinary unused host address that silently swallows everything sent to it.

## Building and signing

Open `ssid-resolver-ios.xcodeproj` in Xcode. Everything the SSID lookup needs is already declared in
the project, so this section is a map of where it lives rather than a to-do list:

- The location usage strings (`NSLocationWhenInUseUsageDescription` and
  `NSLocationAlwaysAndWhenInUseUsageDescription`) are build settings on the app target - the
  Info.plist is generated, there is no file to edit.
- The `com.apple.developer.networking.wifi-info` entitlement lives in
  `ssid-resolver-ios/ssid-resolver-ios.entitlements`, wired up via the target's
  "Access WiFi Information" capability under "Signing & Capabilities":

| Add WiFi Capability 1                                                              | Add WiFi Capability 2                                                              |
|------------------------------------------------------------------------------------|------------------------------------------------------------------------------------|
| <img src="res/add-wifi-capability-1.png" alt="Add WiFi Capability 1" width="400"/> | <img src="res/add-wifi-capability-2.png" alt="Add WiFi Capability 2" width="400"/> |      

To run on a device, change the development team under "Signing & Capabilities" to your own paid
team - as the warning at the top says, a free personal team cannot provision the wifi-info
entitlement. If you are wiring the same lookup into your own app, these are exactly the pieces to
replicate: the two usage strings, the capability, and a deployment target of iOS 15.6 or later.

# License

Copyright 2026 Raoul Marc Schmidiger (hello@raoulsson.com)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
