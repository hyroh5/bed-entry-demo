import CoreLocation
import Foundation
import Testing
@testable import SleepDemo

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func time(_ h: Int, _ m: Int) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: h, minute: m))!
}

private func features(count: Int = 200, screen: Double = 150, lateral: Double = 0, horizontal: Double = 0.3,
                      accMean: Double = 0.01, accVar: Double = 0.0001, gyroMean: Double = 0.02,
                      gyroVar: Double = 0.001, stable: Double = 120) -> WindowFeatures {
    WindowFeatures(sampleCount: count, windowSeconds: 10, accMean: accMean, accVar: accVar,
                   gyroMean: gyroMean, gyroVar: gyroVar, gravityX: 0, gravityY: 0, gravityZ: 1,
                   screenTiltDeg: screen, lateralTiltDeg: lateral, horizontalG: horizontal, stableDuration: stable)
}

private func input(_ now: Date, _ f: WindowFeatures?, gate: GateStatus = .pass, active: Bool = true) -> RuleInput {
    RuleInput(now: now, features: f, samplingHz: 20, targetBedtimeMinutes: 23 * 60 + 30,
              locationGate: gate, locationReason: "test", appActive: active)
}

struct BedtimeTests {
    @Test func minutesWrapAroundMidnight() {
        #expect(RuleEngine.minutesFromTarget(now: time(0, 15), targetMinutes: 23 * 60 + 30, calendar: utc) == 45)
        #expect(RuleEngine.minutesFromTarget(now: time(23, 0), targetMinutes: 30, calendar: utc) == -90)
        #expect(RuleEngine.minutesFromTarget(now: time(12, 0), targetMinutes: 0, calendar: utc) == -720)
    }

    @Test func scoreShape() {
        let r = RuleConfig() // plateau 30, before 120, after 240
        #expect(RuleEngine.bedtimeScore(minutesFromTarget: 0, rules: r) == 100)
        #expect(RuleEngine.bedtimeScore(minutesFromTarget: -30, rules: r) == 100)
        #expect(RuleEngine.bedtimeScore(minutesFromTarget: -75, rules: r) == 50)
        #expect(RuleEngine.bedtimeScore(minutesFromTarget: -120, rules: r) == 0)
        #expect(RuleEngine.bedtimeScore(minutesFromTarget: 135, rules: r) == 50)
        #expect(RuleEngine.bedtimeScore(minutesFromTarget: 300, rules: r) == 0)
    }
}

struct PostureAndMotionTests {
    @Test func tiltAnglesFromGravity() {
        let flatUp = FeatureExtractor.tiltAngles(gx: 0, gy: 0, gz: -1)
        #expect(abs(flatUp.screen) < 1e-9)
        let faceDown = FeatureExtractor.tiltAngles(gx: 0, gy: 0, gz: 1)
        #expect(abs(faceDown.screen - 180) < 1e-9)
        let portrait = FeatureExtractor.tiltAngles(gx: 0, gy: -1, gz: 0)
        #expect(abs(portrait.screen - 90) < 1e-9 && abs(portrait.lateral) < 1e-9)
        let sideways = FeatureExtractor.tiltAngles(gx: 1, gy: 0, gz: 0)
        #expect(abs(sideways.lateral - 90) < 1e-9 && abs(sideways.horizontal - 1) < 1e-9)
    }

    @Test func postureBands() {
        let r = RuleConfig()
        #expect(RuleEngine.postureScore(features(screen: 150), rules: r) == 90)
        #expect(RuleEngine.postureScore(features(screen: 10), rules: r) == 10)
        #expect(RuleEngine.postureScore(features(screen: 180), rules: r) == 90) // 마지막 경계 포함
        // 측면 기울기는 수평 성분이 충분할 때만 적용
        #expect(RuleEngine.postureScore(features(screen: 90, lateral: 80, horizontal: 0.9), rules: r) == 70)
        #expect(RuleEngine.postureScore(features(screen: 90, lateral: 80, horizontal: 0.3), rules: r) == 55)
    }

    @Test func motionStillVsMoving() {
        let r = RuleConfig()
        #expect(RuleEngine.motionScore(features(), rules: r) == 100)
        let walking = features(accMean: 0.2, accVar: 0.03, gyroMean: 0.8, gyroVar: 0.3, stable: 0)
        #expect(RuleEngine.motionScore(walking, rules: r) == 0)
    }

    @Test func varianceComputation() {
        let (m, v) = FeatureExtractor.meanAndVariance([1, 2, 3, 4])
        #expect(m == 2.5 && v == 1.25)
    }
}

struct JudgementTests {
    @Test func holdTimeRequired() {
        var engine = RuleEngine()
        var r = RuleConfig()
        r.holdSeconds = 60
        let start = time(23, 30)
        let a0 = engine.evaluate(input(start, features()), rules: r, calendar: utc)
        #expect(a0.rawState == .possiblyInBed && a0.state == .notInBed)
        let a1 = engine.evaluate(input(start.addingTimeInterval(30), features()), rules: r, calendar: utc)
        #expect(a1.state == .notInBed)
        let a2 = engine.evaluate(input(start.addingTimeInterval(60), features()), rules: r, calendar: utc)
        #expect(a2.state == .possiblyInBed)
        // 임계값 미만으로 떨어지면 유지 시간이 리셋된다
        let moving = features(screen: 40, accMean: 0.2, accVar: 0.03, gyroMean: 0.8, gyroVar: 0.3, stable: 0)
        let a3 = engine.evaluate(input(start.addingTimeInterval(61), moving), rules: r, calendar: utc)
        #expect(a3.state == .notInBed)
        let a4 = engine.evaluate(input(start.addingTimeInterval(62), features()), rules: r, calendar: utc)
        #expect(a4.state == .notInBed && a4.secondsAboveThreshold == 0)
    }

    @Test func gatesAndDataSufficiency() {
        var engine = RuleEngine()
        let r = RuleConfig()
        let now = time(23, 30)
        #expect(engine.evaluate(input(now, features(), gate: .blocked), rules: r, calendar: utc).state == .blocked)
        #expect(engine.evaluate(input(now, features(), active: false), rules: r, calendar: utc).state == .blocked)
        #expect(engine.evaluate(input(now, features(), gate: .unknown), rules: r, calendar: utc).state == .unknown)
        #expect(engine.evaluate(input(now, features(count: 100)), rules: r, calendar: utc).state == .unknown) // 20Hz*10s*0.8=160 미만
        #expect(engine.evaluate(input(now, nil), rules: r, calendar: utc).state == .unknown)
        // 위치 제한 해제 시 판정 진행
        #expect(engine.evaluate(input(now, features(), gate: .disabled), rules: r, calendar: utc).rawState == .possiblyInBed)
    }

    @Test func weightsNormalized() {
        #expect(RuleEngine.weighted([(100, 40), (0, 35), (100, 25)]) == 65)
        #expect(RuleEngine.weighted([(100, 0), (50, 0)]) == 0)
    }

    @Test func ruleVersionIsContentBased() {
        var r = RuleConfig()
        let v1 = r.version
        #expect(RuleConfig().version == v1)
        r.threshold = 75
        #expect(r.version != v1)
    }
}

@MainActor
struct LocationGateTests {
    private let home = (lat: 37.5665, lon: 126.9780)

    private func settings(enabled: Bool = true) -> AppSettings {
        var s = AppSettings()
        s.locationGateEnabled = enabled
        s.homeLatitude = home.lat
        s.homeLongitude = home.lon
        s.homeRadius = 150
        return s
    }

    private func loc(dLat: Double, accuracy: Double = 10, age: TimeInterval = 0, now: Date) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: home.lat + dLat, longitude: home.lon),
                   altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 10, timestamp: now.addingTimeInterval(-age))
    }

    @Test func gateStates() {
        let now = Date()
        let r = RuleConfig()
        let ok = CLAuthorizationStatus.authorizedWhenInUse
        func gate(_ s: AppSettings, _ a: CLAuthorizationStatus, _ l: CLLocation?) -> GateStatus {
            LocationService.evaluateGate(settings: s, rules: r, authorization: a, location: l, now: now).status
        }
        #expect(gate(settings(), ok, loc(dLat: 0.0005, now: now)) == .pass)       // 약 55m
        #expect(gate(settings(), ok, loc(dLat: 0.01, now: now)) == .blocked)      // 약 1.1km
        #expect(gate(settings(), ok, loc(dLat: 0, accuracy: 500, now: now)) == .unknown)
        #expect(gate(settings(), ok, loc(dLat: 0, age: 1000, now: now)) == .unknown)
        #expect(gate(settings(), .denied, loc(dLat: 0, now: now)) == .unknown)
        #expect(gate(settings(), ok, nil) == .unknown)
        #expect(gate(settings(enabled: false), .denied, nil) == .disabled)
        #expect(gate(AppSettings(), ok, loc(dLat: 0, now: now)) == .unknown)      // 집 미설정
    }
}
