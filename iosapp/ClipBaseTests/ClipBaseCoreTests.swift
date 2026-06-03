import XCTest
@testable import ClipBase

final class ClipBaseCoreTests: XCTestCase {
    func testDefaultServerURLUsesProductionClipBase() {
        XCTAssertEqual(ClipBaseSnapshot.empty.baseURL, "https://clipbase.thelonesomeera.com/")
    }

    func testClipLibraryDoesNotAutoSelectFirstSectionByDefault() {
        let sections = [
            ClipSection(id: "first", title: "第一個分類", position: 0, updatedAt: 100, deletedAt: nil)
        ]

        XCTAssertNil(DomainRules.validSectionSelection(current: nil, sections: sections))
        XCTAssertNil(DomainRules.validSectionSelection(current: "missing", sections: sections))
        XCTAssertEqual(DomainRules.validSectionSelection(current: "first", sections: sections), "first")
    }

    func testPromptOptimizerMergeMatchesWebRules() {
        let optimizer = PromptOptimizer(
            id: "optimizer-1",
            title: "Prefix",
            placement: .prefix,
            affixText: "固定提示詞",
            position: 0,
            updatedAt: 100,
            deletedAt: nil
        )

        XCTAssertEqual(DomainRules.mergedPrompt(input: "", optimizer: optimizer), "固定提示詞")
        XCTAssertEqual(DomainRules.mergedPrompt(input: "  原始內容  ", optimizer: optimizer), "固定提示詞\n\n原始內容")

        var suffix = optimizer
        suffix.placement = .suffix
        suffix.affixText = "固定後綴"
        XCTAssertEqual(DomainRules.mergedPrompt(input: "原始內容", optimizer: suffix), "原始內容\n\n固定後綴")
    }

    func testMemoRangesAreNormalizedWithWebRules() {
        let content = "abcde"
        let ranges = [
            CopyableRange(start: 3, end: 8),
            CopyableRange(start: 1, end: 2),
            CopyableRange(start: 2, end: 4),
            CopyableRange(start: 4, end: 4),
            CopyableRange(start: 1, end: 2)
        ]

        XCTAssertEqual(
            DomainRules.normalizeCopyableRanges(ranges, content: content),
            [CopyableRange(start: 1, end: 4)]
        )
    }

    func testDeletingSectionMovesActiveItemsToOtherAndKeepsTombstone() throws {
        var snapshot = ClipBaseSnapshot.empty
        let sectionId = try snapshot.createSection(title: "帳號", now: 100)
        let item = ClipItem(
            id: "item-1",
            sectionId: sectionId,
            name: "Email",
            content: "user@example.com",
            metadata: nil,
            position: 0,
            updatedAt: 110,
            deletedAt: nil
        )
        snapshot.items.append(item)

        let fallbackId = try snapshot.deleteSection(id: sectionId, now: 200)

        XCTAssertEqual(snapshot.sections.first(where: { $0.id == sectionId })?.deletedAt, 200)
        XCTAssertEqual(snapshot.items.first(where: { $0.id == "item-1" })?.sectionId, fallbackId)
        XCTAssertEqual(snapshot.sections.first(where: { $0.id == fallbackId })?.title, "其它")
        XCTAssertThrowsError(try snapshot.deleteSection(id: fallbackId, now: 250)) { error in
            XCTAssertEqual(error as? ClipBaseDomainError, .protectedSection)
        }
    }

    func testRemoteChangesUseRowLevelLastWriteWins() {
        var snapshot = ClipBaseSnapshot.empty
        snapshot.sections = [
            ClipSection(id: "section-1", title: "Local", position: 0, updatedAt: 500, deletedAt: nil)
        ]

        snapshot.applyRemoteChanges(SyncChanges(sections: [
            ClipSection(id: "section-1", title: "Old Remote", position: 0, updatedAt: 400, deletedAt: nil)
        ]))
        XCTAssertEqual(snapshot.sections.first?.title, "Local")

        snapshot.applyRemoteChanges(SyncChanges(sections: [
            ClipSection(id: "section-1", title: "Deleted Remote", position: 0, updatedAt: 450, deletedAt: 600)
        ]))
        XCTAssertEqual(snapshot.sections.first?.deletedAt, 600)
    }

    func testRemoteSectionTombstoneDoesNotMoveItemUpdatedAtBackwards() {
        var snapshot = ClipBaseSnapshot.empty
        snapshot.sections = [
            ClipSection(id: "section-1", title: "Local", position: 0, updatedAt: 500, deletedAt: nil)
        ]
        snapshot.items = [
            ClipItem(id: "item-1", sectionId: "section-1", name: "Newer Item", content: "value", metadata: nil, position: 0, updatedAt: 800, deletedAt: nil)
        ]

        snapshot.applyRemoteChanges(SyncChanges(sections: [
            ClipSection(id: "section-1", title: "Deleted Remote", position: 0, updatedAt: 500, deletedAt: 600)
        ]))

        let fallbackId = snapshot.sections.first { $0.title == "其它" }?.id
        XCTAssertEqual(snapshot.items.first?.sectionId, fallbackId)
        XCTAssertEqual(snapshot.items.first?.updatedAt, 800)
    }

    func testLocalChangesIncludeRecordsAfterLastSync() {
        var snapshot = ClipBaseSnapshot.empty
        snapshot.sections = [
            ClipSection(id: "old", title: "Old", position: 0, updatedAt: 100, deletedAt: nil),
            ClipSection(id: "new", title: "New", position: 1, updatedAt: 300, deletedAt: nil),
            ClipSection(id: "deleted", title: "Deleted", position: 2, updatedAt: 100, deletedAt: 350)
        ]

        let changes = snapshot.localChanges(after: 200)
        XCTAssertEqual(changes.sections.map(\.id), ["new", "deleted"])
    }

    func testCSVExportNeutralizesSpreadsheetFormulas() {
        let section = ClipSection(id: "section-1", title: "帳號", position: 0, updatedAt: 100, deletedAt: nil)
        let item = ClipItem(
            id: "item-1",
            sectionId: "section-1",
            name: "Token",
            content: "  =IMPORTXML(\"https://example.com\")",
            metadata: nil,
            position: 0,
            updatedAt: 100,
            deletedAt: nil
        )

        let csv = CSVSupport.export(sections: [section]) { _ in [item] }

        XCTAssertTrue(csv.contains(",Token,\"'  =IMPORTXML(\"\"https://example.com\"\")\""))
    }

    func testCSVImportUpsertsClipRecordsAndKeepsTombstones() {
        var snapshot = ClipBaseSnapshot.empty
        snapshot.sections = [
            ClipSection(id: "section-1", title: "帳號", position: 0, updatedAt: 1_000, deletedAt: nil),
            ClipSection(id: "removed-section", title: "已移除", position: 1, updatedAt: 1_300, deletedAt: nil)
        ]
        snapshot.items = [
            ClipItem(id: "email", sectionId: "section-1", name: "Email", content: "old@example.com", metadata: nil, position: 0, updatedAt: 1_100, deletedAt: nil),
            ClipItem(id: "legacy", sectionId: "section-1", name: "Legacy", content: "old-value", metadata: nil, position: 1, updatedAt: 1_200, deletedAt: nil),
            ClipItem(id: "removed-item", sectionId: "removed-section", name: "Token", content: "removed", metadata: nil, position: 0, updatedAt: 1_400, deletedAt: nil)
        ]

        snapshot.importCSVRows([
            CSVRow(section: "帳號", subsection: "", field: "Email", value: "new@example.com"),
            CSVRow(section: "帳號", subsection: "Phone", field: "Main", value: "0912")
        ], now: 5_000)

        let accountSection = snapshot.activeSections.first { $0.title == "帳號" }
        XCTAssertEqual(accountSection?.id, "section-1")
        XCTAssertEqual(accountSection?.updatedAt, 5_000)
        XCTAssertEqual(snapshot.sections.first { $0.id == "removed-section" }?.deletedAt, 5_000)

        let accountItems = snapshot.activeItems(in: "section-1")
        XCTAssertEqual(accountItems.first { $0.name == "Email" }?.id, "email")
        XCTAssertEqual(accountItems.first { $0.name == "Email" }?.content, "new@example.com")
        XCTAssertEqual(accountItems.first { $0.name == "Phone / Main" }?.content, "0912")
        XCTAssertEqual(snapshot.items.first { $0.id == "legacy" }?.deletedAt, 5_000)
        XCTAssertEqual(snapshot.items.first { $0.id == "removed-item" }?.deletedAt, 5_000)
    }

    func testNativeLoginPayloadAndInvalidCredentialMessage() async throws {
        MockURLProtocol.requestHandler = { request in
            let body = try XCTUnwrap(request.httpBodyStream.flatMap(Self.readStream) ?? request.httpBody)
            let payload = try JSONSerialization.jsonObject(with: body) as? [String: String]

            XCTAssertEqual(request.url?.absoluteString, "https://clipbase.thelonesomeera.com/api/login")
            XCTAssertEqual(payload?["username"], "operator")
            XCTAssertEqual(payload?["password"], "wrong")
            XCTAssertEqual(payload?["tokenMode"], "bearer")
            XCTAssertEqual(payload?["client"], "native")

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 401,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"error":"帳號或密碼不正確"}"#.utf8))
        }
        defer {
            MockURLProtocol.requestHandler = nil
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = SyncClient(session: URLSession(configuration: configuration))

        do {
            _ = try await client.login(baseURL: ClipBaseSnapshot.defaultBaseURL, username: "operator", password: "wrong")
            XCTFail("Login should fail for invalid credentials")
        } catch let error as SyncClientError {
            XCTAssertEqual(error.localizedDescription, "帳號或密碼不正確")
        }
    }

    @MainActor
    func testSyncQueuesLocalChangesMadeDuringInFlightSync() async throws {
        let store = LocalClipBaseStore(fileURL: temporaryStoreURL())
        var snapshot = ClipBaseSnapshot.empty
        snapshot.sections = [
            ClipSection(id: "section-1", title: "Original", position: 0, updatedAt: 1_000, deletedAt: nil)
        ]
        snapshot.lastSyncAt = 2_000
        try store.save(snapshot)

        let tokenStore = InMemoryTokenStore(token: "session-token")
        let syncClient = ControlledSyncClient()
        let model = AppModel(store: store, keychain: tokenStore, syncClient: syncClient)
        model.load()

        let syncTask = Task { await model.sync() }
        try await syncClient.waitForCallCount(1)

        model.updateSection(id: "section-1", title: "Edited during sync")
        await model.sync()
        await syncClient.resumeFirstSync(serverTime: DomainRules.nowMilliseconds() + 100_000)

        try await syncClient.waitForCallCount(2)
        let secondChanges = await syncClient.changesForCall(at: 1)
        XCTAssertEqual(secondChanges?.sections.map(\.title), ["Edited during sync"])

        await syncTask.value
    }

    @MainActor
    func testLoginToDifferentBaseURLResetsSnapshotBeforeSyncing() async throws {
        let store = LocalClipBaseStore(fileURL: temporaryStoreURL())
        var snapshot = ClipBaseSnapshot.empty
        snapshot.baseURL = "https://old.example"
        snapshot.username = "old-user"
        snapshot.lastSyncAt = 1_000
        snapshot.sections = [
            ClipSection(id: "old-section", title: "Old dirty data", position: 0, updatedAt: 2_000, deletedAt: nil)
        ]
        try store.save(snapshot)

        let tokenStore = InMemoryTokenStore()
        let syncClient = RecordingSyncClient()
        let model = AppModel(store: store, keychain: tokenStore, syncClient: syncClient)
        model.load()

        await model.login(baseURL: "https://new.example", username: "new-user", password: "secret")

        let optionalFirstCall = await syncClient.syncCall(at: 0)
        let firstCall = try XCTUnwrap(optionalFirstCall)
        XCTAssertEqual(firstCall.baseURL, "https://new.example")
        XCTAssertEqual(firstCall.since, 0)
        XCTAssertTrue(firstCall.changes.isEmpty)
        XCTAssertEqual(model.snapshot.baseURL, "https://new.example")
        XCTAssertEqual(model.snapshot.username, "new-user")
        XCTAssertEqual(model.snapshot.sections, [])
    }

    @MainActor
    func testStaleSyncResponseAfterBaseURLChangeIsIgnored() async throws {
        let store = LocalClipBaseStore(fileURL: temporaryStoreURL())
        var snapshot = ClipBaseSnapshot.empty
        snapshot.baseURL = "https://old.example"
        snapshot.sections = [
            ClipSection(id: "local-section", title: "Local", position: 0, updatedAt: 1_000, deletedAt: nil)
        ]
        snapshot.lastSyncAt = 2_000
        try store.save(snapshot)

        let tokenStore = InMemoryTokenStore(token: "old-token")
        let syncClient = ControlledSyncClient()
        let model = AppModel(store: store, keychain: tokenStore, syncClient: syncClient)
        model.load()

        let syncTask = Task { await model.sync() }
        try await syncClient.waitForCallCount(1)

        model.updateBaseURL("https://new.example")
        await syncClient.resumeFirstSync(
            serverTime: 9_000,
            changes: SyncChanges(
                sections: [
                    ClipSection(id: "old-remote-section", title: "Old Remote", position: 0, updatedAt: 8_000, deletedAt: nil)
                ],
                items: [],
                optimizers: [],
                memoDocuments: []
            )
        )
        await syncTask.value

        XCTAssertEqual(model.snapshot.baseURL, "https://new.example")
        XCTAssertEqual(model.snapshot.lastSyncAt, 0)
        XCTAssertTrue(model.snapshot.sections.isEmpty)
    }

    private static func readStream(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: bufferSize)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }
        return data
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("clipbase-state.json")
    }
}

private actor ControlledSyncClient: SyncServicing {
    private var calls: [(since: Milliseconds, changes: SyncChanges)] = []
    private var firstSyncContinuation: CheckedContinuation<SyncResponse, Never>?

    func login(baseURL: String, username: String, password: String) async throws -> LoginResponse {
        LoginResponse(username: username, token: "session-token")
    }

    func logout(baseURL: String, token: String) async {
    }

    func sync(baseURL: String, token: String, since: Milliseconds, changes: SyncChanges) async throws -> SyncResponse {
        calls.append((since: since, changes: changes))
        if calls.count == 1 {
            return await withCheckedContinuation { continuation in
                firstSyncContinuation = continuation
            }
        }
        return SyncResponse(serverTime: DomainRules.nowMilliseconds(), changes: SyncChanges())
    }

    func resumeFirstSync(serverTime: Milliseconds, changes: SyncChanges = SyncChanges()) {
        firstSyncContinuation?.resume(returning: SyncResponse(serverTime: serverTime, changes: changes))
        firstSyncContinuation = nil
    }

    func changesForCall(at index: Int) -> SyncChanges? {
        guard calls.indices.contains(index) else {
            return nil
        }
        return calls[index].changes
    }

    func waitForCallCount(_ expected: Int) async throws {
        for _ in 0..<50 {
            if calls.count >= expected {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw NSError(domain: "ClipBaseCoreTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Timed out waiting for sync call \(expected)"
        ])
    }
}

private actor RecordingSyncClient: SyncServicing {
    private var syncCalls: [(baseURL: String, since: Milliseconds, changes: SyncChanges)] = []

    func login(baseURL: String, username: String, password: String) async throws -> LoginResponse {
        LoginResponse(username: username, token: "session-token")
    }

    func logout(baseURL: String, token: String) async {
    }

    func sync(baseURL: String, token: String, since: Milliseconds, changes: SyncChanges) async throws -> SyncResponse {
        syncCalls.append((baseURL: baseURL, since: since, changes: changes))
        return SyncResponse(serverTime: 5_000, changes: SyncChanges())
    }

    func syncCall(at index: Int) -> (baseURL: String, since: Milliseconds, changes: SyncChanges)? {
        guard syncCalls.indices.contains(index) else {
            return nil
        }
        return syncCalls[index]
    }
}

private final class InMemoryTokenStore: TokenStoring {
    private var token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func readToken() -> String? {
        token
    }

    func saveToken(_ token: String) throws {
        self.token = token
    }

    func deleteToken() {
        token = nil
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
    }
}
