import Foundation
import XCTest
@testable import ClipBaseApp

final class ClipBaseLogicTests: XCTestCase {
    func testPromptOptimizerMergeMatchesWebRules() {
        let prefix = PromptOptimizer(
            id: "p1",
            title: "Prefix",
            placement: .prefix,
            affixText: "請優化",
            position: 0,
            updatedAt: 1000,
            deletedAt: nil
        )
        let suffix = PromptOptimizer(
            id: "p2",
            title: "Suffix",
            placement: .suffix,
            affixText: "請輸出英文",
            position: 1,
            updatedAt: 1000,
            deletedAt: nil
        )

        XCTAssertEqual(prefix.mergedPrompt(input: ""), "請優化")
        XCTAssertEqual(prefix.mergedPrompt(input: "原始提示"), "請優化\n\n原始提示")
        XCTAssertEqual(suffix.mergedPrompt(input: "原始提示"), "原始提示\n\n請輸出英文")
    }

    func testCopyableRangesNormalizeSelectionAndOverlaps() {
        let content = "0123456789abcdef"
        let ranges = TextRangeHelpers.normalize([
            CopyableRange(start: 8, end: 12),
            CopyableRange(start: 2, end: 5),
            CopyableRange(start: 4, end: 7),
            CopyableRange(start: -1, end: 2),
            CopyableRange(start: 30, end: 40)
        ], content: content)

        XCTAssertEqual(ranges, [
            CopyableRange(start: 2, end: 7),
            CopyableRange(start: 8, end: 12)
        ])

        let selected = TextRangeHelpers.copyableRange(
            forSelection: NSRange(location: 2, length: 6),
            content: "xx  標記  yy"
        )
        XCTAssertEqual(selected, CopyableRange(start: 4, end: 6))
    }

    func testCSVParseAndExportMatchesFourColumnFormat() {
        let text = [
            "區塊,子區塊,欄位,值",
            "\"測試,帳號\",Admin,備註,\"line 1",
            "line 2 with \"\"quote\"\"\""
        ].joined(separator: "\n")

        XCTAssertEqual(CSVService.parse(text), [
            CSVRow(section: "測試,帳號", subsection: "Admin", field: "備註", value: "line 1\nline 2 with \"quote\"")
        ])

        let csv = CSVService.export([
            CSVRow(section: "=cmd", subsection: "+SUM(1,1)", field: "-10", value: "@HYPERLINK(\"https://evil.example\")"),
            CSVRow(section: "安全分類", subsection: "", field: "備註", value: "  =IMPORTXML(\"https://evil.example\")")
        ])

        XCTAssertEqual(csv, [
            "區塊,子區塊,欄位,值",
            "'=cmd,\"'+SUM(1,1)\",'-10,\"'@HYPERLINK(\"\"https://evil.example\"\")\"",
            "安全分類,,備註,\"'  =IMPORTXML(\"\"https://evil.example\"\")\""
        ].joined(separator: "\n"))
    }

    func testDeletingSectionMovesItemsToOtherAndKeepsTombstone() throws {
        let repository = LocalRepository(fileURL: temporaryStoreURL())
        let source = try repository.createSection(title: "待刪分類", now: 1000)
        let item = try repository.createItem(sectionId: source.id, name: "保留項目", content: "保留內容", now: 1200)

        let fallback = try repository.deleteSection(id: source.id, now: 2000)

        XCTAssertEqual(fallback.title, "其它")
        XCTAssertFalse(repository.activeSections.contains(where: { $0.id == source.id }))
        XCTAssertEqual(repository.allSections.first(where: { $0.id == source.id })?.deletedAt, 2000)

        let moved = repository.activeItems(in: fallback.id).first
        XCTAssertEqual(moved?.id, item.id)
        XCTAssertEqual(moved?.name, "保留項目")
        XCTAssertEqual(moved?.updatedAt, 2000)
    }

    func testRemoteLastWriteWinsIgnoresOlderAndAppliesNewer() throws {
        let repository = LocalRepository(fileURL: temporaryStoreURL())
        let section = try repository.createSection(title: "本機新版", now: 2000)

        try repository.applyRemoteChanges(
            SyncChanges(
                sections: [
                    ClipSection(id: section.id, title: "遠端舊版", position: 0, updatedAt: 1000, deletedAt: nil)
                ],
                items: [],
                optimizers: [],
                memoDocuments: []
            ),
            serverTime: 3000
        )

        XCTAssertEqual(repository.activeSections.first?.title, "本機新版")
        XCTAssertEqual(repository.lastSyncAt, 3000)

        try repository.applyRemoteChanges(
            SyncChanges(
                sections: [
                    ClipSection(id: section.id, title: "遠端新版", position: 0, updatedAt: 4000, deletedAt: nil)
                ],
                items: [],
                optimizers: [],
                memoDocuments: []
            ),
            serverTime: 5000
        )

        XCTAssertEqual(repository.activeSections.first?.title, "遠端新版")
        XCTAssertEqual(repository.lastSyncAt, 5000)
    }

    func testCSVImportHandlesCustomRowsAndExportsMetadataRows() throws {
        let repository = LocalRepository(fileURL: temporaryStoreURL())
        try repository.importCSVRows([
            CSVRow(section: "帳號", subsection: "", field: "Email", value: "a@example.com"),
            CSVRow(section: "自定義", subsection: "Token", field: "訊息", value: "abc"),
            CSVRow(section: "自定義", subsection: "Token", field: "建立時間", value: "2026/01/02")
        ], now: 1000)

        XCTAssertEqual(repository.activeSections.map(\.title), ["帳號", "自定義"])
        XCTAssertEqual(repository.activeItems(in: repository.activeSections[0].id).first?.name, "Email")
        XCTAssertEqual(repository.activeItems(in: repository.activeSections[1].id).first?.metadata, "建立時間：2026/01/02")

        XCTAssertEqual(repository.exportCSVRows(), [
            CSVRow(section: "帳號", subsection: "", field: "Email", value: "a@example.com"),
            CSVRow(section: "自定義", subsection: "Token", field: "訊息", value: "abc"),
            CSVRow(section: "自定義", subsection: "Token", field: "建立時間", value: "2026/01/02")
        ])
    }

    func testUserDefaultsTokenStoreNormalizesAndClearsToken() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ClipBaseTests.\(UUID().uuidString)"))
        let store = UserDefaultsTokenStore(defaults: defaults)

        try store.saveToken(" session-token ")

        XCTAssertEqual(try store.loadToken(), "session-token")
        XCTAssertEqual(defaults.string(forKey: UserDefaultsTokenStore.defaultsKey), "session-token")

        try store.deleteToken()

        XCTAssertNil(try store.loadToken())
    }

    @MainActor
    func testLogoutResetsPreviousLoginData() async throws {
        defer {
            ControlledURLProtocol.requestHandler = nil
        }

        let repository = LocalRepository(fileURL: temporaryStoreURL())
        _ = try repository.createSection(title: "登入後資料", now: 1_000)
        try repository.applyRemoteChanges(.empty, serverTime: 2_000)

        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ClipBaseTests.\(UUID().uuidString)"))
        defaults.set("https://clipbase.test", forKey: "clipbase.apiBaseURL")
        defaults.set("admin", forKey: "clipbase.username")
        defaults.set("https://clipbase.test", forKey: "clipbase.lastAuthenticatedBaseURL")
        let tokenStore = InMemoryTokenStore(token: "session-token")
        ControlledURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"ok":true}"#.utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ControlledURLProtocol.self]

        let store = ClipBaseStore(
            repository: repository,
            tokenStore: tokenStore,
            apiClient: ClipBaseAPIClient(session: URLSession(configuration: configuration)),
            defaults: defaults
        )

        await store.logout()

        XCTAssertNil(tokenStore.loadToken())
        XCTAssertEqual(store.authState, .unauthenticated)
        XCTAssertTrue(repository.allSections.isEmpty)
        XCTAssertEqual(store.sections.count, 0)
        XCTAssertEqual(store.lastSyncAt, 0)
        XCTAssertNil(defaults.string(forKey: "clipbase.username"))
        XCTAssertNil(defaults.string(forKey: "clipbase.lastAuthenticatedBaseURL"))
        XCTAssertNil(store.alert)
    }

    @MainActor
    func testLoginUnauthorizedShowsLoginFailureMessage() async throws {
        defer {
            ControlledURLProtocol.requestHandler = nil
        }

        ControlledURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"error":"帳號或密碼不正確"}"#.utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ControlledURLProtocol.self]

        let store = ClipBaseStore(
            repository: LocalRepository(fileURL: temporaryStoreURL()),
            tokenStore: InMemoryTokenStore(),
            apiClient: ClipBaseAPIClient(session: URLSession(configuration: configuration)),
            defaults: try XCTUnwrap(UserDefaults(suiteName: "ClipBaseTests.\(UUID().uuidString)"))
        )

        await store.bootstrap()
        await store.login(baseURL: "https://clipbase.test", username: "admin", password: "wrong")

        XCTAssertEqual(store.authState, .unauthenticated)
        XCTAssertEqual(store.alert?.title, "登入失敗")
        XCTAssertEqual(store.alert?.message, "帳號或密碼不正確")
    }

    @MainActor
    func testPendingSyncSendsLocalChangesMadeDuringInFlightSync() async throws {
        defer {
            ControlledURLProtocol.requestHandler = nil
        }

        let repository = LocalRepository(fileURL: temporaryStoreURL())
        let section = try repository.createSection(title: "Original", now: 1_000)
        try repository.applyRemoteChanges(.empty, serverTime: 2_000)

        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ClipBaseTests.\(UUID().uuidString)"))
        defaults.set("https://clipbase.test", forKey: "clipbase.apiBaseURL")
        let tokenStore = InMemoryTokenStore(token: "session-token")
        let requestController = SyncRequestController()
        ControlledURLProtocol.requestHandler = requestController.handle
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ControlledURLProtocol.self]

        let store = ClipBaseStore(
            repository: repository,
            tokenStore: tokenStore,
            apiClient: ClipBaseAPIClient(session: URLSession(configuration: configuration)),
            defaults: defaults
        )

        let syncTask = Task { await store.syncNow(showSuccess: false) }
        let firstRequestStarted = await requestController.waitForFirstRequest()
        XCTAssertTrue(firstRequestStarted, "First sync request was not started")

        store.updateSection(id: section.id, title: "Edited during sync")
        await store.syncNow(showSuccess: false)

        requestController.resumeFirstRequest()
        let secondRequestStarted = await requestController.waitForSecondRequest()
        XCTAssertTrue(secondRequestStarted, "Pending sync did not run")

        let secondRequest = try XCTUnwrap(requestController.secondRequest)
        XCTAssertEqual(secondRequest.httpMethod, "POST")
        let body = try XCTUnwrap(secondRequest.httpBody ?? secondRequest.httpBodyStream.map(Self.readStream))
        let payload = try JSONDecoder.clipBase.decode(SyncRequestPayload.self, from: body)
        XCTAssertEqual(payload.changes.sections.map(\.title), ["Edited during sync"])

        await syncTask.value
    }

    @MainActor
    func testStaleUnauthorizedSyncDoesNotClearNewLoginToken() async throws {
        defer {
            AsyncControlledURLProtocol.requestHandler = nil
        }

        let repository = LocalRepository(fileURL: temporaryStoreURL())
        try repository.applyRemoteChanges(.empty, serverTime: 2_000)

        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ClipBaseTests.\(UUID().uuidString)"))
        defaults.set("https://clipbase.test", forKey: "clipbase.apiBaseURL")
        let tokenStore = InMemoryTokenStore(token: "old-token")
        let requestController = StaleUnauthorizedSyncController()
        AsyncControlledURLProtocol.requestHandler = requestController.handle
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AsyncControlledURLProtocol.self]
        configuration.httpMaximumConnectionsPerHost = 4

        let store = ClipBaseStore(
            repository: repository,
            tokenStore: tokenStore,
            apiClient: ClipBaseAPIClient(session: URLSession(configuration: configuration)),
            defaults: defaults
        )

        let syncTask = Task { await store.syncNow(showSuccess: false) }
        let initialSyncStarted = await requestController.waitForRequestCount(1)
        XCTAssertTrue(initialSyncStarted, "Initial sync request was not started")

        await store.logout()
        await store.login(baseURL: "https://clipbase.test", username: "admin", password: "password")

        requestController.resumeInitialSync()
        await syncTask.value

        let newTokenSyncStarted = await requestController.waitForRequestCount(4)
        XCTAssertTrue(newTokenSyncStarted, "Pending sync with the new token did not run")
        XCTAssertEqual(tokenStore.loadToken(), "new-token")
        XCTAssertEqual(store.authState, .authenticated(username: "admin"))
        XCTAssertNotEqual(store.alert?.title, "請重新登入")
        XCTAssertEqual(requestController.latestSyncAuthorization, "Bearer new-token")
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

private final class SyncRequestController {
    private let lock = NSLock()
    private let firstRequestStarted = DispatchSemaphore(value: 0)
    private let firstRequestCanReturn = DispatchSemaphore(value: 0)
    private let secondRequestStarted = DispatchSemaphore(value: 0)
    private var requestCount = 0
    private var _secondRequest: URLRequest?

    var secondRequest: URLRequest? {
        lock.withLock { _secondRequest }
    }

    func handle(_ request: URLRequest) -> (HTTPURLResponse, Data) {
        let currentCount = lock.withLock {
            requestCount += 1
            return requestCount
        }

        if currentCount == 1 {
            firstRequestStarted.signal()
            _ = firstRequestCanReturn.wait(timeout: .now() + 5)
        } else if currentCount == 2 {
            lock.withLock {
                _secondRequest = request
            }
            secondRequestStarted.signal()
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let body = Data(#"{"serverTime":9999999999999,"changes":{"sections":[],"items":[],"optimizers":[],"memoDocuments":[]}}"#.utf8)
        return (response, body)
    }

    func waitForFirstRequest() async -> Bool {
        await waitForRequestCount(1)
    }

    func resumeFirstRequest() {
        firstRequestCanReturn.signal()
    }

    func waitForSecondRequest() async -> Bool {
        await waitForRequestCount(2)
    }

    private func waitForRequestCount(_ expected: Int) async -> Bool {
        for _ in 0..<100 {
            if lock.withLock({ requestCount >= expected }) {
                return true
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return false
    }
}

private final class StaleUnauthorizedSyncController {
    private let lock = NSLock()
    private let initialSyncCanReturn = DispatchSemaphore(value: 0)
    private var requestCount = 0
    private var _latestSyncAuthorization: String?

    var latestSyncAuthorization: String? {
        lock.withLock { _latestSyncAuthorization }
    }

    func handle(_ request: URLRequest) -> (HTTPURLResponse, Data) {
        let currentCount = lock.withLock {
            requestCount += 1
            return requestCount
        }

        if currentCount == 1 {
            _ = initialSyncCanReturn.wait(timeout: .now() + 5)
            return response(for: request, statusCode: 401, body: #"{"error":"請先登入"}"#)
        }

        if request.url?.path == "/api/login" {
            return response(for: request, body: #"{"username":"admin","token":"new-token"}"#)
        }

        if request.url?.path == "/api/sync" {
            lock.withLock {
                _latestSyncAuthorization = request.value(forHTTPHeaderField: "Authorization")
            }
            return response(
                for: request,
                body: #"{"serverTime":9999999999999,"changes":{"sections":[],"items":[],"optimizers":[],"memoDocuments":[]}}"#
            )
        }

        return response(for: request, body: #"{"ok":true}"#)
    }

    func resumeInitialSync() {
        initialSyncCanReturn.signal()
    }

    func waitForRequestCount(_ expected: Int) async -> Bool {
        for _ in 0..<100 {
            if lock.withLock({ requestCount >= expected }) {
                return true
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return false
    }

    private func response(for request: URLRequest, statusCode: Int = 200, body: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }
}

private final class ControlledURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "clipbase.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = requestHandler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
    }
}

private final class AsyncControlledURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "clipbase.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let request = request
        DispatchQueue.global().async { [weak self] in
            guard let self else {
                return
            }
            guard let requestHandler = Self.requestHandler else {
                self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }

            let (response, data) = requestHandler(request)
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
    }
}

private struct SyncRequestPayload: Decodable {
    let changes: SyncChanges
}

private final class InMemoryTokenStore: TokenStoring {
    private var token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func loadToken() -> String? {
        token
    }

    func saveToken(_ token: String) {
        self.token = token
    }

    func deleteToken() {
        token = nil
    }
}
