import Foundation
@main struct Smoke {
 static func check(_ value: Bool) { precondition(value) }
 static func main() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let repo = TextHabitRepository(url: directory.appendingPathComponent("habits.json"))
  check(try repo.load().isEmpty)
  var h = TextHabit(); h.name = " My voice "; h.instruction = " Keep it short. "; h.output = .reading; h.enabled = false
  h = h.normalized(); precondition(h.name == "My voice" && h.instruction == "Keep it short.")
  try repo.save([h]); check(try repo.load() == [h])
  let saved = try Data(contentsOf: repo.url)
  for list in [[h,h], [TextHabit()], (0..<51).map { _ in var v=h; v.id=UUID(); return v }] {
   do { try repo.save(list); fatalError("Invalid habit archive accepted") } catch TextHabitRepository.Failure.invalidArchive {}
   check(try Data(contentsOf: repo.url) == saved)
  }
  var long=h; long.instruction=String(repeating:"x",count:1001); precondition(!long.isValid)
  try Data("{\"version\":2,\"habits\":[]}".utf8).write(to: repo.url)
  do { _ = try repo.load(); fatalError("Unknown version accepted") } catch TextHabitRepository.Failure.invalidArchive {}
  check(try String(contentsOf:repo.url,encoding:.utf8).contains("\"version\":2"))
  print("Text habit persistence: passed")
 }
}
