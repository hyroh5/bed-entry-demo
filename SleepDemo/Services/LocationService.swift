import CoreLocation
import Foundation
import Observation

/// 측정 중 위치 수신 (기록 전용, 판정에는 쓰지 않음).
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
