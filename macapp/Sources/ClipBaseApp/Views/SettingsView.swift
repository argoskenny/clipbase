import SwiftUI

struct SettingsView: View {
    @AppStorage("clipbase.apiBaseURL") private var apiBaseURL = "https://clipbase.thelonesomeera.com/"
    @AppStorage("clipbase.username") private var username = ""

    var body: some View {
        TabView {
            Form {
                TextField("API Base URL", text: $apiBaseURL)
                TextField("預設帳號", text: $username)
                Text("Bearer token 儲存在 macOS Keychain。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .tabItem {
                Label("同步", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .frame(width: 480, height: 220)
    }
}
