import SwiftUI

struct SSIDResolverView: View {
    @StateObject private var viewModel = SSIDResolverViewModel()
    @State private var isLoading = false
    
    private let orangeColor = Color(hex: "FFA500")
    private let bgColor = Color(hex: "2A4683")
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Top margin
                Spacer()
                    .frame(height: 24)
                
                // Title
                Text("WiFi SSID Resolver")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(orangeColor)
                
                Text("iOS")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(orangeColor)
                
                // SSID Result
                Text(viewModel.ssid)
                    .font(.system(size: 30))
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color(hex: "E0E0E0"))
                    .padding(.top, 12)
                
                // Resolve Button
                Button(action: {
                    isLoading = true
                    Task {
                        await viewModel.fetchSSID()
                        isLoading = false
                    }
                }) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Resolve SSID")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .frame(height: 48)
                    }
                }
                .frame(minWidth: 200)
                .background(isLoading ? Color(hex: "C0C0C0") : orangeColor)
                .cornerRadius(4)
                .disabled(isLoading)
                .padding(.top, 16)
                
                // Divider
                Rectangle()
                    .fill(orangeColor)
                    .frame(height: 1)
                    .padding(.vertical, 16)
                
                // Permission Status
                Text(viewModel.permissionStatus)
                    .font(.system(size: 22))
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color(hex: "E0E0E0"))
                
                // Error Message
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(6)
                        .background(Color(hex: "FFE0E0"))
                }
                
                // Permission Button
                Button(action: {
                    viewModel.requestPermission() // Only request when button clicked
                }) {
                    Text("Request Location Permissions")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .frame(height: 48)
                }
                .frame(minWidth: 200)
                .background(isLoading ? Color(hex: "C0C0C0") : orangeColor)
                .cornerRadius(4)
                .disabled(isLoading)
                .padding(.top, 16)
                
                // Permissions Lists
                Group {
                    // Granted Permissions
                    HStack {
                        Text("Granted Permissions:")
                            .foregroundColor(.white)
                            .font(.system(size: 18, weight: .bold))
                        Spacer()
                    }
                    .padding(.top, 16)
                    
                    Text(viewModel.grantedPermissions.values.joined(separator: "\n"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(Color(hex: "C8E6C9"))
                    
                    // Denied Permissions
                    HStack {
                        Text("Denied Permissions:")
                            .foregroundColor(.white)
                            .font(.system(size: 18, weight: .bold))
                        Spacer()
                    }
                    .padding(.top, 12)
                    
                    Text(viewModel.deniedPermissions.values.joined(separator: "\n"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(Color(hex: "FFCDD2"))
                }
            }
            .padding(12)
        }
        .background(bgColor)
        .task {
            await viewModel.checkPermissionStatus()
        }
    }
}

// Helper for hex colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
