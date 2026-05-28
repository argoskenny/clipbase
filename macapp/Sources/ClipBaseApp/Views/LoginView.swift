import AppKit
import SwiftUI

struct LoginView: View {
    @ObservedObject var store: ClipBaseStore
    @State private var username = ""
    @State private var password = ""
    @State private var isSubmitting = false

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)
                    .cornerRadius(18)
                Text("ClipBase")
                    .font(.largeTitle.bold())
                Text("剪貼資料庫、提示詞優化器與備忘文件")
                    .foregroundStyle(.secondary)
            }

            Form {
                TextField("帳號", text: $username)
                    .textFieldStyle(.roundedBorder)
                SecureField("密碼", text: $password)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task {
                        isSubmitting = true
                        await store.login(username: username, password: password)
                        isSubmitting = false
                    }
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isSubmitting ? "登入中..." : "登入")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
            }
            .formStyle(.grouped)
            .frame(width: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear {
            username = store.savedUsername
        }
    }
}
