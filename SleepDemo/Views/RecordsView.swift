import SwiftData
import SwiftUI

struct RecordsView: View {
    @Environment(\.modelContext) private var context
    @Environment(MeasurementController.self) private var controller
    @Query(sort: \MeasurementSession.startedAt, order: .reverse) private var sessions: [MeasurementSession]
    @State private var share: ShareItems?
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    Text("저장된 측정 세션이 없습니다.").foregroundStyle(.secondary)
                }
                ForEach(sessions) { session in
                    NavigationLink {
                        SessionDetailView(session: session)
                    } label: {
                        SessionRow(session: session, isActive: session.id == controller.session?.id)
                    }
                    .deleteDisabled(session.id == controller.session?.id)
                }
                .onDelete { offsets in
                    let repo = SessionRepository(context: context)
                    for i in offsets { repo.delete(sessions[i]) }
                }
            }
            .navigationTitle("데이터 기록")
            .toolbar {
                Menu {
                    Button("전체 JSON 내보내기") { export { [try ExportService.exportJSON(sessions)] } }
                    Button("전체 CSV 내보내기") { export { try ExportService.exportCSV(sessions) } }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(sessions.isEmpty)
            }
            .sheet(item: $share) { ActivityView(items: $0.urls) }
            .alert("내보내기 실패", isPresented: .constant(exportError != nil)) {
                Button("확인") { exportError = nil }
            } message: { Text(exportError ?? "") }
        }
    }

    private func export(_ make: () throws -> [URL]) {
        do { share = ShareItems(urls: try make()) } catch { exportError = error.localizedDescription }
    }
}

private struct SessionRow: View {
    let session: MeasurementSession
    let isActive: Bool

    var body: some View {
        let labels = session.labels
        let misses = labels.filter { $0.isMisclassified == true }.count
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                if isActive { Badge(text: "측정 중", color: .green) }
            }
            HStack(spacing: 12) {
                Text(durationText)
                Text("응답 \(labels.count)")
                Text("오분류 \(misses)").foregroundStyle(misses > 0 ? .red : .secondary)
                Text("룰 \(session.ruleVersion)")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var durationText: String {
        let end = session.endedAt ?? Date()
        let minutes = Int(end.timeIntervalSince(session.startedAt) / 60)
        return "\(minutes)분"
    }
}

struct SessionDetailView: View {
    let session: MeasurementSession
    @State private var share: ShareItems?
    @State private var exportError: String?

    var body: some View {
        let scores = session.sortedScores
        let labels = session.sortedLabels
        let judged = labels.compactMap(\.isMisclassified)
        let misses = judged.filter { $0 }.count

        List {
            Section("세션 정보") {
                LabeledContent("시작", value: session.startedAt.formatted(date: .abbreviated, time: .standard))
                LabeledContent("종료", value: session.endedAt?.formatted(date: .abbreviated, time: .standard) ?? "측정 중")
                LabeledContent("목표 취침 시간", value: ExportService.hhmm(session.targetBedtimeMinutes))
                LabeledContent("위치 제한", value: session.locationGateEnabled ? "사용 (반경 \(Int(session.homeRadius))m)" : "해제")
                LabeledContent("시작 시 위치 게이트", value: session.initialLocationGate)
                LabeledContent("샘플링", value: "\(fmt(session.samplingHz)) Hz")
                LabeledContent("룰 버전", value: session.ruleVersion)
                LabeledContent("원시 샘플 수", value: "\(session.sampleCount)")
                LabeledContent("판정 기록 수", value: "\(scores.count)")
            }

            Section("점수 변화") {
                let points = SeriesBuilder.downsample(scores, max: 300)
                SeriesChart(points: SeriesBuilder.series(points.map {
                    ($0.timestamp, [("총점", $0.total), ("자세", $0.posture), ("움직임", $0.motion), ("취침시간", $0.bedtime)])
                }), threshold: session.ruleConfig?.threshold, yDomain: 0...100, height: 200)
            }

            Section {
                if labels.isEmpty {
                    Text("응답 없음").foregroundStyle(.secondary)
                }
                ForEach(labels) { label in
                    LabelRow(label: label)
                }
            } header: {
                Text("사용자 응답 \(labels.count)건")
            } footer: {
                if !judged.isEmpty {
                    Text("판정 가능 \(judged.count)건 중 오분류 \(misses)건 (정확도 \(fmt(Double(judged.count - misses) / Double(judged.count) * 100))%). BLOCKED·UNKNOWN 예측은 제외.")
                }
            }

            Section("내보내기") {
                Button("JSON 내보내기") { export { [try ExportService.exportJSON([session])] } }
                Button("CSV 내보내기") { export { try ExportService.exportCSV([session]) } }
            }
        }
        .navigationTitle("세션 상세")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $share) { ActivityView(items: $0.urls) }
        .alert("내보내기 실패", isPresented: .constant(exportError != nil)) {
            Button("확인") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    private func export(_ make: () throws -> [URL]) {
        do { share = ShareItems(urls: try make()) } catch { exportError = error.localizedDescription }
    }
}

private struct LabelRow: View {
    let label: UserLabel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label.timestamp.formatted(date: .omitted, time: .standard)).monospacedDigit()
                Spacer()
                switch label.isMisclassified {
                case .some(true): Badge(text: "오분류", color: .red)
                case .some(false): Badge(text: "일치", color: .green)
                case .none: Badge(text: "판정 불가", color: .gray)
                }
            }
            HStack(spacing: 10) {
                Text("응답: \(label.inBed ? "예" : "아니요")").bold()
                Text("예측: \(label.predictedState)")
                Text("점수 \(fmt(label.total))")
            }
            .font(.caption)
            Text("자세 \(fmt(label.posture)) · 움직임 \(fmt(label.motion)) · 취침 \(fmt(label.bedtime)) · 위치 \(label.locationGate)")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
