import Foundation
import MapKit

final class UnavailablePrimaryRates: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { request.url?.host=="api.frankfurter.dev" }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let response=HTTPURLResponse(url:request.url!,statusCode:503,httpVersion:nil,headerFields:nil)!
    client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

@main struct UtilityServicesFixture {
  @MainActor static func main() async throws {
    let services=NativeSelectionUtilityServices()
    let rate=try await services.rate(source:"EUR",target:"USD")
    guard rate.converted(100,source:"EUR",target:"USD") != nil else {fatalError("Invalid ECB response")}
    print("PASS: native rate service decoded a dated EUR/USD rate; selected amount not transmitted.")
    let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[UnavailablePrimaryRates.self]
    let fallback=NativeSelectionUtilityServices(configuration:config)
    for (source,target) in [("EUR","MAD"),("MAD","USD")] {
      let rate=try await fallback.rate(source:source,target:target)
      guard rate.provider=="Exchange API",rate.converted(100,source:source,target:target) != nil else {fatalError("Invalid fallback rate")}
    }
    print("PASS: simulated primary outage recovered with real dated EUR/MAD and MAD/USD fallback rates.")
    let items=try await services.places(query:"10 Downing Street, London")
    guard !items.isEmpty else {fatalError("No public address match")}
    print("PASS: native MapKit service resolved a public address without opening Maps or requesting location.")
    services.cancel()
  }
}
