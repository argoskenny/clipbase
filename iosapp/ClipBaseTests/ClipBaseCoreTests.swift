import XCTest
@testable import ClipBase

final class ClipBaseCoreTests: XCTestCase {
    func testDefaultServerURLUsesProductionClipBase() {
        XCTAssertEqual(ClipBaseSnapshot.empty.baseURL, "https://clipbase.thelonesomeera.com/")
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
