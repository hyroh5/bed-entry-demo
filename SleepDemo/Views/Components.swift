import Charts
import SwiftUI
import UIKit

func fmt(_ v: Double?, _ digits: Int = 0) -> String {
    guard let v else { return "—" }
    return String(format: "%.\(digits)f", v)
}

extension BedState {
    var color: Color {
        switch self {
        case .blocked: .gray
        case .unknown: .orange
        case .notInBed: .blue
        case .possiblyInBed: .indigo
        }
    }
}

extension GateStatus {
    var color: Color {
        switch self {
        case .pass, .disabled: .green
        case .blocked: .red
        case .unknown: .orange
        }
    }
}

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// 숫자 입력 행. 소수 입력 후 키보드 '완료' 또는 다른 칸으로 이동하면 반영된다.
struct NumberField: View {
    let title: String
    @Binding var value: Double
    var unit: String = ""

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: $value, format: .number.precision(.fractionLength(0...6)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
            if !unit.isEmpty {
                Text(unit).foregroundStyle(.secondary).font(.footnote)
            }
        }
    }
}

struct KeyboardDoneToolbar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
    }
}

extension View {
    func keyboardDoneToolbar() -> some View { modifier(KeyboardDoneToolbar()) }
}

/// 공유 시트 (CSV/JSON 내보내기).
struct ShareItems: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// 시간축 다중 시리즈 꺾은선 차트.
struct SeriesPoint: Identifiable {
    let id: Int
    let t: Date
    let series: String
    let value: Double
}

struct SeriesChart: View {
    let points: [SeriesPoint]
    var threshold: Double?
    var yDomain: ClosedRange<Double>?
    var height: CGFloat = 170

    var body: some View {
        if points.isEmpty {
            Text("데이터 없음")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: height)
        } else if let yDomain {
            chart.chartYScale(domain: yDomain)
        } else {
            chart
        }
    }

    private var chart: some View {
        Chart {
            ForEach(points) { p in
                LineMark(x: .value("시간", p.t), y: .value("값", p.value), series: .value("항목", p.series))
                    .foregroundStyle(by: .value("항목", p.series))
                    .interpolationMethod(.linear)
            }
            if let threshold {
                RuleMark(y: .value("임계값", threshold))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.red)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute().second())
            }
        }
        .frame(height: height)
    }
}

enum SeriesBuilder {
    static func axes(_ samples: [MotionSample], _ value: (MotionSample) -> (Double, Double, Double)) -> [SeriesPoint] {
        var out: [SeriesPoint] = []
        out.reserveCapacity(samples.count * 3)
        for (i, s) in samples.enumerated() {
            let v = value(s)
            out.append(SeriesPoint(id: i * 3, t: s.t, series: "x", value: v.0))
            out.append(SeriesPoint(id: i * 3 + 1, t: s.t, series: "y", value: v.1))
            out.append(SeriesPoint(id: i * 3 + 2, t: s.t, series: "z", value: v.2))
        }
        return out
    }

    /// (시각, [(시리즈명, 값?)]) 목록을 차트 포인트로 변환. nil 값은 건너뛴다.
    static func series(_ rows: [(Date, [(String, Double?)])]) -> [SeriesPoint] {
        var out: [SeriesPoint] = []
        var id = 0
        for (t, values) in rows {
            for (name, v) in values {
                if let v { out.append(SeriesPoint(id: id, t: t, series: name, value: v)) }
                id += 1
            }
        }
        return out
    }

    static func downsample<T>(_ xs: [T], max: Int) -> [T] {
        guard xs.count > max, max > 0 else { return xs }
        let stride = (xs.count + max - 1) / max
        return xs.enumerated().compactMap { $0.offset % stride == 0 ? $0.element : nil }
    }
}
