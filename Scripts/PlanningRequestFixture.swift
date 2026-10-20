import Foundation

private final class Replies: @unchecked Sendable {
  let lock = NSLock()
  var statuses: [Int] = []
  var bodies: [[String: Any]] = []
  func reset(_ statuses: [Int]) { lock.lock(); defer { lock.unlock() }; self.statuses = statuses; bodies = [] }
  func next(_ body: [String: Any]) -> Int {
    lock.lock(); defer { lock.unlock() }; bodies.append(body)
    return statuses.isEmpty ? 599 : statuses.removeFirst()
  }
  var requests: [[String: Any]] { lock.lock(); defer { lock.unlock() }; return bodies }
}
private final class StubProtocol: URLProtocol, @unchecked Sendable {
  static let replies = Replies()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    var bytes = request.httpBody ?? Data()
    if let stream = request.httpBodyStream {
      stream.open(); defer { stream.close() }
      var buffer = [UInt8](repeating: 0, count: 1024)
      while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; bytes.append(contentsOf: buffer.prefix(count)) }
    }
    let body = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] ?? [:]
    let status = Self.replies.next(body)
    if status < 0 {
      client?.urlProtocol(self, didFailWithError: URLError(URLError.Code(rawValue:status)))
      return
    }
    let source = body["selection"] as? String ?? ""
    let item: [String: Any] = ["kind":"event", "title":"Point projet", "owner":NSNull(),
      "deadline":"jeudi 8 octobre 2026 de 15 h à 15 h 30", "condition":NSNull(), "evidence":source,
      "date":"2026-10-08", "time":"15:00", "endDate":"2026-10-08", "endTime":"15:30"]
    let reply: [String: Any] = status == 200
      ? ["requestID":body["requestID"] ?? "", "items":[item]] : ["error":"provider_error"]
    let data = try! JSONSerialization.data(withJSONObject:reply)
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

@main struct PlanningRequestFixture {
  static func main() async throws {
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
    let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
    let client = CorrectionClient(endpoint: URL(string:"https://fixture.invalid")!, requestSession: session)
    let source = "Point projet jeudi 8 octobre 2026 de 15 h à 15 h 30"
    let id = UUID()
    for status in [500, 502, 504, URLError.timedOut.rawValue, URLError.networkConnectionLost.rawValue] {
      StubProtocol.replies.reset([status, 200])
      let drafts = try await client.plan(source, destination: .calendar, requestID: id, credential:"synthetic")
      precondition(drafts.count == 1 && drafts[0].date == "2026-10-08" && drafts[0].time == "15:00" && drafts[0].endTime == "15:30")
      let requests = StubProtocol.replies.requests
      precondition(requests.count == 2 && NSDictionary(dictionary:requests[0]).isEqual(to:requests[1]))
    }
    for (status, failure) in [(400, CorrectionClient.Failure.invalid), (401, .unavailable), (429, .rateLimited), (503, .unavailable)] {
      StubProtocol.replies.reset([status, 200])
      do { _ = try await client.plan(source, destination:.calendar, requestID:id, credential:"synthetic"); preconditionFailure("Unexpected success") }
      catch { precondition(error as? CorrectionClient.Failure == failure) }
      precondition(StubProtocol.replies.requests.count == 1)
    }
    StubProtocol.replies.reset([502, 502, 200])
    do { _ = try await client.plan(source, destination:.calendar, requestID:id, credential:"synthetic"); preconditionFailure("Unlimited retry") }
    catch { precondition(error as? CorrectionClient.Failure == .network) }
    precondition(StubProtocol.replies.requests.count == 2)
    StubProtocol.replies.reset([502, 200])
    do { _ = try await client.correct(source, requestID:id, credential:"synthetic"); preconditionFailure("Other action retried") }
    catch { precondition(error as? CorrectionClient.Failure == .network) }
    precondition(StubProtocol.replies.requests.count == 1)
    StubProtocol.replies.reset([502, 200])
    let pending = Task { try await client.plan(source, destination:.calendar, requestID:id, credential:"synthetic") }
    while StubProtocol.replies.requests.isEmpty { try await Task.sleep(for:.milliseconds(10)) }
    pending.cancel()
    do { _ = try await pending.value; preconditionFailure("Cancelled request succeeded") } catch {}
    precondition(StubProtocol.replies.requests.count == 1)
    print("PASS: planning retries once, preserves payload, respects cancellation and permanent refusals; other actions unchanged")
  }
}
