import Foundation
import SwiftUI
import CoreLocation
import Security

// API still runs on the self-hosted Node backend. All screens below are native SwiftUI.
struct MapPoint: Decodable {
    let lat: Double
    let lon: Double
}

struct HiddenLetter: Identifiable, Decodable {
    let id: String
    let status: String
    let hint: String
    let area: HintArea?
    let place: String?
    let lat: Double?
    let lon: Double?
    let body: String?
    let createdAt: String?
    let openedAt: String?

    struct HintArea: Decodable {
        let lat: Double
        let lon: Double
        let r: Double?
    }

    var coordinate: CLLocationCoordinate2D? {
        if let lat, let lon { return .init(latitude: lat, longitude: lon) }
        if let area { return .init(latitude: area.lat, longitude: area.lon) }
        return nil
    }
    var isSealed: Bool { status == "sealed" }
}

struct MapStop: Identifiable, Decodable {
    let id: String
    let name: String
    let date: String
    let lat: Double
    let lon: Double
}

struct TreasureMap: Decodable {
    let letters: [HiddenLetter]
    let stops: [MapStop]
}

struct DateMemory: Identifiable, Decodable {
    let id: String
    let title: String
    let date: String
    let place: String
    let note: String
    let photos: [String]
    let createdAt: String
}

struct DateListResult: Decodable {
    let dates: [DateMemory]
}
struct NewDateResult: Decodable {
    let ok: Bool
    let entry: DateMemory
}
struct NewDatePayload: Encodable {
    let title: String
    let date: String
    let place: String
    let note: String
    let photos: [String]
}
struct DateCardRating: Codable, Identifiable {
    let key: String
    let title: String
    var id: String { key }
}

struct DateCard: Codable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let date: String
    let place: String
    let intro: String
    let status: String
    let ratings: [DateCardRating]
    let createdAt: String
    let submittedAt: String?
    let answers: DateCardAnswers?
    let agentNote: String?
    let agentNoteAt: String?
    let notification: String?
}

struct DateCardAnswers: Codable {
    let whereTo: String?
    let lookingForward: String?
    let mood: String?
    let needs: String?
    let ratings: [String: Double]?
    let favorite: String?
    let nextTime: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case whereTo = "where"
        case lookingForward, mood, needs, ratings, favorite, nextTime, note
    }
}

struct DateCardListResult: Decodable {
    let cards: [DateCard]
}
struct DateCardResult: Decodable {
    let ok: Bool?
    let card: DateCard
}

// Explicit sharing, separate from the legacy passive tracking API.
// The server keeps only the latest point for 24h, and allows revocation.
struct ManualLocationPayload: Encodable {
    let lat: Double
    let lon: Double
    let acc: Double
}

struct SharedLocation: Decodable {
    let lat: Double
    let lon: Double
    let acc: Double
    let at: String
    let expiresAt: String
}

struct SharedLocationResponse: Decodable {
    let ok: Bool?
    let shared: SharedLocation?
}

struct LetterOpenPayload: Encodable {
    let lat: Double
    let lon: Double
    let acc: Double
}
struct LetterOpenResult: Decodable {
    let ok: Bool
    let awayM: Int?
    let counted: Bool?
    let visits: Int?
    let visitsNeeded: Int?
    let letter: HiddenLetter?
}
struct APIErrorMessage: Decodable {
    let error: String?
}

enum LoveMapError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "请输入以 https:// 开头的服务器地址"
        case .invalidResponse: return "服务器没有返回有效数据"
        case .server(let message): return message
        }
    }
}

struct LoveMapAPI {
    let root: URL
    let token: String

    private func requestData(path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: root.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        request.timeoutInterval = 25
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LoveMapError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = try? JSONDecoder().decode(APIErrorMessage.self, from: data).error
            if http.statusCode == 401 { throw LoveMapError.server("密码不对，或者服务器尚未部署最新版本") }
            throw LoveMapError.server(message ?? "请求失败（HTTP \(http.statusCode)）")
        }
        return data
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await requestData(path: path)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<Payload: Encodable, Result: Decodable>(_ path: String, payload: Payload) async throws -> Result {
        let data = try await requestData(path: path, method: "POST", body: try JSONEncoder().encode(payload))
        return try JSONDecoder().decode(Result.self, from: data)
    }

    func currentSharedLocation() async throws -> SharedLocation? {
        let result: SharedLocationResponse = try await get("/api/location/share")
        return result.shared
    }

    func shareLocationOnce(_ location: CLLocation) async throws -> SharedLocation {
        let payload = ManualLocationPayload(
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            acc: location.horizontalAccuracy
        )
        let result: SharedLocationResponse = try await post("/api/location/share", payload: payload)
        guard let shared = result.shared else { throw LoveMapError.invalidResponse }
        return shared
    }

    func revokeSharedLocation() async throws {
        let data = try await requestData(path: "/api/location/share", method: "DELETE")
        let result = try JSONDecoder().decode(SharedLocationResponse.self, from: data)
        guard result.ok == true && result.shared == nil else { throw LoveMapError.invalidResponse }
    }

    func treasureMap() async throws -> TreasureMap { try await get("/api/travel-map") }
    func dates() async throws -> [DateMemory] {
        let result: DateListResult = try await get("/api/dates")
        return result.dates
    }
    func addDate(_ payload: NewDatePayload) async throws -> DateMemory {
        let result: NewDateResult = try await post("/api/dates", payload: payload)
        return result.entry
    }
    func dateCards() async throws -> [DateCard] {
        let result: DateCardListResult = try await get("/api/date-cards")
        return result.cards
    }
    func submitDateCard(id: String, answers: DateCardAnswers) async throws -> DateCard {
        let result: DateCardResult = try await post("/api/date-cards/\(id)/submit", payload: answers)
        return result.card
    }

    func openLetter(_ id: String, position: CLLocation) async throws -> LetterOpenResult {
        let p = LetterOpenPayload(lat: position.coordinate.latitude,
                                  lon: position.coordinate.longitude,
                                  acc: max(0, position.horizontalAccuracy))
        return try await post("/api/travel-map/letters/\(id)/open", payload: p)
    }
    func photo(named name: String) async throws -> UIImage {
        let data = try await requestData(path: "/api/dates/photos/\(name)")
        guard let image = UIImage(data: data) else { throw LoveMapError.invalidResponse }
        return image
    }
}

enum SecretStore {
    private static let account = "ZFxFLoveMapServerPassword"
    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }
    static func save(_ password: String) {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(match as CFDictionary)
        let attrs: [String: Any] = match.merging([
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]) { _, new in new }
        SecItemAdd(attrs as CFDictionary, nil)
    }
    static func clear() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ] as CFDictionary)
    }
}

@MainActor
final class LoveMapSession: ObservableObject {
    @Published var connected: Bool
    @Published var error: String?
    @Published var connecting = false
    @Published var serverAddress: String

    init() {
        let address = UserDefaults.standard.string(forKey: "zfxf.server") ?? "https://memory.ryanecho.xyz/zfxf"
        serverAddress = address
        connected = address.hasPrefix("https://") && !SecretStore.load().isEmpty
    }

    var api: LoveMapAPI? {
        guard connected, let url = URL(string: serverAddress) else { return nil }
        return LoveMapAPI(root: url, token: SecretStore.load())
    }

    func connect(address: String, password: String) async {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed), url.scheme == "https", url.host != nil else {
            error = LoveMapError.invalidAddress.localizedDescription
            return
        }
        guard !password.isEmpty else { error = "请输入藏宝地图的密码"; return }
        connecting = true
        error = nil
        defer { connecting = false }
        do {
            _ = try await LoveMapAPI(root: url, token: password).treasureMap()
            serverAddress = trimmed
            UserDefaults.standard.set(trimmed, forKey: "zfxf.server")
            SecretStore.save(password)
            connected = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    func disconnect() {
        connected = false
        SecretStore.clear()
    }
}

@MainActor
final class TreasureLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var notice: String?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }
    func locate() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default: notice = "请在 iPhone 设置里允许定位，才能在到达地点时拆信。"
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let newest = locations.last { location = newest; notice = nil }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        notice = "暂时没有拿到位置，等一会儿再试试。"
    }
}
