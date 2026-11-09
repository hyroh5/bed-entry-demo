import CoreLocation
import Foundation
import Observation

/// Core Location 기반 집 위치 하드 게이트.
@Observable @MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var lastLocation: CLLocation?
    private(set) var lastError: String?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var isUpdating = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        authorization = manager.authorizationStatus
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    /// 연속 위치 업데이트를 켜거나 끈다 (중복 호출 무시).
    func setActive(_ active: Bool) {
        if active, !isUpdating {
            if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
            manager.startUpdatingLocation()
            isUpdating = true
        } else if !active, isUpdating {
            manager.stopUpdatingLocation()
            isUpdating = false
        }
    }

    /// 1회 위치 요청 (설정 화면에서 집 위치 지정용).
    func requestOnce() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.requestLocation()
    }

    func gate(settings: AppSettings, rules: RuleConfig, now: Date = Date()) -> (status: GateStatus, reason: String) {
        Self.evaluateGate(settings: settings, rules: rules, authorization: authorization, location: lastLocation, now: now)
    }

    static func evaluateGate(settings: AppSettings, rules: RuleConfig, authorization: CLAuthorizationStatus,
                             location: CLLocation?, now: Date) -> (status: GateStatus, reason: String) {
        guard settings.locationGateEnabled else { return (.disabled, "위치 제한 해제됨") }
        guard let lat = settings.homeLatitude, let lon = settings.homeLongitude else {
            return (.unknown, "집 위치 미설정")
        }
        switch authorization {
        case .denied, .restricted: return (.unknown, "위치 권한 없음")
        case .notDetermined: return (.unknown, "위치 권한 요청 전")
        default: break
        }
        guard let loc = location else { return (.unknown, "위치 수신 대기 중") }
        if loc.horizontalAccuracy < 0 || loc.horizontalAccuracy > rules.maxLocationAccuracy {
            return (.unknown, "위치 정확도 부족 (±\(Int(loc.horizontalAccuracy))m)")
        }
        if now.timeIntervalSince(loc.timestamp) > rules.maxLocationAgeSeconds {
            return (.unknown, "위치 정보가 오래됨")
        }
        let distance = loc.distance(from: CLLocation(latitude: lat, longitude: lon))
        return distance <= settings.homeRadius
            ? (.pass, "집 반경 내 (\(Int(distance))m)")
            : (.blocked, "집 반경 밖 (\(Int(distance))m)")
    }

    // MARK: CLLocationManagerDelegate (메인 스레드에서 생성했으므로 메인에서 호출됨)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated { self.authorization = status }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        MainActor.assumeIsolated {
            self.lastLocation = loc
            self.lastError = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        MainActor.assumeIsolated { self.lastError = message }
    }
}
