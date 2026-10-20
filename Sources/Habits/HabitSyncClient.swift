import Foundation

struct HabitSyncClient: Sendable {
    private let transport: URLSession
    init(transport: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        self.transport = transport ?? URLSession(configuration: configuration)
    }
    func fetch(owner: UUID, token: String) async throws -> [CloudHabit] {
        let data = try await request(owner: owner, token: token, method: "GET",
                                     query: [URLQueryItem(name: "select", value: "id,user_id,name,enabled,definition"),
                                             URLQueryItem(name: "order", value: "created_at,id"),
                                             URLQueryItem(name: "limit", value: "51")])
        return try JSONDecoder().decode([CloudHabit].self, from: data)
    }
    func save(_ habit: TextHabit, owner: UUID, token: String) async throws {
        _ = try await request(owner: owner, token: token, method: "POST",
                              query: [URLQueryItem(name: "on_conflict", value: "id")],
                              body: JSONEncoder().encode(CloudHabit(habit, owner: owner)))
    }
    func remove(_ id: UUID, owner: UUID, token: String) async throws {
        _ = try await request(owner: owner, token: token, method: "DELETE",
                              query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")])
    }
    private func request(owner: UUID, token: String, method: String, query: [URLQueryItem], body: Data? = nil) async throws -> Data {
        var url = URLComponents(url: AuthConfiguration.projectURL.appendingPathComponent("rest/v1/tero_habits"), resolvingAgainstBaseURL: false)!
        url.queryItems = query + (method == "POST" ? [] : [URLQueryItem(name: "user_id", value: "eq.\(owner.uuidString)")])
        var request = URLRequest(url: url.url!)
        request.httpMethod = method; request.httpBody = body
        request.timeoutInterval = 12; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(AuthConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        let (data, response) = try await transport.data(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode), data.count <= 1_000_000 else {
            throw AuthFailure.unavailable
        }
        return data
    }
}
