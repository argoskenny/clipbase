import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ClipBaseStore: ObservableObject {
    enum AuthState: Equatable {
        case checking
        case unauthenticated
        case authenticated(username: String?)
    }

    @Published private(set) var authState: AuthState = .checking
    @Published private(set) var sections: [ClipSection] = []
    @Published private(set) var items: [ClipItem] = []
    @Published private(set) var optimizers: [PromptOptimizer] = []
    @Published private(set) var memoDocuments: [MemoDocument] = []
    @Published private(set) var lastSyncAt: Int64 = 0
    @Published private(set) var syncMessage = "尚未同步"
    @Published private(set) var isSyncing = false
    @Published var alert: UserFacingAlert?

    private let repository: LocalRepository
    private let tokenStore: TokenStoring
    private let apiClient: ClipBaseAPIClient
    private let defaults: UserDefaults
    private var bootstrapped = false
    private var pendingSync = false
    private var localChangeGeneration: UInt64 = 0
    private var authGeneration: UInt64 = 0

    init(
        repository: LocalRepository = LocalRepository(),
        tokenStore: TokenStoring = KeychainTokenStore(),
        apiClient: ClipBaseAPIClient = ClipBaseAPIClient(),
        defaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.tokenStore = tokenStore
        self.apiClient = apiClient
        self.defaults = defaults
        refreshPublishedState()
    }

    var apiBaseURL: String {
        get { defaults.string(forKey: DefaultsKey.apiBaseURL) ?? DefaultsKey.defaultBaseURL }
        set { defaults.set(newValue, forKey: DefaultsKey.apiBaseURL) }
    }

    var savedUsername: String {
        get { defaults.string(forKey: DefaultsKey.username) ?? "" }
        set { defaults.set(newValue, forKey: DefaultsKey.username) }
    }

    private var lastAuthenticatedBaseURL: String {
        get { defaults.string(forKey: DefaultsKey.lastAuthenticatedBaseURL) ?? "" }
        set { defaults.set(newValue, forKey: DefaultsKey.lastAuthenticatedBaseURL) }
    }

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true

        do {
            if try tokenStore.loadToken() == nil {
                authState = .unauthenticated
                return
            }
        } catch {
            authState = .unauthenticated
            showError(error, fallback: "無法讀取登入狀態")
            return
        }

        authState = .authenticated(username: savedUsername.isEmpty ? nil : savedUsername)
        await syncNow(showSuccess: false)
    }

    func login(baseURL: String, username: String, password: String) async {
        do {
            alert = nil
            let normalizedBaseURL = ClipBaseAPIClient.normalizedBaseURL(baseURL)
            let response = try await apiClient.login(baseURL: normalizedBaseURL, username: username, password: password)
            guard let token = response.token else {
                throw APIError.message("伺服器未回傳 Bearer token")
            }

            if lastAuthenticatedBaseURL != normalizedBaseURL {
                try repository.resetAll()
            }

            try tokenStore.saveToken(token)
            authGeneration &+= 1
            apiBaseURL = normalizedBaseURL
            savedUsername = response.username
            lastAuthenticatedBaseURL = normalizedBaseURL
            authState = .authenticated(username: response.username)
            refreshPublishedState()
            await syncNow(showSuccess: true)
        } catch {
            showError(error, fallback: "登入失敗")
        }
    }

    func login(username: String, password: String) async {
        await login(baseURL: DefaultsKey.defaultBaseURL, username: username, password: password)
    }

    func logout() async {
        authGeneration &+= 1
        pendingSync = false
        alert = nil
        if let token = try? tokenStore.loadToken() {
            await apiClient.logout(baseURL: apiBaseURL, token: token)
        }
        try? tokenStore.deleteToken()
        authState = .unauthenticated
    }

    func syncNow(showSuccess: Bool = true) async {
        guard !isSyncing else {
            pendingSync = true
            return
        }

        let token: String
        let authGenerationAtStart: UInt64
        do {
            guard let loadedToken = try tokenStore.loadToken() else {
                authState = .unauthenticated
                return
            }
            token = loadedToken
            authGenerationAtStart = authGeneration
        } catch {
            authState = .unauthenticated
            syncMessage = "同步失敗"
            showError(error, fallback: "無法讀取登入狀態")
            return
        }

        isSyncing = true
        syncMessage = "同步中..."
        defer {
            isSyncing = false
            if pendingSync {
                pendingSync = false
                Task { await syncNow(showSuccess: false) }
            }
        }

        do {
            let generationAtStart = localChangeGeneration
            let since = repository.lastSyncAt
            let changes = repository.localChanges(after: since)
            let response: ClipBaseAPIClient.SyncResponse
            if changes.isEmpty {
                response = try await apiClient.pullSync(baseURL: apiBaseURL, token: token, since: since)
            } else {
                response = try await apiClient.sync(baseURL: apiBaseURL, token: token, since: since, changes: changes)
            }
            guard authGenerationAtStart == authGeneration else {
                return
            }
            let changedDuringSync = localChangeGeneration != generationAtStart
            try repository.applyRemoteChanges(
                response.changes,
                serverTime: response.serverTime,
                preserveLastSyncAt: changedDuringSync
            )
            if changedDuringSync {
                pendingSync = true
            }
            refreshPublishedState()
            syncMessage = "已同步 \(formatSyncTime(response.serverTime))"
            if showSuccess {
                flash(title: "同步完成", message: "本機與 Web 已完成同步")
            }
        } catch APIError.unauthorized {
            guard shouldHandleUnauthorized(token: token, authGenerationAtStart: authGenerationAtStart) else {
                return
            }
            try? tokenStore.deleteToken()
            authGeneration &+= 1
            authState = .unauthenticated
            syncMessage = "登入已過期"
            alert = UserFacingAlert(title: "請重新登入", message: "伺服器回傳 401，Bearer token 已失效。")
        } catch {
            syncMessage = "同步失敗"
            showError(error, fallback: "同步失敗")
        }
    }

    private func shouldHandleUnauthorized(token: String, authGenerationAtStart: UInt64) -> Bool {
        guard authGenerationAtStart == authGeneration else {
            return false
        }

        return (try? tokenStore.loadToken()) == token
    }

    func createSection(title: String) {
        performLocalChange {
            try repository.createSection(title: title)
        }
    }

    func updateSection(id: String, title: String) {
        performLocalChange {
            try repository.updateSection(id: id, title: title)
        }
    }

    func deleteSection(id: String) {
        performLocalChange {
            try repository.deleteSection(id: id)
        }
    }

    func createItem(sectionId: String, name: String, content: String) {
        performLocalChange {
            try repository.createItem(sectionId: sectionId, name: name, content: content)
        }
    }

    func updateItem(id: String, sectionId: String, name: String, content: String) {
        performLocalChange {
            try repository.updateItem(id: id, sectionId: sectionId, name: name, content: content)
        }
    }

    func moveItem(id: String, sectionId: String) {
        performLocalChange {
            try repository.moveItem(id: id, sectionId: sectionId)
        }
    }

    func deleteItem(id: String) {
        performLocalChange {
            try repository.deleteItem(id: id)
        }
    }

    func createOptimizer(title: String, placement: OptimizerPlacement, affixText: String) {
        performLocalChange {
            try repository.createOptimizer(title: title, placement: placement, affixText: affixText)
        }
    }

    func updateOptimizer(id: String, title: String, placement: OptimizerPlacement, affixText: String) {
        performLocalChange {
            try repository.updateOptimizer(id: id, title: title, placement: placement, affixText: affixText)
        }
    }

    func deleteOptimizer(id: String) {
        performLocalChange {
            try repository.deleteOptimizer(id: id)
        }
    }

    func createMemoDocument(title: String, content: String, copyableRanges: [CopyableRange]) {
        performLocalChange {
            try repository.createMemoDocument(title: title, content: content, copyableRanges: copyableRanges)
        }
    }

    func updateMemoDocument(id: String, title: String, content: String, copyableRanges: [CopyableRange]) {
        performLocalChange {
            try repository.updateMemoDocument(id: id, title: title, content: content, copyableRanges: copyableRanges)
        }
    }

    func deleteMemoDocument(id: String) {
        performLocalChange {
            try repository.deleteMemoDocument(id: id)
        }
    }

    func items(in sectionId: String) -> [ClipItem] {
        items
            .filter { $0.sectionId == sectionId && $0.deletedAt == nil }
            .sorted { left, right in
                if left.position == right.position {
                    return left.name.localizedStandardCompare(right.name) == .orderedAscending
                }
                return left.position < right.position
            }
    }

    func copy(_ text: String, notice: String = "已複製") {
        Clipboard.copy(text)
        flash(title: notice, message: text.isEmpty ? "內容為空" : "內容已放入剪貼簿")
    }

    func importCSV(from url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let rows = CSVService.parse(text)
            try repository.importCSVRows(rows)
            localChangeGeneration &+= 1
            refreshPublishedState()
            scheduleSync()
            flash(title: "CSV 已匯入", message: "剪貼內容已依四欄格式更新")
        } catch {
            showError(error, fallback: "CSV 匯入失敗")
        }
    }

    func exportCSV(to url: URL) {
        do {
            let csv = CSVService.export(repository.exportCSVRows())
            try csv.write(to: url, atomically: true, encoding: .utf8)
            flash(title: "CSV 已匯出", message: url.lastPathComponent)
        } catch {
            showError(error, fallback: "CSV 匯出失敗")
        }
    }

    func exportBackup(to url: URL) {
        do {
            let backup = repository.exportBackup()
            let data = try JSONEncoder.clipBase.encode(backup)
            try data.write(to: url, options: [.atomic])
            flash(title: "備份已匯出", message: url.lastPathComponent)
        } catch {
            showError(error, fallback: "備份失敗")
        }
    }

    func restoreBackup(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let backup = try JSONDecoder.clipBase.decode(ClipBaseBackup.self, from: data)
            try repository.restoreBackup(backup)
            localChangeGeneration &+= 1
            refreshPublishedState()
            scheduleSync()
            flash(title: "備份已還原", message: "本機資料已套用備份內容")
        } catch {
            showError(error, fallback: "還原失敗")
        }
    }

    func openCSVImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            importCSV(from: url)
        }
    }

    func openCSVExportPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "clipbase-export.csv"
        if panel.runModal() == .OK, let url = panel.url {
            exportCSV(to: url)
        }
    }

    func openBackupExportPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "clipbase-backup.json"
        if panel.runModal() == .OK, let url = panel.url {
            exportBackup(to: url)
        }
    }

    func openBackupRestorePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            restoreBackup(from: url)
        }
    }

    private func performLocalChange(_ action: () throws -> Void) {
        do {
            try action()
            localChangeGeneration &+= 1
            refreshPublishedState()
            scheduleSync()
        } catch {
            showError(error, fallback: "操作失敗")
        }
    }

    private func scheduleSync() {
        syncMessage = "有本機變更待同步"
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await syncNow(showSuccess: false)
        }
    }

    private func refreshPublishedState() {
        sections = repository.activeSections
        items = repository.allItems
        optimizers = repository.activeOptimizers
        memoDocuments = repository.activeMemoDocuments
        lastSyncAt = repository.lastSyncAt
    }

    private func flash(title: String, message: String) {
        alert = UserFacingAlert(title: title, message: message)
    }

    private func showError(_ error: Error, fallback: String) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        alert = UserFacingAlert(title: fallback, message: message)
    }

    private func formatSyncTime(_ milliseconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private enum DefaultsKey {
    static let apiBaseURL = "clipbase.apiBaseURL"
    static let username = "clipbase.username"
    static let lastAuthenticatedBaseURL = "clipbase.lastAuthenticatedBaseURL"
    static let defaultBaseURL = "https://clipbase.thelonesomeera.com/"
}
