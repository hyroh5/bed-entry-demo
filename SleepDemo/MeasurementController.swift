import Foundation
import Observation
import SwiftData

struct HistoryPoint: Identifiable {
    var id: Date { t }
    let t: Date
    let state: BedState
    let total: Double?
    let posture: Double?
    let motion: Double?
    let bedtime: Double?
    let accVar: Double?
    let gyroVar: Double?
}

/// 서비스들을 묶어 측정 세션을 진행한다.
/// 센서는 설정 주기(기본 20Hz)로 받고, UI는 4Hz, 판정·저장은 1Hz로 갱신한다.
@Observable @MainActor
final class MeasurementController {
    let settings: SettingsStore
    let location = LocationService()
    let device = DeviceStateService()

    private(set) var session: MeasurementSession?
    private(set) var isPaused = false
    private(set) var latest: MotionSample?
    private(set) var features: WindowFeatures?
    private(set) var assessment: Assessment?
    private(set) var chartSamples: [MotionSample] = []
    private(set) var history: [HistoryPoint] = []
    private(set) var message: String?

    var isMeasuring: Bool { session != nil }
    var motionAvailable: Bool { motionService.isAvailable }

    @ObservationIgnored private let motionService = MotionService()
    @ObservationIgnored private let repository: SessionRepository
    @ObservationIgnored private var recent: [MotionSample] = []
    @ObservationIgnored private var pending: [MotionSample] = []
    @ObservationIgnored private var latestInternal: MotionSample?
    @ObservationIgnored private var extractor = FeatureExtractor()
    @ObservationIgnored private var engine = RuleEngine()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var tickCount = 0
    @ObservationIgnored private var sessionHz = 20.0

    private let uiTickInterval = 0.25
    private let evaluateEveryTicks = 4
    private let chartSeconds = 30.0
    private let maxChartPoints = 150
    private let maxHistory = 1800
    private let flushSeconds = 5.0

    init(settings: SettingsStore, context: ModelContext) {
        self.settings = settings
        self.repository = SessionRepository(context: context)
    }

    // MARK: 세션 제어

    func start() {
        guard session == nil else { return }
        let app = settings.app
        sessionHz = app.samplingHz
        let gate = location.gate(settings: app, rules: settings.rules).status
        session = repository.createSession(settings: app, rules: settings.rules, initialGate: gate)

        recent.removeAll(); pending.removeAll(); history.removeAll(); chartSamples.removeAll()
        latestInternal = nil; latest = nil; features = nil; assessment = nil; tickCount = 0
        message = motionService.isAvailable ? nil
            : "이 기기에서는 Device Motion을 사용할 수 없습니다 (시뮬레이터). 센서 측정은 실제 iPhone에서 테스트하세요."

        if device.isAppActive { resumeSensors() } else { isPaused = true }
    }

    func stop() {
        guard let session else { return }
        pauseSensors()
        flush()
        repository.end(session)
        self.session = nil
        isPaused = false
    }

    /// scenePhase 변화. 비활성/백그라운드에서는 측정을 일시 중지한다.
    func setAppActive(_ active: Bool) {
        guard device.isAppActive != active else { return }
        device.isAppActive = active
        guard session != nil else { return }
        if active {
            resumeSensors()
        } else {
            pauseSensors()
            evaluateAndRecord(now: Date()) // BLOCKED(앱 비활성) 기록
            flush()
        }
    }

    func submitLabel(inBed: Bool) {
        guard let session else { return }
        let now = Date()
        let rules = settings.rules
        let cutoff = now.addingTimeInterval(-rules.labelContextSeconds)
        repository.addLabel(inBed: inBed, at: now, assessment: assessment, features: features,
                            context: recent.filter { $0.t >= cutoff }, contextSeconds: rules.labelContextSeconds,
                            ruleVersion: rules.version, to: session)
        let predicted = assessment?.state.rawValue ?? BedState.unknown.rawValue
        message = "응답 저장: \(inBed ? "예" : "아니요") · 당시 예측 \(predicted)"
    }

    // MARK: 내부

    private func resumeSensors() {
        isPaused = false
        // 데이터 공백 이후에는 윈도우·안정 시간·유지 시간을 새로 시작한다.
        recent.removeAll()
        extractor.reset()
        engine.reset()
        location.setActive(settings.app.locationGateEnabled)
        motionService.start(hz: sessionHz) { [weak self] sample in self?.ingest(sample) }
        let t = Timer(timeInterval: uiTickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func pauseSensors() {
        isPaused = true
        motionService.stop()
        location.setActive(false)
        timer?.invalidate()
        timer = nil
    }

    private func ingest(_ raw: MotionSample) {
        var s = raw
        s.battery = device.battery
        recent.append(s)
        pending.append(s)
        latestInternal = s
        extractor.ingest(s, rules: settings.rules)
    }

    private func tick() {
        let now = Date()
        let rules = settings.rules
        let keep = max(rules.motionWindowSeconds, rules.labelContextSeconds, chartSeconds)
        let cutoff = now.addingTimeInterval(-keep)
        let firstKept = recent.firstIndex { $0.t >= cutoff } ?? recent.count
        if firstKept > 0 { recent.removeFirst(firstKept) }

        latest = latestInternal
        let chartCutoff = now.addingTimeInterval(-chartSeconds)
        let window = recent.filter { $0.t >= chartCutoff }
        let stride = max(1, window.count / maxChartPoints)
        chartSamples = window.enumerated().compactMap { $0.offset % stride == 0 ? $0.element : nil }

        tickCount += 1
        if tickCount % evaluateEveryTicks == 0 { evaluateAndRecord(now: now) }
    }

    private func evaluateAndRecord(now: Date) {
        guard let session else { return }
        let rules = settings.rules
        let app = settings.app
        location.setActive(app.locationGateEnabled && device.isAppActive)
        let gate = location.gate(settings: app, rules: rules, now: now)
        let f = device.isAppActive
            ? extractor.features(recent: recent, now: now, windowSeconds: rules.motionWindowSeconds)
            : nil
        let a = engine.evaluate(RuleInput(now: now, features: f, samplingHz: sessionHz,
                                          targetBedtimeMinutes: app.targetBedtimeMinutes,
                                          locationGate: gate.status, locationReason: gate.reason,
                                          appActive: device.isAppActive),
                                rules: rules)
        features = f
        assessment = a
        history.append(HistoryPoint(t: now, state: a.state, total: a.total, posture: a.posture,
                                    motion: a.motion, bedtime: a.bedtime, accVar: f?.accVar, gyroVar: f?.gyroVar))
        if history.count > maxHistory { history.removeFirst(history.count - maxHistory) }

        repository.appendScore(a, features: f, battery: device.battery, ruleVersion: rules.version, to: session)
        if Double(pending.count) >= sessionHz * flushSeconds { flush() }
    }

    private func flush() {
        guard let session, !pending.isEmpty else { return }
        repository.appendSamples(pending, to: session)
        pending.removeAll(keepingCapacity: true)
        repository.save()
    }
}
