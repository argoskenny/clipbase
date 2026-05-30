import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.isAuthenticated {
                TabView {
                    ClipLibraryView()
                        .tabItem {
                            Label("剪貼內容", systemImage: "list.bullet.rectangle")
                        }
                    PromptOptimizersView()
                        .tabItem {
                            Label("提示詞", systemImage: "wand.and.stars")
                        }
                    MemoDocumentsView()
                        .tabItem {
                            Label("備忘", systemImage: "doc.text")
                        }
                    SettingsView()
                        .tabItem {
                            Label("同步", systemImage: "arrow.triangle.2.circlepath")
                        }
                }
            } else {
                LoginView()
            }
        }
        .alert("錯誤", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("好", role: .cancel) {
                model.clearError()
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .overlay(alignment: .bottom) {
            if let notice = model.notice {
                Text(notice)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 18)
                    .task(id: notice) {
                        try? await Task.sleep(for: .seconds(1.5))
                        model.clearNotice()
                    }
            }
        }
    }
}

private struct LoginView: View {
    @EnvironmentObject private var model: AppModel
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Image("AppMark")
                        .resizable()
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Text("ClipBase")
                        .font(.largeTitle.weight(.semibold))
                    Text("剪貼資料庫、提示詞優化器與備忘文件")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
            .listRowBackground(Color.clear)

            Section("登入") {
                TextField("帳號", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("密碼", text: $password)
                Button {
                    Task {
                        await model.login(baseURL: ClipBaseSnapshot.defaultBaseURL, username: username, password: password)
                    }
                } label: {
                    if model.isSyncing {
                        ProgressView()
                    } else {
                        Text("登入")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(model.isSyncing || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
            }
        }
        .onAppear {
            username = model.snapshot.username ?? ""
        }
    }
}

struct EmptyStateView: View {
    var title: String
    var message: String
    var systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(configuration.isPressed ? Color.accentColor.opacity(0.72) : Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SectionHeaderCount: View {
    var title: String
    var count: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(count)")
                .foregroundStyle(.secondary)
        }
    }
}

struct DestructiveTrashButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Label(title, systemImage: "trash")
        }
    }
}

struct CopyButton: View {
    var title: String = "複製"
    var text: String
    var onCopied: (() -> Void)?

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            onCopied?()
        } label: {
            Label(title, systemImage: "doc.on.doc")
        }
    }
}

struct LabeledTextEditor: View {
    var title: String
    @Binding var text: String
    var minHeight: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            TextEditor(text: $text)
                .frame(minHeight: minHeight)
                .padding(6)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct AppMarkHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Image("AppMark")
                .resizable()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text("ClipBase")
                .font(.headline)
        }
    }
}
