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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                if isActive { Badge(text: "측정 중", color: .green) }
            }
            HStack(spacing: 12) {
                Text(durationText)
                Text("상태 전환 \(session.labels.count)")
                Text("위치 \(session.locations.count)")
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
        let labels = session.sortedLabels

        List {
            Section("세션 정보") {
                LabeledContent("시작", value: session.startedAt.formatted(date: .abbreviated, time: .standard))
                LabeledContent("종료", value: session.endedAt?.formatted(date: .abbreviated, time: .standard) ?? "측정 중")
                LabeledContent("샘플링", value: "\(fmt(session.samplingHz)) Hz")
                LabeledContent("원시 샘플 수", value: "\(session.sampleCount)")
                LabeledContent("위치 기록 수", value: "\(session.locations.count)")
            }

            Section {
                if labels.isEmpty {
                    Text("상태 전환 없음").foregroundStyle(.secondary)
                }
                ForEach(labels) { label in
                    LabelRow(label: label)
                }
            } header: {
                Text("상태 전환 \(labels.count)건")
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
        HStack {
            Text(label.timestamp.formatted(date: .omitted, time: .standard)).monospacedDigit()
            Spacer()
            Text("→ \(label.inBed ? "침대 안" : "침대 밖")").bold()
        }
    }
}
