import CoreLocation
import Foundation
import Observation
import SwiftData
import UIKit

/// 측정 세션을 진행한다 (수집 전용, 판정 없음).
/// 센서는 설정 주기(기본 20Hz)로 받고, UI는 4Hz, 위치 기록은 1Hz로 확인한다.
/// 앱이 활성 상태가 아니면 아무것도 측정·기록하지 않는다.
@Observable @MainActor
final class MeasurementController {
    let settings: SettingsStore
    let location = LocationService()
    let device = DeviceStateService()

    private(set) var session: MeasurementSession?
    private(set) var isPaused = false
    private(set) var latest: MotionSample?
    private(set) var chartSamples: [MotionSample] = []
    private(set) var message: String?
    /// 상태 슬라이드로 지정한 현재 실제 상태 (nil = 미입력)
    private(set) var userInBed: Bool?
    private(set) var sampleCount = 0
    private(set) var locationCount = 0

    var isMeasuring: Bool { session != nil }
    var motionAvailable: Bool { motionService.isAvailable }

    @ObservationIgnored private let motionService = MotionService()
    @ObservationIgnored private let repository: SessionRepository
    @ObservationIgnored private var recent: [MotionSample] = []
    @ObservationIgnored private var pending: [MotionSample] = []
    @ObservationIgnored private var latestInternal: MotionSample?
    @ObservationIgnored private var lastLocationTime: Date?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var tickCount = 0
    @ObservationIgnored private var sessionHz = 20.0

    private let uiTickInterval = 0.25
    private let locationEveryTicks = 4
    private let chartSeconds = 30.0
    private let maxChartPoints = 150
    private let flushSeconds = 5.0

    init(settings: SettingsStore, context: ModelContext) {
        self.settings = settings
        self.repository = SessionRepository(context: context)
    }

    // MARK: 세션 제어

    func start() {
        guard session == nil else { return }
        sessionHz = settings.app.samplingHz
        session = repository.createSession(samplingHz: sessionHz)

        recent.removeAll(); pending.removeAll(); chartSamples.removeAll()
        latestInternal = nil; latest = nil; lastLocationTime = nil; tickCount = 0
        userInBed = nil; sampleCount = 0; locationCount = 0
        UIApplication.shared.isIdleTimerDisabled = true // 측정 중 자동 잠금으로 일시 중지되지 않게
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
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// scenePhase 변화. 비활성/백그라운드에서는 측정을 멈추고, 돌아오면 다시 시작한다.
    func setAppActive(_ active: Bool) {
        guard device.isAppActive != active else { return }
        device.isAppActive = active
        guard session != nil else { return }
        if active {
            resumeSensors()
        } else {
            pauseSensors()
            flush()
        }
    }

    /// 상태 슬라이드 변경. 같은 상태로의 변경은 무시하고, 바뀔 때만 전환 기록을 남긴다.
    func setUserState(inBed: Bool) {
        guard let session, userInBed != inBed else { return }
        userInBed = inBed
        let now = Date()
        repository.addLabel(inBed: inBed, at: now, to: session)
        message = "\(now.formatted(date: .omitted, time: .standard)) \(inBed ? "침대 안" : "침대 밖")으로 전환"
    }

    func distanceToHome(_ loc: CLLocation) -> Double? {
        guard let lat = settings.app.homeLatitude, let lon = settings.app.homeLongitude else { return nil }
        return loc.distance(from: CLLocation(latitude: lat, longitude: lon))
    }

    // MARK: 내부

    private func resumeSensors() {
        isPaused = false
        recent.removeAll()
        location.setActive(true)
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
        sampleCount += 1
    }

    private func tick() {
        let now = Date()
        let cutoff = now.addingTimeInterval(-chartSeconds)
        let firstKept = recent.firstIndex { $0.t >= cutoff } ?? recent.count
        if firstKept > 0 { recent.removeFirst(firstKept) }

        latest = latestInternal
        let stride = max(1, recent.count / maxChartPoints)
        chartSamples = recent.enumerated().compactMap { $0.offset % stride == 0 ? $0.element : nil }

        tickCount += 1
        if tickCount % locationEveryTicks == 0 { recordLocationIfNew() }
        if Double(pending.count) >= sessionHz * flushSeconds { flush() }
    }

    /// 새로 받은 위치만 기록한다. 세션 시작 전에 받아 둔(캐시된) 위치는 건너뛴다.
    private func recordLocationIfNew() {
        guard let session, let loc = location.lastLocation, loc.timestamp >= session.startedAt else { return }
        if let last = lastLocationTime, loc.timestamp <= last { return }
        lastLocationTime = loc.timestamp
        repository.appendLocation(loc, distanceToHome: distanceToHome(loc), to: session)
        locationCount += 1
    }

    private func flush() {
        guard let session, !pending.isEmpty else { return }
        repository.appendSamples(pending, to: session)
        pending.removeAll(keepingCapacity: true)
        repository.save()
    }
}
