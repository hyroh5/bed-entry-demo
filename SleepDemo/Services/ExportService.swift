import Foundation

/// 세션 데이터를 JSON(1개 파일) 또는 CSV(4개 파일)로 임시 폴더에 쓴다.
@MainActor
enum ExportService {
    private static let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    // MARK: JSON

    private struct ExportFile: Encodable {
        let exportedAt: Date
        let sessions: [SessionDTO]
    }

    private struct SessionDTO: Encodable {
        let id: UUID
        let startedAt: Date
        let endedAt: Date?
        let targetBedtime: String
        let locationGateEnabled: Bool
        let homeRadius: Double
        let initialLocationGate: String
        let samplingHz: Double
        let ruleVersion: String
        let ruleConfig: RuleConfig?
        let samples: [MotionSample]
        let scores: [ScoreDTO]
        let labels: [LabelDTO]
    }

    private struct ScoreDTO: Encodable {
        let timestamp: Date
        let state: String
        let rawState: String
        let total, posture, motion, bedtime: Double?
        let locationGate: String
        let appActive: Bool
        let battery: String
        let ruleVersion: String
        let features: WindowFeatures?
    }

    private struct LabelDTO: Encodable {
        let id: UUID
        let timestamp: Date
        let inBed: Bool
        let predictedState: String
        let predictedRawState: String
        let misclassified: Bool?
        let total, posture, motion, bedtime: Double?
        let locationGate: String
        let ruleVersion: String
        let features: WindowFeatures?
        let contextSeconds: Double
        let contextSamples: [MotionSample]
    }

    static func exportJSON(_ sessions: [MeasurementSession]) throws -> URL {
        let file = ExportFile(exportedAt: Date(), sessions: sessions.map { s in
            SessionDTO(
                id: s.id, startedAt: s.startedAt, endedAt: s.endedAt,
                targetBedtime: hhmm(s.targetBedtimeMinutes),
                locationGateEnabled: s.locationGateEnabled, homeRadius: s.homeRadius,
                initialLocationGate: s.initialLocationGate, samplingHz: s.samplingHz,
                ruleVersion: s.ruleVersion, ruleConfig: s.ruleConfig,
                samples: s.allSamples,
                scores: s.sortedScores.map {
                    ScoreDTO(timestamp: $0.timestamp, state: $0.state, rawState: $0.rawState,
                             total: $0.total, posture: $0.posture, motion: $0.motion, bedtime: $0.bedtime,
                             locationGate: $0.locationGate, appActive: $0.appActive, battery: $0.battery,
                             ruleVersion: $0.ruleVersion, features: $0.features)
                },
                labels: s.sortedLabels.map {
                    LabelDTO(id: $0.id, timestamp: $0.timestamp, inBed: $0.inBed,
                             predictedState: $0.predictedState, predictedRawState: $0.predictedRawState,
                             misclassified: $0.isMisclassified,
                             total: $0.total, posture: $0.posture, motion: $0.motion, bedtime: $0.bedtime,
                             locationGate: $0.locationGate, ruleVersion: $0.ruleVersion, features: $0.features,
                             contextSeconds: $0.contextSeconds, contextSamples: $0.decodedContext)
                }
            )
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let style = iso
        encoder.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(style.format(date))
        }
        let url = try exportDirectory().appendingPathComponent("sleepdemo_\(stamp()).json")
        try encoder.encode(file).write(to: url)
        return url
    }

    // MARK: CSV

    static func exportCSV(_ sessions: [MeasurementSession]) throws -> [URL] {
        let featureHeader = "sample_count,acc_mean,acc_var,gyro_mean,gyro_var,gravity_x,gravity_y,gravity_z,screen_tilt_deg,lateral_tilt_deg,horizontal_g,stable_duration"

        var samples = "session_id,timestamp,epoch,pitch,roll,yaw,gx,gy,gz,ax,ay,az,rx,ry,rz,battery\n"
        var scores = "session_id,timestamp,epoch,state,raw_state,total,posture,motion,bedtime,location_gate,app_active,battery,rule_version,\(featureHeader)\n"
        var labels = "session_id,label_id,timestamp,epoch,in_bed,predicted_state,predicted_raw_state,misclassified,total,posture,motion,bedtime,location_gate,rule_version,context_seconds,\(featureHeader)\n"
        var context = "label_id,timestamp,epoch,pitch,roll,yaw,gx,gy,gz,ax,ay,az,rx,ry,rz,battery\n"

        for s in sessions {
            let sid = s.id.uuidString
            for m in s.allSamples {
                samples += "\(sid),\(sampleRow(m))\n"
            }
            for p in s.sortedScores {
                scores += [sid, iso.format(p.timestamp), num(p.timestamp.timeIntervalSince1970), p.state, p.rawState,
                           num(p.total), num(p.posture), num(p.motion), num(p.bedtime), p.locationGate,
                           p.appActive ? "1" : "0", p.battery, p.ruleVersion, featureRow(p.features)]
                    .joined(separator: ",") + "\n"
            }
            for l in s.sortedLabels {
                let lid = l.id.uuidString
                labels += [sid, lid, iso.format(l.timestamp), num(l.timestamp.timeIntervalSince1970), l.inBed ? "1" : "0",
                           l.predictedState, l.predictedRawState, l.isMisclassified.map { $0 ? "1" : "0" } ?? "",
                           num(l.total), num(l.posture), num(l.motion), num(l.bedtime), l.locationGate, l.ruleVersion,
                           num(l.contextSeconds), featureRow(l.features)]
                    .joined(separator: ",") + "\n"
                for m in l.decodedContext {
                    context += "\(lid),\(sampleRow(m))\n"
                }
            }
        }

        let dir = try exportDirectory()
        let prefix = "sleepdemo_\(stamp())"
        var urls: [URL] = []
        for (name, body) in [("samples", samples), ("scores", scores), ("labels", labels), ("label_context", context)] {
            let url = dir.appendingPathComponent("\(prefix)_\(name).csv")
            try body.write(to: url, atomically: true, encoding: .utf8)
            urls.append(url)
        }
        return urls
    }

    // MARK: 보조

    private static func sampleRow(_ m: MotionSample) -> String {
        [iso.format(m.t), num(m.t.timeIntervalSince1970), num(m.pitch), num(m.roll), num(m.yaw),
         num(m.gx), num(m.gy), num(m.gz), num(m.ax), num(m.ay), num(m.az),
         num(m.rx), num(m.ry), num(m.rz), m.battery.rawValue].joined(separator: ",")
    }

    private static func featureRow(_ f: WindowFeatures?) -> String {
        guard let f else { return Array(repeating: "", count: 12).joined(separator: ",") }
        return [String(f.sampleCount), num(f.accMean), num(f.accVar), num(f.gyroMean), num(f.gyroVar),
                num(f.gravityX), num(f.gravityY), num(f.gravityZ), num(f.screenTiltDeg), num(f.lateralTiltDeg),
                num(f.horizontalG), num(f.stableDuration)].joined(separator: ",")
    }

    private static func num(_ v: Double?) -> String { v.map { String($0) } ?? "" }

    static func hhmm(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }

    private static func exportDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
