import Foundation
import Observation

struct AppSettings: Codable, Equatable {
    /// 집 좌표. 위치 기록마다 집까지 거리를 계산하는 데만 쓰고, 세션에는 저장하지 않는다.
    var homeLatitude: Double?
    var homeLongitude: Double?
    var samplingHz = 20.0
}

/// UserDefaults에 JSON으로 저장되는 설정 저장소.
@Observable @MainActor
final class SettingsStore {
    var app: AppSettings { didSet { Self.save(app, key: Self.appKey) } }

    private static let appKey = "settings.app.v1"

    init() {
        app = Self.load(AppSettings.self, key: Self.appKey) ?? AppSettings()
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
