import Observation
import UIKit

/// 충전 상태(`UIDevice.batteryState`)와 앱 활성 상태(`scenePhase`).
/// 앱 비활성은 "화면이 꺼졌다"는 뜻이 아니다 — 측정 일시 중지 신호로만 쓴다.
@Observable @MainActor
final class DeviceStateService {
    private(set) var battery: BatteryStatus = .unknown
    var isAppActive = true

    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshBattery()
        observer = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBattery() }
        }
    }

    private func refreshBattery() {
        battery = switch UIDevice.current.batteryState {
        case .charging: .charging
        case .full: .full
        case .unplugged: .unplugged
        case .unknown: .unknown
        @unknown default: .unknown
        }
    }
}
