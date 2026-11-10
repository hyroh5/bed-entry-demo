import Foundation

/// 센서 샘플 1개. 저장(배치)·내보내기·실시간 분석에 공통으로 쓴다.
struct MotionSample: Codable, Sendable {
    var t: Date
    // attitude (rad)
    var pitch: Double
    var roll: Double
    var yaw: Double
    // gravity (g)
    var gx: Double
    var gy: Double
    var gz: Double
    // userAcceleration (g)
    var ax: Double
    var ay: Double
    var az: Double
    // rotationRate (rad/s)
    var rx: Double
    var ry: Double
    var rz: Double
    var battery: BatteryStatus

    var accMagnitude: Double { (ax * ax + ay * ay + az * az).squareRoot() }
    var gyroMagnitude: Double { (rx * rx + ry * ry + rz * rz).squareRoot() }
}

enum BatteryStatus: String, Codable, Sendable {
    case charging, full, unplugged, unknown

    var label: String {
        switch self {
        case .charging: "충전 중"
        case .full: "완충"
        case .unplugged: "미충전"
        case .unknown: "알 수 없음"
        }
    }
}
