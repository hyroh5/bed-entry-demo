import Charts
import SwiftUI
import UIKit

func fmt(_ v: Double?, _ digits: Int = 0) -> String {
    guard let v else { return "—" }
    return String(format: "%.\(digits)f", v)
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
    var height: CGFloat = 170

    var body: some View {
        if points.isEmpty {
            Text("데이터 없음")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: height)
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
}

/// 상태 슬라이드 (침대 밖 / 침대 안). 측정 중에만 바꿀 수 있다.
struct UserStatePicker: View {
    @Environment(MeasurementController.self) private var controller

    var body: some View {
        Picker("실제 상태", selection: binding) {
            Text("침대 밖").tag(Bool?.some(false))
            Text("침대 안").tag(Bool?.some(true))
        }
        .pickerStyle(.segmented)
        .disabled(!controller.isMeasuring)
    }

    private var binding: Binding<Bool?> {
        Binding(get: { controller.userInBed },
                set: { if let v = $0 { controller.setUserState(inBed: v) } })
    }
}
