import Foundation
import CoreLocation
import NetworkExtension

class MissingPermissionException: Error {
    let missingPermissions: [String]
    
    init(_ missingPermissions: [String]) {
        self.missingPermissions = missingPermissions
    }
    
    var localizedDescription: String {
        return "Aborting fetchSSID to prevent potential crash. Missing permissions for: \(missingPermissions.joined(separator: ", "))"
    }
}

enum SSIDResolverError: Error {
    case noWifiConnection
    case ssidWithheld
    case unknown

    var localizedDescription: String {
        switch self {
        case .noWifiConnection:
            return "Not connected to any WiFi network"
        case .ssidWithheld:
            // fetchCurrent() returning nil while WiFi is plainly up has more
            // than one cause, and the old code reported the entitlement as
            // fact. Naming all three is the honest answer, and on a commercial
            // or captive network the entitlement is often not the reason.
            return "Connected to WiFi, but iOS did not return the network name. "
                + "This needs the Access WiFi Information entitlement; captive, "
                + "enterprise and some guest networks also withhold it."
        case .unknown:
            return "Unknown error occurred while fetching WiFi information"
        }
    }
}


class CoreSSIDResolver: NSObject, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()
    private var permissionCompletion: ((Result<Bool, Error>) -> Void)?
    private(set) var ssid: String?
    var isLocationPermissionGranted: Bool = false
    
    override init() {
        super.init()
        print("CoreSSIDResolver: Initializing")
        locationManager.delegate = self
    }
    
    func requestLocationPermission(completion: @escaping (Result<Bool, Error>) -> Void) async {
        print("CoreSSIDResolver: Starting permission request")
        
        permissionCompletion = completion
        let status = locationManager.authorizationStatus
        
        switch status {
        case .notDetermined:
            print("CoreSSIDResolver: Status not determined, requesting permission")
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            print("CoreSSIDResolver: Permission denied")
            completion(.failure(MissingPermissionException(["Location Access"])))
        case .authorizedWhenInUse, .authorizedAlways:
            print("CoreSSIDResolver: Already authorized")
            completion(.success(true))
        @unknown default:
            print("CoreSSIDResolver: Unknown status")
            completion(.failure(SSIDResolverError.unknown))
        }
    }
    
    /** This will only work with the location permissions. Thus the funky Task domino in the ViewModel */
    func checkAccessWiFiEntitlement() async -> Bool {
        let network: NEHotspotNetwork? = await NEHotspotNetwork.fetchCurrent()
        if(network != nil) {
            return true
        }
        return false
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        print("CoreSSIDResolver: Authorization changed to: \(manager.authorizationStatus.debugDescription)")
        
        if let completion = permissionCompletion {
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                print("CoreSSIDResolver: Permission granted")
                completion(.success(true))
            case .restricted, .denied:
                print("CoreSSIDResolver: Permission denied")
                completion(.failure(MissingPermissionException(["Location Access"])))
            case .notDetermined:
                print("CoreSSIDResolver: Still not determined")
                // Don't call completion yet
                return
            @unknown default:
                print("CoreSSIDResolver: Unknown status in callback")
                completion(.failure(SSIDResolverError.unknown))
            }
        }
        permissionCompletion = nil
        
        Task {
            isLocationPermissionGranted = await checkAccessWiFiEntitlement()
        }
        
    }
    
    func fetchSSID() async throws -> String {
        print("CoreSSIDResolver: Fetching SSID")
        
        var missingPermissions: [String] = []
        
        // Check location permission
        if ![.authorizedWhenInUse, .authorizedAlways].contains(locationManager.authorizationStatus) {
            missingPermissions.append("Location Access")
        }
        
        // Location is the one cause we can actually observe, so it stays a
        // hard precondition. Everything else is diagnosed after the attempt.
        if !missingPermissions.isEmpty {
            print("CoreSSIDResolver: Missing permissions: \(missingPermissions.joined(separator: ", "))")
            throw MissingPermissionException(missingPermissions)
        }

        guard let currentNetwork = await NEHotspotNetwork.fetchCurrent() else {
            // Distinguish "no WiFi" from "WiFi up but name withheld" by asking
            // the interface table, which needs no permission at all. Without
            // this the user is told a permission is missing when the real cause
            // may be the network they are standing on.
            let onWifi = NetworkInterfaceResolver.fetchAll().contains { iface in
                iface.name.hasPrefix("en")
                    && !iface.ip.hasPrefix("169.254.")
                    && !iface.ip.hasPrefix("127.")
            }
            print("CoreSSIDResolver: fetchCurrent returned nil, wifi interface up: \(onWifi)")
            throw onWifi ? SSIDResolverError.ssidWithheld : SSIDResolverError.noWifiConnection
        }
        
        print("CoreSSIDResolver: Successfully got SSID: \(currentNetwork.ssid)")
        self.ssid = currentNetwork.ssid
        return currentNetwork.ssid
    }
    
    // Optional: Add method to get additional network info if needed
    func fetchNetworkInfo() async throws -> NetworkInfo {
        guard let network = await NEHotspotNetwork.fetchCurrent() else {
            throw SSIDResolverError.noWifiConnection
        }
        
        return NetworkInfo(
            ssid: network.ssid,
            bssid: network.bssid,
            signalStrength: network.signalStrength
        )
    }
}

// Optional: Structure for additional network information
struct NetworkInfo {
    let ssid: String
    let bssid: String
    let signalStrength: Double // -1.0 to 1.0
}

extension CLAuthorizationStatus {
    var debugDescription: String {
        switch self {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedAlways: return "authorizedAlways"
        case .authorizedWhenInUse: return "authorizedWhenInUse"
        @unknown default: return "unknown"
        }
    }
}
