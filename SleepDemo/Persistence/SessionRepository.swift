import CoreLocation
import Foundation
import SwiftData

@MainActor
struct SessionRepository {
    let context: ModelContext

    func createSession(samplingHz: Double) -> MeasurementSession {
        let session = MeasurementSession(startedAt: Date(), samplingHz: samplingHz)
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

    func appendLocation(_ loc: CLLocation, distanceToHome: Double?, to session: MeasurementSession) {
        let record = LocationRecord(timestamp: loc.timestamp, latitude: loc.coordinate.latitude,
                                    longitude: loc.coordinate.longitude, horizontalAccuracy: loc.horizontalAccuracy,
                                    distanceToHome: distanceToHome)
        context.insert(record)
        record.session = session
    }

    func addLabel(inBed: Bool, at time: Date, to session: MeasurementSession) {
        let label = UserLabel(inBed: inBed, timestamp: time)
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
