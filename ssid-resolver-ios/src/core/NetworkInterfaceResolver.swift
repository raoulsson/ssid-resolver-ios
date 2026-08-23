import Foundation
import os.log

// One IPv4 interface as reported by getifaddrs. Netmask is carried explicitly
// because Dart's NetworkInterface has no way to obtain it, which is the whole
// reason this file exists: broadcast addresses computed as "first three
// octets + .255" are wrong on any network that is not a /24.
struct NetworkInterfaceInfo {
    let name: String
    let ip: String
    let netmask: String
    let broadcast: String
    let prefixLength: Int

    var asDictionary: [String: Any] {
        [
            "name": name,
            "ip": ip,
            "netmask": netmask,
            "broadcast": broadcast,
            "prefixLength": prefixLength
        ]
    }
}

// Enumerates IPv4 interfaces via getifaddrs(3). No entitlement and no
// permission is required for this call, unlike SSID lookup - it must keep
// working even when the user has denied Location.
// Kept in lockstep with the copy in ssid_resolver_flutter's iOS plugin.
enum NetworkInterfaceResolver {
    static func fetchAll() -> [NetworkInterfaceInfo] {
        var results: [NetworkInterfaceInfo] = []

        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else {
            // The caller gets an empty list either way. Without this line an
            // outright syscall failure is indistinguishable from a machine with
            // no network, and the two need very different fixes.
            os_log("getifaddrs failed (errno %d), reporting no interfaces", log: .default, type: .error, errno)
            return results
        }
        // getifaddrs hands out a linked list we own; freeifaddrs must run on
        // every exit path or the list leaks.
        defer { freeifaddrs(ifaddrPtr) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let interface = cursor {
            defer { cursor = interface.pointee.ifa_next }

            let addrFamily = interface.pointee.ifa_addr?.pointee.sa_family
            guard addrFamily == UInt8(AF_INET) else { continue }

            // ifa_netmask can be nil for some interface entries. Falling back
            // to /24 here would silently reintroduce the bug this file
            // exists to remove, so skip the entry instead.
            guard let netmaskAddr = interface.pointee.ifa_netmask else {
                os_log("skipping %{public}s: no netmask reported", log: .default, type: .info,
                       String(cString: interface.pointee.ifa_name))
                continue
            }
            guard let ipAddr = interface.pointee.ifa_addr else { continue }

            guard let ipValue = ipv4Value(from: ipAddr),
                  let maskValue = ipv4Value(from: netmaskAddr) else {
                os_log("skipping %{public}s: address could not be read as IPv4", log: .default, type: .info,
                       String(cString: interface.pointee.ifa_name))
                continue
            }

            let name = String(cString: interface.pointee.ifa_name)
            let broadcastValue = (ipValue & maskValue) | ~maskValue

            // Prefix length is the count of LEADING one bits, not the popcount:
            // a non-contiguous mask like 255.255.0.255 has 24 bits set but only
            // 16 leading ones, and reporting 24 would lie about the network.
            let prefix = (~maskValue).leadingZeroBitCount
            if maskValue != contiguousMask(prefixLength: prefix) {
                // Keep the interface - the broadcast above is still computed
                // from the real mask - but leave a trace, because a mask like
                // this means something unusual about the network setup.
                os_log("interface %{public}s has non-contiguous netmask %{public}s, reporting prefix /%d from its leading ones",
                       log: .default, type: .error, name, dottedString(from: maskValue), prefix)
            }

            results.append(
                NetworkInterfaceInfo(
                    name: name,
                    ip: dottedString(from: ipValue),
                    netmask: dottedString(from: maskValue),
                    broadcast: dottedString(from: broadcastValue),
                    prefixLength: prefix
                )
            )
        }

        if results.isEmpty {
            os_log("no IPv4 interfaces found", log: .default, type: .error)
        }
        return results
    }

    // Extracts the 32-bit address in host byte order so bitwise mask math
    // below works the same way regardless of the machine's endianness.
    // ifa_addr/ifa_netmask are typed as sockaddr but the underlying storage
    // for an AF_INET entry is sockaddr_in - on Darwin both are 16 bytes, so
    // rebinding is safe and avoids a manual byte copy.
    private static func ipv4Value(from sockaddrPtr: UnsafeMutablePointer<sockaddr>) -> UInt32? {
        var result: UInt32?
        sockaddrPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { addrInPtr in
            result = UInt32(bigEndian: addrInPtr.pointee.sin_addr.s_addr)
        }
        return result
    }

    // The mask a well-formed /prefix would have; comparing against it is how a
    // non-contiguous mask is detected. Shifting a UInt32 by 32 traps in Swift,
    // so the zero-prefix case is explicit.
    private static func contiguousMask(prefixLength: Int) -> UInt32 {
        prefixLength <= 0 ? 0 : ~UInt32(0) << (32 - prefixLength)
    }

    private static func dottedString(from value: UInt32) -> String {
        let b0 = (value >> 24) & 0xFF
        let b1 = (value >> 16) & 0xFF
        let b2 = (value >> 8) & 0xFF
        let b3 = value & 0xFF
        return "\(b0).\(b1).\(b2).\(b3)"
    }
}
