import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: ClipBaseStore
    @State private var selectedFeature: AppFeature? = .clips

    var body: some View {
        Group {
            switch store.authState {
            case .checking:
                ProgressView("載入中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unauthenticated:
                LoginView(store: store)
            case .authenticated:
                appShell
            }
        }
        .task {
            await store.bootstrap()
        }
        .alert(item: $store.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private var appShell: some View {
        NavigationSplitView {
            List(selection: $selectedFeature) {
                Section {
                    ForEach(AppFeature.allCases) { feature in
                        NavigationLink(value: feature) {
                            FeatureRow(feature: feature, detail: detailText(for: feature))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("ClipBase")
        } detail: {
            switch selectedFeature ?? .clips {
            case .clips:
                ClipLibraryView(store: store)
            case .optimizers:
                PromptOptimizersView(store: store)
            case .memos:
                MemoDocumentsView(store: store)
            }
        }
        .removeDefaultSidebarToggleIfAvailable()
        .toolbar {
            if #available(macOS 26.0, *) {
                DefaultToolbarItem(kind: .sidebarToggle, placement: .navigation)
            } else {
                ToolbarItem(placement: .navigation) {
                    Button {
                        toggleSidebar()
                    } label: {
                        Label("顯示或隱藏側邊欄", systemImage: "sidebar.left")
                    }
                    .help("顯示或隱藏側邊欄")
                }
            }

            ToolbarItemGroup {
                Button {
                    Task { await store.syncNow() }
                } label: {
                    Label(store.isSyncing ? "同步中" : "同步", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(store.isSyncing)
                .help(store.syncMessage)

                Menu {
                    Button("匯入 CSV...") { store.openCSVImportPanel() }
                    Button("匯出 CSV...") { store.openCSVExportPanel() }
                    Divider()
                    Button("匯出完整備份...") { store.openBackupExportPanel() }
                    Button("還原完整備份...") { store.openBackupRestorePanel() }
                } label: {
                    Label("檔案", systemImage: "folder")
                }

                Button {
                    Task { await store.logout() }
                } label: {
                    Label("登出", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
    }

    private func detailText(for feature: AppFeature) -> String {
        switch feature {
        case .clips:
            let itemCount = store.items.filter { $0.deletedAt == nil }.count
            return "\(store.sections.count) 分類 / \(itemCount) 項"
        case .optimizers:
            return "\(store.optimizers.count) 個模板"
        case .memos:
            return "\(store.memoDocuments.count) 份文件"
        }
    }
}

private func toggleSidebar() {
    NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
}

private extension View {
    @ViewBuilder
    func removeDefaultSidebarToggleIfAvailable() -> some View {
        if #available(macOS 14.0, *) {
            toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}

private struct FeatureRow: View {
    let feature: AppFeature
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: feature.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
