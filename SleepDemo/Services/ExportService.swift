import Foundation

/// 세션 데이터를 JSON(1개 파일) 또는 CSV(3개 파일)로 임시 폴더에 쓴다.
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
        let samplingHz: Double
        let samples: [MotionSample]
        let transitions: [TransitionDTO]
        let locations: [LocationDTO]
    }

    private struct TransitionDTO: Encodable {
        let timestamp: Date
        let inBed: Bool
    }

    private struct LocationDTO: Encodable {
        let timestamp: Date
        let latitude, longitude, horizontalAccuracy: Double
        let distanceToHome: Double?
    }

    static func exportJSON(_ sessions: [MeasurementSession]) throws -> URL {
        let file = ExportFile(exportedAt: Date(), sessions: sessions.map { s in
            SessionDTO(
                id: s.id, startedAt: s.startedAt, endedAt: s.endedAt, samplingHz: s.samplingHz,
                samples: s.allSamples,
                transitions: s.sortedLabels.map { TransitionDTO(timestamp: $0.timestamp, inBed: $0.inBed) },
                locations: s.sortedLocations.map {
                    LocationDTO(timestamp: $0.timestamp, latitude: $0.latitude, longitude: $0.longitude,
                                horizontalAccuracy: $0.horizontalAccuracy, distanceToHome: $0.distanceToHome)
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
        var samples = "session_id,timestamp,epoch,in_bed,pitch,roll,yaw,gx,gy,gz,ax,ay,az,rx,ry,rz,battery\n"
        var transitions = "session_id,timestamp,epoch,in_bed\n"
        var locations = "session_id,timestamp,epoch,latitude,longitude,accuracy_m,distance_to_home_m\n"

        for s in sessions {
            let sid = s.id.uuidString
            let labels = s.sortedLabels
            let all = s.allSamples
            let inBed = inBedValues(at: all.map(\.t), transitions: labels.map { ($0.timestamp, $0.inBed) })
            for (m, b) in zip(all, inBed) {
                samples += "\(sid),\(iso.format(m.t)),\(num(m.t.timeIntervalSince1970)),\(flag(b)),\(sampleRow(m))\n"
            }
            for l in labels {
                transitions += "\(sid),\(iso.format(l.timestamp)),\(num(l.timestamp.timeIntervalSince1970)),\(flag(l.inBed))\n"
            }
            for l in s.sortedLocations {
                locations += [sid, iso.format(l.timestamp), num(l.timestamp.timeIntervalSince1970), num(l.latitude),
                              num(l.longitude), num(l.horizontalAccuracy), num(l.distanceToHome)]
                    .joined(separator: ",") + "\n"
            }
        }

        let dir = try exportDirectory()
        let prefix = "sleepdemo_\(stamp())"
        var urls: [URL] = []
        for (name, body) in [("samples", samples), ("transitions", transitions), ("locations", locations)] {
            let url = dir.appendingPathComponent("\(prefix)_\(name).csv")
            try body.write(to: url, atomically: true, encoding: .utf8)
            urls.append(url)
        }
        return urls
    }

    /// 각 시각에 적용되는 상태 슬라이드 값. 두 입력 모두 시간순이어야 하며, 첫 전환 이전은 nil.
    static func inBedValues(at times: [Date], transitions: [(Date, Bool)]) -> [Bool?] {
        var i = 0
        var current: Bool?
        return times.map { t in
            while i < transitions.count, transitions[i].0 <= t {
                current = transitions[i].1
                i += 1
            }
            return current
        }
    }

    // MARK: 보조

    private static func sampleRow(_ m: MotionSample) -> String {
        [num(m.pitch), num(m.roll), num(m.yaw), num(m.gx), num(m.gy), num(m.gz), num(m.ax), num(m.ay), num(m.az),
         num(m.rx), num(m.ry), num(m.rz), m.battery.rawValue].joined(separator: ",")
    }

    private static func num(_ v: Double?) -> String { v.map { String($0) } ?? "" }
    private static func flag(_ v: Bool?) -> String { v.map { $0 ? "1" : "0" } ?? "" }

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
