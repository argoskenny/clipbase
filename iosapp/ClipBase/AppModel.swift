import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: ClipBaseSnapshot
    @Published private(set) var isAuthenticated: Bool
    @Published var isSyncing = false
    @Published var errorMessage: String?
    @Published var notice: String?

    private let store: LocalClipBaseStore
    private let keychain: TokenStoring
    private let syncClient: SyncServicing
    private var token: String?
    private var pendingSync = false
    private var localChangeGeneration: UInt64 = 0

    init(
        store: LocalClipBaseStore = LocalClipBaseStore(),
        keychain: TokenStoring = KeychainStore(),
        syncClient: SyncServicing = SyncClient()
    ) {
        self.store = store
        self.keychain = keychain
        self.syncClient = syncClient
        self.snapshot = .empty
        self.token = keychain.readToken()
        self.isAuthenticated = token != nil
    }

    func load() {
        do {
            snapshot = try store.load()
            token = keychain.readToken()
            isAuthenticated = token != nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func login(baseURL: String, username: String, password: String) async {
        errorMessage = nil
        isSyncing = true

        do {
            let normalizedBaseURL = normalizeBaseURL(baseURL)
            let response = try await syncClient.login(baseURL: normalizedBaseURL, username: username, password: password)
            guard let token = response.token, !token.isEmpty else {
                throw SyncClientError.server("登入回應缺少 Bearer token")
            }
            try keychain.saveToken(token)
            self.token = token
            if !sameBaseURL(snapshot.baseURL, normalizedBaseURL) {
                snapshot = emptySnapshot(baseURL: normalizedBaseURL)
                localChangeGeneration = 0
            }
            snapshot.baseURL = normalizedBaseURL
            snapshot.username = response.username
            try store.save(snapshot)
            isAuthenticated = true
            isSyncing = false
            await sync()
        } catch {
            isSyncing = false
            errorMessage = error.localizedDescription
            isAuthenticated = false
        }
    }

    func logout() async {
        if let token {
            await syncClient.logout(baseURL: snapshot.baseURL, token: token)
        }
        keychain.deleteToken()
        token = nil
        snapshot.username = nil
        persist(snapshot)
        isAuthenticated = false
    }

    func sync() async {
        guard let token else {
            isAuthenticated = false
            return
        }
        if isSyncing {
            pendingSync = true
            return
        }

        errorMessage = nil
        isSyncing = true
        defer {
            isSyncing = false
            if pendingSync {
                pendingSync = false
                Task { await sync() }
            }
        }

        do {
            let generationAtStart = localChangeGeneration
            let since = snapshot.lastSyncAt
            let changes = snapshot.localChanges(after: since)
            let response = try await syncClient.sync(baseURL: snapshot.baseURL, token: token, since: since, changes: changes)
            let changedDuringSync = localChangeGeneration != generationAtStart
            var next = snapshot
            next.applyRemoteChanges(response.changes)
            next.lastSyncAt = changedDuringSync ? since : response.serverTime
            snapshot = next
            try store.save(snapshot)
            if changedDuringSync {
                pendingSync = true
            }
            notice = changes.isEmpty ? "已同步" : "本地變更已同步"
        } catch SyncClientError.unauthorized {
            keychain.deleteToken()
            self.token = nil
            isAuthenticated = false
            errorMessage = SyncClientError.unauthorized.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateBaseURL(_ baseURL: String) {
        let normalizedBaseURL = normalizeBaseURL(baseURL)
        guard !sameBaseURL(snapshot.baseURL, normalizedBaseURL) else {
            snapshot.baseURL = normalizedBaseURL
            persist(snapshot)
            return
        }

        keychain.deleteToken()
        token = nil
        isAuthenticated = false
        snapshot = emptySnapshot(baseURL: normalizedBaseURL)
        localChangeGeneration = 0
        persist(snapshot)
    }

    @discardableResult
    func createSection(title: String) -> String? {
        mutateAndSync { try $0.createSection(title: title) }
    }

    func updateSection(id: String, title: String) {
        mutateAndSync { snapshot in
            try snapshot.updateSection(id: id, title: title)
            return id
        }
    }

    @discardableResult
    func deleteSection(id: String) -> String? {
        mutateAndSync { try $0.deleteSection(id: id) }
    }

    @discardableResult
    func createItem(sectionId: String, name: String, content: String) -> String? {
        mutateAndSync { try $0.createItem(sectionId: sectionId, name: name, content: content) }
    }

    func updateItem(id: String, sectionId: String, name: String, content: String) {
        mutateAndSync { snapshot in
            try snapshot.updateItem(id: id, sectionId: sectionId, name: name, content: content)
            return id
        }
    }

    func moveItem(id: String, to sectionId: String) {
        mutateAndSync { snapshot in
            try snapshot.moveItem(id: id, to: sectionId)
            return id
        }
    }

    func deleteItem(id: String) {
        mutateAndSync { snapshot in
            snapshot.deleteItem(id: id)
            return id
        }
    }

    @discardableResult
    func createOptimizer(title: String, placement: PromptPlacement, affixText: String) -> String? {
        mutateAndSync { try $0.createOptimizer(title: title, placement: placement, affixText: affixText) }
    }

    func updateOptimizer(id: String, title: String, placement: PromptPlacement, affixText: String) {
        mutateAndSync { snapshot in
            try snapshot.updateOptimizer(id: id, title: title, placement: placement, affixText: affixText)
            return id
        }
    }

    func deleteOptimizer(id: String) {
        mutateAndSync { snapshot in
            snapshot.deleteOptimizer(id: id)
            return id
        }
    }

    @discardableResult
    func createMemoDocument(title: String, content: String, copyableRanges: [CopyableRange]) -> String? {
        mutateAndSync { try $0.createMemoDocument(title: title, content: content, copyableRanges: copyableRanges) }
    }

    func updateMemoDocument(id: String, title: String, content: String, copyableRanges: [CopyableRange]) {
        mutateAndSync { snapshot in
            try snapshot.updateMemoDocument(id: id, title: title, content: content, copyableRanges: copyableRanges)
            return id
        }
    }

    func deleteMemoDocument(id: String) {
        mutateAndSync { snapshot in
            snapshot.deleteMemoDocument(id: id)
            return id
        }
    }

    func importCSV(_ csv: String) {
        do {
            let rows = try CSVSupport.parse(csv)
            mutateAndSync { snapshot in
                snapshot.importCSVRows(rows)
                return "csv"
            }
            notice = "CSV 已匯入"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportCSV() -> String {
        CSVSupport.export(sections: snapshot.activeSections) { sectionId in
            snapshot.activeItems(in: sectionId)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func clearNotice() {
        notice = nil
    }

    @discardableResult
    private func mutateAndSync(_ operation: (inout ClipBaseSnapshot) throws -> String) -> String? {
        do {
            var next = snapshot
            let id = try operation(&next)
            snapshot = next
            try store.save(snapshot)
            localChangeGeneration &+= 1
            Task { await sync() }
            return id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func persist(_ snapshot: ClipBaseSnapshot) {
        do {
            try store.save(snapshot)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func normalizeBaseURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ClipBaseSnapshot.empty.baseURL : trimmed
    }

    private func sameBaseURL(_ left: String, _ right: String) -> Bool {
        canonicalBaseURL(left) == canonicalBaseURL(right)
    }

    private func canonicalBaseURL(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func emptySnapshot(baseURL: String) -> ClipBaseSnapshot {
        var snapshot = ClipBaseSnapshot.empty
        snapshot.baseURL = baseURL
        return snapshot
    }
}
