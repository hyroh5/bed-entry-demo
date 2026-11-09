import Foundation

struct RuleInput {
    var now: Date
    var features: WindowFeatures?
    var samplingHz: Double
    var targetBedtimeMinutes: Int
    var locationGate: GateStatus
    var locationReason: String
    var appActive: Bool
}

/// 하드 게이트 + 고정 룰 점수 + 유지 시간 판정.
struct RuleEngine {
    private(set) var aboveSince: Date?

    mutating func reset() { aboveSince = nil }

    mutating func evaluate(_ input: RuleInput, rules: RuleConfig, calendar: Calendar = .current) -> Assessment {
        let minutes = Self.minutesFromTarget(now: input.now, targetMinutes: input.targetBedtimeMinutes, calendar: calendar)
        let bedtime = Self.bedtimeScore(minutesFromTarget: minutes, rules: rules)
        let posture = input.features.map { Self.postureScore($0, rules: rules) }
        let motion = input.features.map { Self.motionScore($0, rules: rules) }
        var totalScore: Double?
        if let posture, let motion {
            totalScore = Self.weighted([
                (posture, rules.weightPosture),
                (motion, rules.weightMotion),
                (bedtime, rules.weightBedtime),
            ])
        }

        var a = Assessment(timestamp: input.now, state: .unknown, rawState: .unknown,
                           total: totalScore, posture: posture, motion: motion, bedtime: bedtime,
                           locationGate: input.locationGate, appActive: input.appActive,
                           secondsAboveThreshold: 0, reason: "")

        // 1) 하드 게이트
        if !input.appActive {
            aboveSince = nil
            a.state = .blocked; a.rawState = .blocked; a.reason = "앱 비활성 — 측정 일시 중지"
            return a
        }
        if input.locationGate == .blocked {
            aboveSince = nil
            a.state = .blocked; a.rawState = .blocked; a.reason = input.locationReason
            return a
        }

        // 2) 데이터 충분성
        let required = input.samplingHz * rules.motionWindowSeconds * rules.minDataRatio
        let count = input.features?.sampleCount ?? 0
        guard Double(count) >= required, let total = totalScore else {
            aboveSince = nil
            a.reason = "센서 데이터 부족 (\(count)/\(Int(required.rounded(.up))))"
            return a
        }
        if input.locationGate == .unknown {
            aboveSince = nil
            a.reason = input.locationReason
            return a
        }

        // 3) 임계값 + 유지 시간
        if total >= rules.threshold {
            let since = aboveSince ?? input.now
            aboveSince = since
            let held = input.now.timeIntervalSince(since)
            a.secondsAboveThreshold = held
            a.rawState = .possiblyInBed
            if held >= rules.holdSeconds {
                a.state = .possiblyInBed
                a.reason = "임계값 이상 \(Int(held))초 유지"
            } else {
                a.state = .notInBed
                a.reason = "임계값 이상 — 유지 대기 \(Int(held))/\(Int(rules.holdSeconds))초"
            }
        } else {
            aboveSince = nil
            a.rawState = .notInBed
            a.state = .notInBed
            a.reason = "임계값 미만"
        }
        return a
    }

    // MARK: 점수 함수 (0~100)

    static func postureScore(_ f: WindowFeatures, rules: RuleConfig) -> Double {
        let screen = bandScore(f.screenTiltDeg, bands: rules.screenTiltBands) ?? 0
        var lateral = 0.0
        if f.horizontalG >= rules.lateralMinHorizontalG {
            lateral = bandScore(f.lateralTiltDeg, bands: rules.lateralTiltBands) ?? 0
        }
        return clamp(max(screen, lateral))
    }

    static func motionScore(_ f: WindowFeatures, rules: RuleConfig) -> Double {
        let acc = min(ramp(f.accMean, low: rules.accMeanLow, high: rules.accMeanHigh),
                      ramp(f.accVar, low: rules.accVarLow, high: rules.accVarHigh))
        let gyro = min(ramp(f.gyroMean, low: rules.gyroMeanLow, high: rules.gyroMeanHigh),
                       ramp(f.gyroVar, low: rules.gyroVarLow, high: rules.gyroVarHigh))
        let duration = rules.stableDurationForFull > 0 ? min(1, f.stableDuration / rules.stableDurationForFull) : 1
        return clamp(100 * weighted([
            (acc, rules.motionSubWeightAcc),
            (gyro, rules.motionSubWeightGyro),
            (duration, rules.motionSubWeightDuration),
        ]))
    }

    /// 목표 취침 시각 기준 현재 시각의 차이(분). 음수 = 목표 이전. 자정을 넘는 경우를 처리한다.
    static func minutesFromTarget(now: Date, targetMinutes: Int, calendar: Calendar) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second], from: now)
        let nowMinutes = Double(c.hour ?? 0) * 60 + Double(c.minute ?? 0) + Double(c.second ?? 0) / 60
        var d = (nowMinutes - Double(targetMinutes)).truncatingRemainder(dividingBy: 1440)
        if d >= 720 { d -= 1440 } else if d < -720 { d += 1440 }
        return d
    }

    static func bedtimeScore(minutesFromTarget d: Double, rules: RuleConfig) -> Double {
        let distance = abs(d)
        let edge = d < 0 ? rules.bedtimeWindowBeforeMinutes : rules.bedtimeWindowAfterMinutes
        let plateau = rules.bedtimePlateauMinutes
        if distance <= plateau { return 100 }
        if distance >= edge { return 0 }
        return 100 * (edge - distance) / (edge - plateau)
    }

    // MARK: 보조

    static func bandScore(_ value: Double, bands: [ScoreBand]) -> Double? {
        bands.first { value >= $0.minDeg && value < $0.maxDeg }?.score
            ?? bands.first { value == $0.maxDeg }?.score
    }

    /// low 이하 1, high 이상 0, 사이는 선형.
    static func ramp(_ v: Double, low: Double, high: Double) -> Double {
        if v <= low { return 1 }
        if v >= high { return 0 }
        return (high - v) / (high - low)
    }

    /// (값, 가중치) 가중 평균. 음수 가중치는 0으로 취급.
    static func weighted(_ pairs: [(Double, Double)]) -> Double {
        let sum = pairs.reduce(0) { $0 + max(0, $1.1) }
        guard sum > 0 else { return 0 }
        return pairs.reduce(0) { $0 + $1.0 * max(0, $1.1) } / sum
    }

    private static func clamp(_ v: Double) -> Double { min(100, max(0, v)) }
}
