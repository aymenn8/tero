import Foundation

struct CurrencyQuantity: Sendable {
  let value: Decimal
  let sources: [String]
  static let codes = ["EUR","USD","GBP","MAD","CHF","CAD","AUD","JPY","CNY","INR","KRW","BRL","MXN","SEK","NOK","DKK","PLN","TRY","ZAR","NZD","SGD","HKD"]
  static func searchTerms(_ code: String) -> String {
    let names = ["EUR":"euro", "USD":"US dollar dollar américain", "GBP":"British pound livre sterling", "MAD":"Moroccan dirham dirham marocain dh dhs", "CHF":"Swiss franc franc suisse", "CAD":"Canadian dollar", "AUD":"Australian dollar", "JPY":"Japanese yen", "CNY":"Chinese yuan", "INR":"Indian rupee", "KRW":"Korean won"]
    return code + " " + (names[code] ?? "")
  }
  static func parse(_ text: String) -> Self? {
    var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    var sources: [String] = []
    for alias in ["DHS", "DH"] {
      if text.uppercased().hasSuffix(alias) { sources=["MAD"];text=String(text.dropLast(alias.count));break }
      if text.uppercased().hasPrefix(alias) { sources=["MAD"];text=String(text.dropFirst(alias.count));break }
    }
    let symbols: [(String,[String])] = [("US$",["USD"]),("CA$",["CAD"]),("A$",["AUD"]),("€",["EUR"]),("£",["GBP"]),("$",["USD","CAD","AUD","NZD","SGD","HKD"]),("¥",["JPY","CNY"]),("₹",["INR"])]
    for (symbol, codes) in symbols {
      if text.hasPrefix(symbol) { sources=codes; text=String(text.dropFirst(symbol.count)); break }
      if text.hasSuffix(symbol) { sources=codes; text=String(text.dropLast(symbol.count)); break }
    }
    if sources.isEmpty {
      for code in codes {
        if text.uppercased().hasPrefix(code) { sources=[code];text=String(text.dropFirst(3));break }
        if text.uppercased().hasSuffix(code) { sources=[code];text=String(text.dropLast(3));break }
      }
    }
    guard let parts = SelectionQuantity.parts(text), parts.suffix.isEmpty else { return nil }
    guard let amount = Decimal(string: text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")), !amount.isNaN else { return nil }
    return .init(value: amount, sources: sources)
  }
}
struct CurrencyRate: Decodable, Sendable {
  let date: String
  let base: String
  let quote: String
  let rate: Decimal
  var provider = "Frankfurter"
  enum CodingKeys: String, CodingKey { case date, base, quote, rate }
  func converted(_ amount: Decimal, source: String, target: String, now: Date = .now) -> Decimal? {
    guard base == source, quote == target, source != target, rate > 0,
          let dateComponents = CommitmentDraft.components(date: date, time: nil), let day = dateComponents.date,
          day.timeIntervalSince(now) <= 86400, now.timeIntervalSince(day) < 10 * 86400 else { return nil }
    let result = amount * rate
    return result.isNaN ? nil : result
  }
}

/// Daily public snapshot fallback; only the base code is requested, never an amount.
struct CurrencySnapshot: Decodable {
  let date: String
  let base: String
  let rates: [String: Decimal]
  struct Key: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue=stringValue }
    init?(intValue: Int) { return nil }
  }
  init(from decoder: any Decoder) throws {
    let container=try decoder.container(keyedBy: Key.self)
    date=try container.decode(String.self,forKey:Key(stringValue:"date"))
    guard let key=container.allKeys.first(where: { CurrencyQuantity.codes.contains($0.stringValue.uppercased()) }) else {
      throw DecodingError.dataCorrupted(.init(codingPath:decoder.codingPath,debugDescription:"Missing base currency"))
    }
    base=key.stringValue.uppercased()
    rates=try container.decode([String:Decimal].self,forKey:key)
  }
  func rate(source: String, target: String) -> CurrencyRate? {
    guard base==source,let value=rates[target.lowercased()],value>0 else{return nil}
    return CurrencyRate(date:date,base:source,quote:target,rate:value,provider:"Exchange API")
  }
}
