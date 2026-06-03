import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var baseURL = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AppMarkHeader()
                        .padding(.vertical, 4)
                }

                Section("帳號") {
                    LabeledContent("使用者", value: model.snapshot.username ?? "未登入")
                    LabeledContent("Token", value: model.isAuthenticated ? "UserDefaults 已儲存" : "未儲存")
                }

                Section("伺服器") {
                    TextField("Server URL", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    Button("儲存 Server URL") {
                        model.updateBaseURL(baseURL)
                    }
                }

                Section("同步狀態") {
                    LabeledContent("最後同步", value: lastSyncText)
                    Button {
                        Task {
                            await model.sync()
                        }
                    } label: {
                        if model.isSyncing {
                            ProgressView()
                        } else {
                            Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(model.isSyncing)
                }

                Section {
                    Button(role: .destructive) {
                        Task {
                            await model.logout()
                        }
                    } label: {
                        Label("登出", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("同步")
            .onAppear {
                baseURL = model.snapshot.baseURL
            }
        }
    }

    private var lastSyncText: String {
        guard model.snapshot.lastSyncAt > 0 else {
            return "尚未同步"
        }
        let date = Date(timeIntervalSince1970: TimeInterval(model.snapshot.lastSyncAt) / 1000)
        return date.formatted(date: .abbreviated, time: .standard)
    }
}
