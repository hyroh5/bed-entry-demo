import Foundation

/// 최근 구간 센서 통계량 계산. 안정 유지 시간만 샘플 단위로 누적한다.
struct FeatureExtractor {
    private(set) var stableSince: Date?

    mutating func reset() { stableSince = nil }

    mutating func ingest(_ s: MotionSample, rules: RuleConfig) {
        let isStable = s.accMagnitude < rules.stableAccThreshold && s.gyroMagnitude < rules.stableGyroThreshold
        if isStable {
            if stableSince == nil { stableSince = s.t }
        } else {
            stableSince = nil
        }
    }

    func features(recent: [MotionSample], now: Date, windowSeconds: Double) -> WindowFeatures? {
        let start = now.addingTimeInterval(-windowSeconds)
        let window = recent.filter { $0.t >= start }
        guard !window.isEmpty else { return nil }

        let acc = Self.meanAndVariance(window.map(\.accMagnitude))
        let gyro = Self.meanAndVariance(window.map(\.gyroMagnitude))

        let n = Double(window.count)
        var gx = window.reduce(0) { $0 + $1.gx } / n
        var gy = window.reduce(0) { $0 + $1.gy } / n
        var gz = window.reduce(0) { $0 + $1.gz } / n
        let norm = (gx * gx + gy * gy + gz * gz).squareRoot()
        if norm > 0 { gx /= norm; gy /= norm; gz /= norm }
        let tilt = Self.tiltAngles(gx: gx, gy: gy, gz: gz)

        return WindowFeatures(
            sampleCount: window.count,
            windowSeconds: windowSeconds,
            accMean: acc.mean, accVar: acc.variance,
            gyroMean: gyro.mean, gyroVar: gyro.variance,
            gravityX: gx, gravityY: gy, gravityZ: gz,
            screenTiltDeg: tilt.screen, lateralTiltDeg: tilt.lateral, horizontalG: tilt.horizontal,
            stableDuration: stableSince.map { max(0, now.timeIntervalSince($0)) } ?? 0
        )
    }

    static func meanAndVariance(_ xs: [Double]) -> (mean: Double, variance: Double) {
        guard !xs.isEmpty else { return (0, 0) }
        let n = Double(xs.count)
        let mean = xs.reduce(0, +) / n
        let variance = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
        return (mean, variance)
    }

    /// 정규화된 중력 벡터(기기 좌표계, z는 화면 바깥 방향)로 기기 기울기를 구한다.
    /// 이 값은 기기의 자세이며 사용자의 신체 자세가 아니다.
    static func tiltAngles(gx: Double, gy: Double, gz: Double) -> (screen: Double, lateral: Double, horizontal: Double) {
        let screen = acos(min(1, max(-1, -gz))) * 180 / .pi
        let lateral = atan2(abs(gx), abs(gy)) * 180 / .pi
        let horizontal = (gx * gx + gy * gy).squareRoot()
        return (screen, lateral, horizontal)
    }
}
