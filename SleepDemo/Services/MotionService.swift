import CoreMotion
import Foundation

/// Core Motion `CMDeviceMotion` 수집. 시뮬레이터에서는 사용할 수 없다 (실제 기기 테스트 대상).
@MainActor
final class MotionService {
    private let manager = CMMotionManager()

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start(hz: Double, onSample: @escaping @MainActor (MotionSample) -> Void) {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / max(1, hz)
        // CMLogItem.timestamp는 부팅 후 경과 시간이므로 벽시계 시각으로 변환한다.
        let bootTime = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        manager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let m = motion else { return }
            let sample = MotionSample(
                t: Date(timeIntervalSince1970: bootTime + m.timestamp),
                pitch: m.attitude.pitch, roll: m.attitude.roll, yaw: m.attitude.yaw,
                gx: m.gravity.x, gy: m.gravity.y, gz: m.gravity.z,
                ax: m.userAcceleration.x, ay: m.userAcceleration.y, az: m.userAcceleration.z,
                rx: m.rotationRate.x, ry: m.rotationRate.y, rz: m.rotationRate.z,
                battery: .unknown
            )
            MainActor.assumeIsolated { onSample(sample) }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
