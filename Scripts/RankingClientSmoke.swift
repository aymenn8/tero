import Foundation

final class RankingURLProtocol: URLProtocol, @unchecked Sendable {
  enum Mode { case ok, wrongID, offline, slow, delayed }
  nonisolated(unsafe) static var mode: Mode = .ok // Single sequential test driver only.
  private var delayedTask: Task<Void, Never>?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    if Self.mode == .slow { return }
    if Self.mode == .offline { client?.urlProtocol(self,didFailWithError:URLError(.notConnectedToInternet)); return }
    var bytes = request.httpBody ?? Data()
    if bytes.isEmpty, let stream = request.httpBodyStream {
      stream.open(); defer { stream.close() }
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }; bytes.append(contentsOf: buffer.prefix(count))
      }
    }
    let body = try! JSONSerialization.jsonObject(with: bytes) as! [String:Any]
    let id = Self.mode == .wrongID ? UUID().uuidString : body["requestID"] as! String
    var object: [String:Any] = ["requestID":id,"model":"jev-1.13.0", "scores":[["id":"fix","score":2.5,"confidence":0.8],["id":"translate","score":1.0,"confidence":0.9]],
      "usage":["inputTokens":400,"outputTokens":10,"estimatedCostUSD":0.0000168],"promptVersion":2,"latencyMs":100]
    if body["debug"] as? Bool == true {
      object["debug"] = ["providerRequest":"{\"model\":\"jev-1.13.0\"}", "providerResponse":"{\"answers\":{}}"]
      object["scores"] = [["id":"fix","score":2.5,"confidence":0.8,"probabilities":["0":0.0,"1":0.0,"2":0.5,"3":0.5]], ["id":"translate","score":1.0,"confidence":0.9,"probabilities":["0":0.0,"1":1.0,"2":0.0,"3":0.0]]]
    }
    let data = try! JSONSerialization.data(withJSONObject:object)
    if Self.mode == .delayed {
      delayedTask = Task { @Sendable [self] in
        do { try await Task.sleep(for: .milliseconds(1100)) } catch { return }
        guard !Task.isCancelled else { return }
        deliver(data)
      }
    } else { deliver(data) }
  }
  private func deliver(_ data: Data) {
    client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
    client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() { delayedTask?.cancel() }
}
@main struct RankingClientSmoke {
  static func main() async throws {
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [RankingURLProtocol.self]
    let session = URLSession(configuration:config)
    let client = RankingClient(session:session,deadline:.milliseconds(80))
    let input = RankingContext(RecommendationContext(selection:.init(applicationName:"Test",processIdentifier:0,status:.selected("a short test")),applicationID:"test"))!
    let result = try await client.rank(context:input,candidates:["fix","translate"],credential:"synthetic")
    precondition(result.model == "jev-1.13.0" && result.scores.count == 2)
    precondition(result.debug == nil)
    let traced = try await client.rank(context:input,candidates:["fix","translate"],credential:"synthetic",debug:true)
    precondition(traced.debug?.providerRequest.contains("jev-1.13.0") == true)
    precondition(traced.scores.first?.probabilities?["3"] == 0.5)
    // Exact-context reuse expires quickly and cannot cross accounts or signed-out state.
    var memo = RankingMemo()
    let account = UUID(), otherAccount = UUID(), now = ContinuousClock.now
    let candidates = ["fix", "translate"]
    memo.store(result.scores, accountID: account, context: input, candidates: candidates, now: now)
    precondition(memo.scores(accountID: account, context: input, candidates: candidates, now: now.advanced(by: .seconds(19))) == result.scores)
    precondition(memo.scores(accountID: otherAccount, context: input, candidates: candidates, now: now) == nil)
    precondition(memo.scores(accountID: account, context: input, candidates: candidates.reversed(), now: now) == nil)
    let changed = RankingContext(RecommendationContext(selection: .init(applicationName: "Test", processIdentifier: 0, status: .selected("different text")), applicationID: "test"))!
    precondition(memo.scores(accountID: account, context: changed, candidates: candidates, now: now) == nil)
    precondition(memo.scores(accountID: account, context: input, candidates: candidates, now: now.advanced(by: .seconds(20))) == nil)
    memo.store(result.scores, accountID: account, context: input, candidates: candidates, now: now)
    precondition(memo.scores(accountID: nil, context: input, candidates: candidates, now: now) == nil)
    precondition(memo.scores(accountID: account, context: input, candidates: candidates, now: now) == nil)
    RankingURLProtocol.mode = .delayed
    let delayedStart = ContinuousClock.now
    let delayed = try await RankingClient(session:session).rank(context:input,candidates:["fix","translate"],credential:"synthetic")
    precondition(delayed.scores.count == 2 && delayedStart.duration(to:.now) > .milliseconds(900))
    RankingURLProtocol.mode = .wrongID
    do { _ = try await client.rank(context:input,candidates:["fix","translate"],credential:"synthetic");fatalError("wrong ID accepted") } catch {}
    RankingURLProtocol.mode = .offline
    do { _ = try await client.rank(context:input,candidates:["fix","translate"],credential:"synthetic");fatalError("offline accepted") } catch {}
    RankingURLProtocol.mode = .slow
    let start = ContinuousClock.now
    do { _ = try await client.rank(context:input,candidates:["fix","translate"],credential:"synthetic");fatalError("timeout accepted") } catch {}
    precondition(start.duration(to:.now) < .milliseconds(500))
    let task = Task { try await RankingClient(session:session,deadline:.seconds(2)).rank(context:input,candidates:["fix","translate"],credential:"synthetic") }
    try await Task.sleep(for:.milliseconds(20)); let cancellation = ContinuousClock.now; task.cancel()
    do { _ = try await task.value;fatalError("cancelled request accepted") } catch {}
    precondition(cancellation.duration(to:.now) < .milliseconds(500))
    session.invalidateAndCancel()
    print("PASS: native ranking transport, request identity, offline fallback, deadline, cancellation and isolated 20-second cache; no provider calls")
  }
}
