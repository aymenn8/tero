import AppKit
import MapKit
import Observation

/// One invocation-local choice adapter for native selection utilities.
@MainActor @Observable final class SelectionUtilitySession {
  let action: Action
  private(set) var options: [ModeChoice] = []
  var selectedID: String?
  private(set) var busy = false
  private(set) var message: String?
  private(set) var choosingDate = false
  var date = Date.now
  var sourceTimeZone: TimeZone { sourceZone?.zone ?? .current }
  var label = "Choose an option"
  private(set) var searchQuery = ""
  @ObservationIgnored var result: (String) -> Void
  @ObservationIgnored var back: () -> Void
  @ObservationIgnored var opened: () -> Void
  @ObservationIgnored private var operation: Task<Void, Never>?
  @ObservationIgnored private let services: any SelectionUtilityServices
  private var cancelled = false
  private var page = 0
  private var allOptions: [ModeChoice] = []
  private var stage = ""
  private var units: UnitQuantity?
  private var sourceUnit: ConversionUnit?
  private var money: CurrencyQuantity?
  private var sourceCurrency: String?
  private var clock: SelectedTime?
  private var sourceZone: SelectionTimeZone?
  private var mapItems: [MKMapItem] = []

  init(action: Action, text: String, result: @escaping (String) -> Void,
       back: @escaping () -> Void, opened: @escaping () -> Void, services: (any SelectionUtilityServices)? = nil) {
    self.action=action; self.result=result; self.back=back; self.opened=opened
    self.services=services ?? NativeSelectionUtilityServices()
    switch action {
    case .convertUnits:
      guard let value=UnitQuantity.parse(text) else {message="Select one number with a unit, such as 12 km.";return}
      units=value
      if value.sources.count > 1 { stage="unit_source"; set(value.sources.map { choice($0.id,$0.title) },label:"Choose source unit") }
      else { sourceUnit=value.sources[0]; unitTargets() }
    case .convertCurrencies:
      guard let value=CurrencyQuantity.parse(text) else {message="Select one amount, such as 100 EUR.";return}
      money=value
      if value.sources.count == 1 {sourceCurrency=value.sources[0];currencyTargets()}
      else {stage="currency_source";set((value.sources.isEmpty ? CurrencyQuantity.codes:value.sources).map {currencyChoice($0)},label:"Choose source currency")}
    case .convertTimeZones:
      guard let value=SelectedTime.parse(text) else{message="Select a time and zone, such as 3 PM EST.";return}
      clock=value
      if value.sources.count > 1 {stage="zone_source";set(value.sources.map{choice($0.id,$0.title)},label:"Choose source time zone")}
      else {
        sourceZone=value.sources[0]
        if value.explicitDate != nil { stage="explicit_date" }
        else { chooseDate() }
      }
    case .openMaps,.directions:
      guard let query=SelectedAddress.query(text) else{message="Select an address or a short place name.";return}
      searchPlaces(query)
    default: message="This action is unavailable."
    }
  }
  /// Delivery callbacks must run after the controller owns this session.
  func start() {
    guard !cancelled, stage == "explicit_date", let date = clock?.explicitDate else { return }
    stage = "complete"
    convertTime(date)
  }
  private func choice(_ id: String,_ title: String) -> ModeChoice { .init(id:id,title:title,label:title) }
  private func set(_ values: [ModeChoice],label: String) {
    self.label=label;allOptions=values;searchQuery="";page=0;showPage()
  }
  private func showPage() {
    let matches=allOptions.filter { searchQuery.isEmpty || ($0.title+" "+$0.label+" "+$0.help).localizedStandardContains(searchQuery) }
    options=Array(matches.dropFirst(page*3).prefix(3))
    if matches.count > 3 {options.append(choice("more","More"))}
    selectedID=options.first?.id
  }
  func search(_ query: String) { searchQuery=String(query.prefix(80));page=0;showPage() }
  var presentation: ModeChoicePresentation {
    .init(step:.init(label:label,choices:options,selectedID:selectedID),activityTitle:busy ? action.title:nil,
      searchQuery:allOptions.count>3 ? searchQuery:nil,search:allOptions.count>3 ? {[weak self] in self?.search($0)}:nil,
      select:{[weak self] in self?.selectedID=$0},perform:{[weak self] in self?.perform($0)})
  }
  private func unitTargets() {
    guard let sourceUnit else{return};stage="unit_target"
    set(UnitQuantity.units.filter{$0.dimension==sourceUnit.dimension && $0.id != sourceUnit.id}.map{choice($0.id,$0.title)},label:"\(SelectionQuantity.formatted(units?.value ?? 0)) \(sourceUnit.title) →")
  }
  private func currencyTargets() {
    stage="currency_target";set(CurrencyQuantity.codes.filter{$0 != sourceCurrency}.map{currencyChoice($0)},label:"Convert from \(sourceCurrency ?? "")")
  }
  private func currencyChoice(_ code: String) -> ModeChoice {
    .init(id:code,title:code,label:CurrencyQuantity.searchTerms(code),help:CurrencyQuantity.searchTerms(code))
  }
  private func chooseDate() {
    guard let clock else{return}
    if let date=clock.explicitDate {convertTime(date);return}
    stage="date";set([choice("today","Today"),choice("tomorrow","Tomorrow"),choice("date","Pick date")],label:"Which date in \(sourceZone?.title ?? "source zone")?")
  }
  private func localDate(_ date: Date) -> String {
    let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.timeZone=sourceZone?.zone ?? .current;f.dateFormat="yyyy-MM-dd";return f.string(from:date)
  }
  private func convertTime(_ date: String) {
    guard let clock,let sourceZone else{return}
    let local=SelectionTimeZone(id:TimeZone.current.identifier,title:"Local · \(TimeZone.current.identifier)")
    guard let value=clock.result(on:date,source:sourceZone,target:local) else {
      message="This local time is repeated or does not exist because of a clock change. Choose an explicit UTC offset.";return
    }
    result(value)
  }
  private func perform(_ id: String?) {
    guard !busy,!cancelled else{return}
    guard let id else {
      if choosingDate {choosingDate=false;chooseDate()}
      else if stage=="unit_target",let units,units.sources.count>1 {stage="unit_source";set(units.sources.map{choice($0.id,$0.title)},label:"Choose source unit")}
      else if stage=="currency_target",let money,money.sources.count != 1 {stage="currency_source";set((money.sources.isEmpty ? CurrencyQuantity.codes:money.sources).map{currencyChoice($0)},label:"Choose source currency")}
      else if stage=="date",let clock,clock.sources.count>1 {stage="zone_source";set(clock.sources.map{choice($0.id,$0.title)},label:"Choose source time zone")}
      else{back()};return
    }
    guard options.contains(where:{$0.id==id && $0.enabled}) else{return}
    if id=="more" {
      let count=allOptions.filter{searchQuery.isEmpty || ($0.title+" "+$0.label+" "+$0.help).localizedStandardContains(searchQuery)}.count
      page=(page+1)%max(1,(count+2)/3);showPage();return
    }
    switch stage {
    case "unit_source":sourceUnit=UnitQuantity.units.first{$0.id==id};unitTargets()
    case "unit_target":
      guard let units,let sourceUnit,let target=UnitQuantity.units.first(where:{$0.id==id}),let value=sourceUnit.convert(units.value,to:target) else{message="This quantity cannot be converted.";return}
      result("\(SelectionQuantity.formatted(units.value)) \(sourceUnit.title) = \(SelectionQuantity.formatted(value)) \(target.title)")
    case "currency_source":sourceCurrency=id;currencyTargets()
    case "currency_target":fetchRate(id)
    case "zone_source":sourceZone=clock?.sources.first{$0.id==id};chooseDate()
    case "date":
      if id=="date" {choosingDate=true;stage="custom_date";set([choice("convert","Convert")],label:"Choose the source date")}
      else {
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=sourceZone?.zone ?? .current
        convertTime(localDate(id=="tomorrow" ? calendar.date(byAdding:.day,value:1,to:.now) ?? .now:.now))
      }
    case "custom_date":convertTime(localDate(date))
    case "places":
      guard let index=Int(id),mapItems.indices.contains(index) else{return}
      let item=mapItems[index]
      if services.open(item, directions: action == .directions) {opened()} else{message="Couldn't open Apple Maps."}
    default:break
    }
  }
  private func fetchRate(_ target: String) {
    guard let sourceCurrency,let money else{return};busy=true;message=nil
    operation=Task{[weak self] in
      guard let self else{return}
      do {
        let rate=try await services.rate(source:sourceCurrency,target:target)
        try Task.checkCancellation()
        guard !cancelled,let amount=rate.converted(money.value,source:sourceCurrency,target:target) else{throw URLError(.badServerResponse)}
        busy=false
        let format=NumberFormatter();format.locale=Locale(identifier:"en_US_POSIX");format.numberStyle = .decimal;format.usesGroupingSeparator=false;format.maximumFractionDigits=target=="JPY" || target=="KRW" ? 0:2
        let value=format.string(from:NSDecimalNumber(decimal:amount)) ?? NSDecimalNumber(decimal:amount).stringValue
        let link=rate.provider=="Exchange API" ? "https://github.com/fawazahmed0/exchange-api":"https://frankfurter.dev/"
        result("\(NSDecimalNumber(decimal:money.value).stringValue) \(sourceCurrency) ≈ \(value) \(target)\n\n\(rate.provider) · \(rate.date)\n1 \(sourceCurrency) = \(NSDecimalNumber(decimal:rate.rate).stringValue) \(target)\n[Reference rate](\(link))")
      } catch {
        guard !cancelled,!Task.isCancelled else{return};busy=false;message="Couldn't get a recent reference rate. Try again."
      }
    }
  }
  private func searchPlaces(_ query: String) {
    busy=true
    operation=Task{[weak self] in
      do {
        guard let self else { return }
        let values=try await services.places(query:query);try Task.checkCancellation()
        guard !cancelled else{return};busy=false
        mapItems=values
        guard !mapItems.isEmpty else{message="No matching place found. Select a more complete address.";return}
        stage="places"
        set(mapItems.enumerated().map{ index,item in
          let address=[item.placemark.subThoroughfare,item.placemark.thoroughfare,item.placemark.locality,item.placemark.country].compactMap{$0}.joined(separator:" ")
          return .init(id:String(index),title:String((item.name ?? address).prefix(30)),label:address,help:address)
        },label:action == .directions ? "Choose destination":"Choose location")
      }catch{guard let self,!cancelled,!Task.isCancelled else{return};busy=false;message="Couldn't find this location. Try again."}
    }
  }
  func cancel(){cancelled=true;operation?.cancel();services.cancel()}
}
