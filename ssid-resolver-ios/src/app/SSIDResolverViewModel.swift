import Foundation
import CoreLocation
import NetworkExtension

@MainActor
class SSIDResolverViewModel: ObservableObject {
    private let coreResolver = CoreSSIDResolver()
    @Published var ssid: String = "Unknown SSID Status"
    @Published var permissionStatus: String = "Unknown Permission Status"
    @Published var errorMessage: String?
    @Published var grantedPermissions: [String: String] = [:]
    @Published var deniedPermissions: [String: String] = [:]

    private let requiredPermissions = [
        "Location (When In Use)",
        "Access WiFi Information"
    ]

    func checkPermissionStatus() async {
        // Check location status (without requesting)
        let locationStatus = coreResolver.locationManager.authorizationStatus
        updateLocPermissionInLists(locationStatus: locationStatus)
        
        // Check WiFi only if location is granted
        if [.authorizedWhenInUse, .authorizedAlways].contains(locationStatus) {
            let hasWiFi = await coreResolver.checkAccessWiFiEntitlement()
            // We're already on @MainActor so this is safe
            updateWifiPermissionInLists(hasWiFiEntitlement: hasWiFi)
        } else {
            updateWifiPermissionInLists(hasWiFiEntitlement: false)
        }
    }
    

    private func updatePermissionStatus() {
        if deniedPermissions.isEmpty {
            permissionStatus = "All permissions granted"
        } else if grantedPermissions.isEmpty {
            permissionStatus = "All permissions denied"
        } else {
            permissionStatus = "Some permissions denied"
        }
    }
    
    private func updateLocPermissionInLists(locationStatus: CLAuthorizationStatus) {
        let locationGranted = [CLAuthorizationStatus.authorizedWhenInUse,
                             CLAuthorizationStatus.authorizedAlways]
            .contains(locationStatus)
        
        if locationGranted {
            grantedPermissions["loc"] = "Location (When In Use)"
            deniedPermissions["loc"] = nil
        } else {
            grantedPermissions["loc"] = nil
            deniedPermissions["loc"] = "Location (When In Use)"
        }
        
        updatePermissionStatus()
    }
    
    private func updateWifiPermissionInLists(hasWiFiEntitlement: Bool) {
        if hasWiFiEntitlement {
            grantedPermissions["wifi"] = "Access WiFi Information"
            deniedPermissions["wifi"] = nil
        } else {
            grantedPermissions["wifi"] = nil
            deniedPermissions["wifi"] = "Access WiFi Information"
        }
        
        updatePermissionStatus()
    }
    
    func requestPermission() {
        Task {
            await coreResolver.requestLocationPermission { [weak self] result in
                guard let self = self else { return }
                
                // First handle location permission on main thread
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self.updateLocPermissionInLists(
                            locationStatus: self.coreResolver.locationManager.authorizationStatus
                        )
                        self.errorMessage = nil
                        
                        // After location is handled, check WiFi in a new Task. Only works if location permissions are given.
                        Task { @MainActor in
                            let hasWiFi = await self.coreResolver.checkAccessWiFiEntitlement()
                            // This will now run on main thread
                            self.updateWifiPermissionInLists(hasWiFiEntitlement: hasWiFi)
                            if !self.deniedPermissions.isEmpty {
                                self.errorMessage = "Missing permissions: \(self.deniedPermissions.values.joined(separator: ", "))"
                            }
                        }
                        
                    case .failure(let error):
                        self.updateLocPermissionInLists(
                            locationStatus: self.coreResolver.locationManager.authorizationStatus
                        )
                        if !self.deniedPermissions.isEmpty {
                            self.errorMessage = "Missing permissions: \(self.deniedPermissions.values.joined(separator: ", "))"
                        } else if let permissionError = error as? MissingPermissionException {
                            self.errorMessage = permissionError.localizedDescription
                        } else {
                            self.errorMessage = error.localizedDescription
                        }
                        // If location failed, WiFi will be false
                        self.updateWifiPermissionInLists(hasWiFiEntitlement: false)
                    }
                }
            }
        }
    }

    func fetchSSID() async {
        do {
            let fetchedSSID = try await coreResolver.fetchSSID()
            ssid = fetchedSSID
            errorMessage = nil
        } catch let permissionError as MissingPermissionException {
            // Handle the specific permission exception
            ssid = "Unknown"
            errorMessage = permissionError.localizedDescription
        } catch {
            // Handle any other errors
            ssid = "Unknown"
            let nsError = error as NSError
            errorMessage = nsError.localizedDescription
        }
    }
    
}
