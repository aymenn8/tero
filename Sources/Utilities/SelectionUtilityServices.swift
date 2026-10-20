import AppKit
import MapKit

@MainActor protocol SelectionUtilityServices {
  func rate(source: String, target: String) async throws -> CurrencyRate
  func places(query: String) async throws -> [MKMapItem]
  func open(_ item: MKMapItem, directions: Bool) -> Bool
  func cancel()
}
@MainActor final class NativeSelectionUtilityServices: SelectionUtilityServices {
  private var search: MKLocalSearch?
  private let configuration: URLSessionConfiguration
  init(configuration: URLSessionConfiguration = .ephemeral) { self.configuration=configuration }
  func rate(source: String, target: String) async throws -> CurrencyRate {
    guard CurrencyQuantity.codes.contains(source), CurrencyQuantity.codes.contains(target),source != target else {throw URLError(.badURL)}
    // Only currency codes leave the Mac; never the amount, text or app context.
    let config=configuration.copy() as! URLSessionConfiguration;config.httpCookieStorage=nil;config.urlCache=nil
    let session=URLSession(configuration:config);defer{session.invalidateAndCancel()}
    func fetch(_ url: URL, limit: Int) async throws -> Data {
      var request=URLRequest(url:url,timeoutInterval:6)
      request.setValue("application/json",forHTTPHeaderField:"Accept")
      request.setValue("Tero/0.1",forHTTPHeaderField:"User-Agent")
      let (bytes,response)=try await session.data(for:request)
      try Task.checkCancellation()
      guard let response=response as? HTTPURLResponse,response.statusCode==200,bytes.count<=limit else {throw URLError(.badServerResponse)}
      return bytes
    }
    do {
      let url=URL(string:"https://api.frankfurter.dev/v2/rate/\(source.lowercased())/\(target.lowercased())")!
      let rate=try JSONDecoder().decode(CurrencyRate.self,from:try await fetch(url,limit:4096))
      guard rate.converted(1,source:source,target:target) != nil else {throw URLError(.badServerResponse)}
      return rate
    } catch {
      try Task.checkCancellation()
      let url=URL(string:"https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/\(source.lowercased()).min.json")!
      let snapshot=try JSONDecoder().decode(CurrencySnapshot.self,from:try await fetch(url,limit:65536))
      guard let rate=snapshot.rate(source:source,target:target),rate.converted(1,source:source,target:target) != nil else {throw URLError(.badServerResponse)}
      return rate
    }
  }
  func places(query: String) async throws -> [MKMapItem] {
    guard SelectedAddress.query(query) != nil else {throw URLError(.badURL)}
    let request=MKLocalSearch.Request();request.naturalLanguageQuery=query
    let search=MKLocalSearch(request:request);self.search=search
    let deadline=Task { @MainActor in
      do { try await Task.sleep(for: .seconds(12)) } catch { return }
      search.cancel()
    }
    defer { deadline.cancel() }
    let response=try await search.start();try Task.checkCancellation()
    var seen=Set<String>()
    return Array(response.mapItems.filter { item in
      let coordinate=item.placemark.coordinate
      return CLLocationCoordinate2DIsValid(coordinate) && seen.insert("\(item.name ?? ""):\(coordinate.latitude):\(coordinate.longitude)").inserted
    }.prefix(12))
  }
  func open(_ item: MKMapItem,directions: Bool) -> Bool {
    item.openInMaps(launchOptions:directions ? [MKLaunchOptionsDirectionsModeKey:MKLaunchOptionsDirectionsModeDriving]:nil)
  }
  func cancel(){search?.cancel()}
}
