import Foundation
import Testing
@testable import TeroCore

@Test func unitConversionAndAmbiguity() {
  let km=UnitQuantity.parse("12 km")!
  #expect(abs(km.sources[0].convert(km.value,to:UnitQuantity.units.first{$0.id=="mi"}!)! - 7.4564543068)<0.000001)
  let f=UnitQuantity.parse("32 °F")!
  #expect(abs(f.sources[0].convert(f.value,to:UnitQuantity.units.first{$0.id=="c"}!)!)<0.000001)
  #expect(UnitQuantity.parse("1 gal")?.sources.count==2)
  #expect(UnitQuantity.parse("1 ton")?.sources.count==3)
  #expect(UnitQuantity.parse("10 kg and 4 lb")==nil)
  #expect(UnitQuantity.parse("1,234 km")==nil)
  #expect(UnitQuantity.parse("3,5 km")?.value==3.5)
  #expect(UnitQuantity.units.first{$0.id=="k"}?.convert(-1,to:UnitQuantity.units.first{$0.id=="c"}!)==nil)
}
@Test func currencySourcesAndRateValidation() throws {
  #expect(CurrencyQuantity.parse("$100")?.sources.count==6)
  #expect(CurrencyQuantity.parse("100 EUR")?.sources==["EUR"])
  #expect(CurrencyQuantity.parse("100 dhs")?.sources==["MAD"])
  #expect(CurrencyQuantity.parse("DH 100")?.sources==["MAD"])
  #expect(CurrencyQuantity.parse("100 MAD")?.sources==["MAD"])
  #expect(CurrencyQuantity.parse("100")?.sources.isEmpty==true)
  #expect(CurrencyQuantity.parse("$1,234")==nil)
  let rate=try JSONDecoder().decode(CurrencyRate.self,from:Data(#"{"date":"2026-10-06","base":"EUR","quote":"USD","rate":1.2}"#.utf8))
  let now=ISO8601DateFormatter().date(from:"2026-10-06T12:00:00Z")!
  #expect(rate.converted(100,source:"EUR",target:"USD",now:now)==120)
  #expect(rate.converted(100,source:"GBP",target:"USD",now:now)==nil)
  #expect(rate.converted(100,source:"EUR",target:"USD",now:now.addingTimeInterval(11*86400))==nil)
}
@Test func currencySnapshotValidatesPairAndDate() throws {
  let snapshot=try JSONDecoder().decode(CurrencySnapshot.self,from:Data(#"{"date":"2026-10-06","eur":{"usd":1.12,"mad":11.19}}"#.utf8))
  let now=ISO8601DateFormatter().date(from:"2026-10-06T12:00:00Z")!
  #expect(snapshot.rate(source:"EUR",target:"MAD")?.converted(100,source:"EUR",target:"MAD",now:now)==1119)
  #expect(snapshot.rate(source:"USD",target:"MAD")==nil)
  #expect(snapshot.rate(source:"EUR",target:"GBP")==nil)
  #expect(snapshot.rate(source:"EUR",target:"MAD")?.provider=="Exchange API")
  #expect(snapshot.rate(source:"EUR",target:"MAD")?.converted(100,source:"EUR",target:"MAD",now:now.addingTimeInterval(11*86400))==nil)
}
@Test func explicitAndAmbiguousZonesAndDST() {
  #expect(SelectedTime.parse("3 PM EST")?.hour==15)
  #expect(SelectedTime.parse("15:30 CST")?.sources.count==3)
  #expect(SelectedTime.parse("2026-02-30 15:00 UTC")==nil)
  #expect(SelectedTime.parse("25:00 UTC")==nil)
  let time=SelectedTime.parse("2026-10-06 3 PM EST")!
  let zone=SelectionTimeZone(id:"Europe/Paris",title:"Paris")
  #expect(time.result(on:"2026-10-06",source:time.sources[0],target:zone)?.contains("22:00")==true)
  let spring=SelectedTime.parse("2026-03-08 2:30 AM America/New_York")!
  #expect(spring.instant(on:"2026-03-08",in:spring.sources[0])==nil)
  let fall=SelectedTime.parse("2026-11-01 1:30 AM America/New_York")!
  #expect(fall.instant(on:"2026-11-01",in:fall.sources[0])==nil)
}
@Test func utilitiesAreRegisteredAndRankedFromActualSelection() {
  let reading=SelectionReadout(applicationName:"test",processIdentifier:0,status:.selected("12 km"))
  let context=RecommendationContext(selection:reading,applicationID:nil)
  #expect(Action.convertUnits.definition?.priority(in:context)==110)
  #expect(Action.convertTimeZones.definition?.accepts(context)==false)
  #expect(Action.checkClaim.definition?.usesAI==true)
  #expect(Action.convertUnits.definition?.usesAI==false)
  #expect(Action.openMaps.definition?.transformsText==false)
  #expect(SelectedAddress.query("https://example.com")==nil)
  #expect(SelectedAddress.looksLikeAddress("10 Downing Street, London")==true)
}
