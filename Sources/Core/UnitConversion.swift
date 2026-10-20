import Foundation

struct ConversionUnit: Equatable, Sendable, Identifiable {
  enum Dimension: Sendable { case length, mass, volume, temperature, speed }
  let id: String
  let dimension: Dimension
  let title: String
  let aliases: [String]
  let factor: Double
  var offset: Double = 0
  func convert(_ value: Double, to target: Self) -> Double? {
    guard dimension == target.dimension else { return nil }
    let base = value * factor + offset
    guard dimension != .temperature || base >= -273.15 else { return nil }
    let result = (base - target.offset) / target.factor
    return result.isFinite ? result : nil
  }
}
struct UnitQuantity: Sendable {
  let value: Double
  let sources: [ConversionUnit]
  static func parse(_ text: String) -> Self? {
    guard let parts = SelectionQuantity.parts(text) else { return nil }
    let sources = units.filter { $0.aliases.contains(parts.suffix) }
    return sources.isEmpty ? nil : .init(value: parts.amount, sources: sources)
  }
  static let units: [ConversionUnit] = [
    .init(id: "km", dimension: .length, title: "km", aliases: ["km","kilometer","kilometers","kilometre","kilometres","kilomètres"], factor: 1000),
    .init(id: "mi", dimension: .length, title: "mi", aliases: ["mi","mile","miles"], factor: 1609.344),
    .init(id: "m", dimension: .length, title: "m", aliases: ["m","meter","meters","metre","metres","mètres"], factor: 1),
    .init(id: "ft", dimension: .length, title: "ft", aliases: ["ft","feet","foot"], factor: 0.3048),
    .init(id: "cm", dimension: .length, title: "cm", aliases: ["cm","centimeters","centimetres"], factor: 0.01),
    .init(id: "in", dimension: .length, title: "in", aliases: ["in","inch","inches"], factor: 0.0254),
    .init(id: "mm", dimension: .length, title: "mm", aliases: ["mm","millimeters","millimetres"], factor: 0.001),
    .init(id: "yd", dimension: .length, title: "yd", aliases: ["yd","yard","yards"], factor: 0.9144),
    .init(id: "nmi", dimension: .length, title: "nmi", aliases: ["nmi","nautical miles"], factor: 1852),
    .init(id: "kg", dimension: .mass, title: "kg", aliases: ["kg","kilogram","kilograms","kilo","kilos"], factor: 1),
    .init(id: "lb", dimension: .mass, title: "lb", aliases: ["lb","lbs","pound","pounds"], factor: 0.45359237),
    .init(id: "g", dimension: .mass, title: "g", aliases: ["g","gram","grams","grammes"], factor: 0.001),
    .init(id: "oz", dimension: .mass, title: "oz", aliases: ["oz","ounce","ounces"], factor: 0.028349523125),
    .init(id: "t", dimension: .mass, title: "tonne", aliases: ["t","tonne","tonnes","metric ton","ton"], factor: 1000),
    .init(id: "us_ton", dimension: .mass, title: "US ton", aliases: ["us ton","short ton","ton"], factor: 907.18474),
    .init(id: "uk_ton", dimension: .mass, title: "UK ton", aliases: ["uk ton","long ton","ton"], factor: 1016.0469088),
    .init(id: "l", dimension: .volume, title: "L", aliases: ["l","liter","liters","litre","litres"], factor: 1),
    .init(id: "ml", dimension: .volume, title: "mL", aliases: ["ml","milliliter","millilitres"], factor: 0.001),
    .init(id: "us_gal", dimension: .volume, title: "US gal", aliases: ["us gal","us gallon","gal","gallon","gallons"], factor: 3.785411784),
    .init(id: "uk_gal", dimension: .volume, title: "UK gal", aliases: ["uk gal","imperial gallon","gal","gallon","gallons"], factor: 4.54609),
    .init(id: "us_fl_oz", dimension: .volume, title: "US fl oz", aliases: ["us fl oz","fl oz","fluid ounce"], factor: 0.0295735295625),
    .init(id: "uk_fl_oz", dimension: .volume, title: "UK fl oz", aliases: ["uk fl oz","fl oz","fluid ounce"], factor: 0.0284130625),
    .init(id: "c", dimension: .temperature, title: "°C", aliases: ["°c","celsius","c"], factor: 1),
    .init(id: "f", dimension: .temperature, title: "°F", aliases: ["°f","fahrenheit","f"], factor: 5.0/9, offset: -32 * 5.0/9),
    .init(id: "k", dimension: .temperature, title: "K", aliases: ["k","kelvin"], factor: 1, offset: -273.15),
    .init(id: "kmh", dimension: .speed, title: "km/h", aliases: ["km/h","kph","kmh"], factor: 1.0/3.6),
    .init(id: "mph", dimension: .speed, title: "mph", aliases: ["mph"], factor: 0.44704),
    .init(id: "ms", dimension: .speed, title: "m/s", aliases: ["m/s"], factor: 1),
    .init(id: "kn", dimension: .speed, title: "kn", aliases: ["kn","kt","knot","knots"], factor: 1852.0/3600)
  ]
}
