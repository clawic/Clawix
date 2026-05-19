import XCTest
@testable import Clawix

@MainActor
final class LifeVerticalsStoreCancellationTests: XCTestCase {
    func testCancelSurfaceWorkSuppressesLateCatalogPublication() async {
        let requestStarted = expectation(description: "Catalog request started")
        let requestReturned = expectation(description: "Catalog request returned after teardown")
        let store = LifeVerticalsStore(
            urlSession: Self.urlSession(),
            tokenProvider: { nil }
        )
        LifeVerticalsURLProtocol.handler = { request, loader in
            XCTAssertEqual(request.url?.path, "/v1/health/catalog")
            requestStarted.fulfill()
            let delayedLoader = LifeVerticalsURLProtocol.Loader(loader)
            let responseBody = Self.catalogEnvelope(id: "late-catalog")
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                requestReturned.fulfill()
                LifeVerticalsURLProtocol.respond(
                    delayedLoader.value,
                    request: request,
                    body: responseBody
                )
            }
        }
        defer { LifeVerticalsURLProtocol.handler = nil }

        let task = Task { await store.reloadCatalog(for: "health") }
        await fulfillment(of: [requestStarted], timeout: 1)

        store.cancelSurfaceWork(for: "health")

        await fulfillment(of: [requestReturned], timeout: 1)
        await task.value

        XCTAssertTrue(store.state(for: "health").catalog.isEmpty)
        XCTAssertNil(store.state(for: "health").lastError)
    }

    func testSecondObservationReloadSuppressesStaleFirstResult() async {
        let staleStarted = expectation(description: "Stale observation request started")
        let staleReturned = expectation(description: "Stale observation request returned")
        let freshReturned = expectation(description: "Fresh observation request returned")
        let lock = NSLock()
        var calls = 0
        let store = LifeVerticalsStore(
            urlSession: Self.urlSession(),
            tokenProvider: { nil }
        )
        LifeVerticalsURLProtocol.handler = { request, loader in
            XCTAssertEqual(request.url?.path, "/v1/health/observations")
            lock.lock()
            calls += 1
            let currentCall = calls
            lock.unlock()
            if currentCall == 1 {
                staleStarted.fulfill()
                let delayedLoader = LifeVerticalsURLProtocol.Loader(loader)
                let responseBody = Self.observationsEnvelope(id: "stale")
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.08) {
                    staleReturned.fulfill()
                    LifeVerticalsURLProtocol.respond(
                        delayedLoader.value,
                        request: request,
                        body: responseBody
                    )
                }
                return
            }
            freshReturned.fulfill()
            LifeVerticalsURLProtocol.respond(
                loader,
                request: request,
                body: Self.observationsEnvelope(id: "fresh")
            )
        }
        defer { LifeVerticalsURLProtocol.handler = nil }

        let first = Task {
            await store.reloadObservations(for: "health", variableId: "heart-rate")
        }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task {
            await store.reloadObservations(for: "health", variableId: "heart-rate")
        }

        await fulfillment(of: [freshReturned, staleReturned], timeout: 1)
        await first.value
        await second.value

        XCTAssertEqual(store.state(for: "health").observations.map(\.id), ["fresh"])
        XCTAssertNil(store.state(for: "health").lastError)
    }

    func testCancelSurfaceWorkSuppressesLateMutationError() async {
        let mutationStarted = expectation(description: "Mutation request started")
        let mutationReturned = expectation(description: "Mutation request returned after teardown")
        let store = LifeVerticalsStore(
            urlSession: Self.urlSession(),
            tokenProvider: { nil }
        )
        LifeVerticalsURLProtocol.handler = { request, loader in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/health/observations")
            mutationStarted.fulfill()
            let delayedLoader = LifeVerticalsURLProtocol.Loader(loader)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                mutationReturned.fulfill()
                LifeVerticalsURLProtocol.respond(
                    delayedLoader.value,
                    request: request,
                    statusCode: 500,
                    body: #"{"error":"late"}"#
                )
            }
        }
        defer { LifeVerticalsURLProtocol.handler = nil }

        let task = Task {
            await store.upsertObservation(
                verticalId: "health",
                input: LifeUpsertObservationInput(
                    id: nil,
                    variableId: "heart-rate",
                    value: .number(72),
                    unitId: "bpm",
                    recordedAt: 1_779_196_800_000,
                    source: .manual,
                    notes: nil,
                    sessionId: nil,
                    externalId: nil
                )
            )
        }
        await fulfillment(of: [mutationStarted], timeout: 1)

        store.cancelSurfaceWork(for: "health")

        await fulfillment(of: [mutationReturned], timeout: 1)
        await task.value

        XCTAssertNil(store.state(for: "health").lastError)
    }

    nonisolated private static func urlSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LifeVerticalsURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    nonisolated private static func catalogEnvelope(id: String) -> String {
        """
        {
          "items": [
            {
              "id": "\(id)",
              "domain": "health",
              "label": "Heart rate",
              "unit": { "id": "bpm", "label": "bpm" },
              "valueType": "numeric",
              "origin": "system"
            }
          ]
        }
        """
    }

    nonisolated private static func observationsEnvelope(id: String) -> String {
        """
        {
          "items": [
            {
              "id": "\(id)",
              "variableId": "heart-rate",
              "value": 72,
              "unitId": "bpm",
              "recordedAt": 1779196800000,
              "source": "manual"
            }
          ]
        }
        """
    }
}

private final class LifeVerticalsURLProtocol: URLProtocol {
    struct Loader: @unchecked Sendable {
        let value: URLProtocol

        init(_ value: URLProtocol) {
            self.value = value
        }
    }

    static var handler: ((URLRequest, URLProtocol) -> Void)?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.handler?(request, self)
    }

    override func stopLoading() {}

    static func respond(
        _ loader: URLProtocol,
        request: URLRequest,
        statusCode: Int = 200,
        body: String
    ) {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
              )
        else { return }
        loader.client?.urlProtocol(loader, didReceive: response, cacheStoragePolicy: .notAllowed)
        loader.client?.urlProtocol(loader, didLoad: Data(body.utf8))
        loader.client?.urlProtocolDidFinishLoading(loader)
    }
}
