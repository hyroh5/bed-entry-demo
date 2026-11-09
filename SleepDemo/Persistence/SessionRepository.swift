import Foundation
import SwiftData

@MainActor
struct SessionRepository {
    let context: ModelContext

    func createSession(settings: AppSettings, rules: RuleConfig, initialGate: GateStatus) -> MeasurementSession {
        let session = MeasurementSession(
            startedAt: Date(),
            targetBedtimeMinutes: settings.targetBedtimeMinutes,
            locationGateEnabled: settings.locationGateEnabled,
            homeRadius: settings.homeRadius,
            initialLocationGate: initialGate.rawValue,
            samplingHz: settings.samplingHz,
            ruleVersion: rules.version,
            ruleConfigJSON: rules.json
        )
        context.insert(session)
        save()
        return session
    }

    func appendSamples(_ samples: [MotionSample], to session: MeasurementSession) {
        guard !samples.isEmpty else { return }
        let batch = SampleBatch(samples: samples)
        context.insert(batch)
        batch.session = session
    }

    func appendScore(_ a: Assessment, features: WindowFeatures?, battery: BatteryStatus,
                     ruleVersion: String, to session: MeasurementSession) {
        let point = ScorePoint(assessment: a, features: features, battery: battery, ruleVersion: ruleVersion)
        context.insert(point)
        point.session = session
    }

    func addLabel(inBed: Bool, at time: Date, assessment: Assessment?, features: WindowFeatures?,
                  context samples: [MotionSample], contextSeconds: Double, ruleVersion: String,
                  to session: MeasurementSession) {
        let label = UserLabel(inBed: inBed, timestamp: time, assessment: assessment, features: features,
                              context: samples, contextSeconds: contextSeconds, ruleVersion: ruleVersion)
        context.insert(label)
        label.session = session
        save()
    }

    func end(_ session: MeasurementSession) {
        session.endedAt = Date()
        save()
    }

    func delete(_ session: MeasurementSession) {
        context.delete(session)
        save()
    }

    func save() {
        do { try context.save() } catch { print("SwiftData save failed: \(error)") }
    }
}
