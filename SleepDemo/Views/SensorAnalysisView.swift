import SwiftUI

struct SensorAnalysisView: View {
    @Environment(MeasurementController.self) private var controller
    @Environment(SettingsStore.self) private var settings

    private let liveHistoryPoints = 300

    var body: some View {
        NavigationStack {
            List {
                if !controller.motionAvailable {
                    Section {
                        Text("이 기기에서는 Device Motion을 사용할 수 없습니다. 센서 값과 그래프는 실제 iPhone에서 확인하세요.")
                            .foregroundStyle(.orange)
                    }
                } else if !controller.isMeasuring {
                    Section { Text("대시보드에서 측정을 시작하면 실시간 값이 표시됩니다.").foregroundStyle(.secondary) }
                }

                Section("기기 자세 (실시간)") {
                    let s = controller.latest
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow {
                            valueCell("Pitch", s.map { $0.pitch * 180 / .pi }, "°")
                            valueCell("Roll", s.map { $0.roll * 180 / .pi }, "°")
                            valueCell("Yaw", s.map { $0.yaw * 180 / .pi }, "°")
                        }
                        GridRow {
                            valueCell("중력 x", s?.gx, "g", 2)
                            valueCell("중력 y", s?.gy, "g", 2)
                            valueCell("중력 z", s?.gz, "g", 2)
                        }
                    }
                    let f = controller.features
                    LabeledContent("화면 기울기 (윈도우 평균)", value: "\(fmt(f?.screenTiltDeg))°")
                    LabeledContent("측면 기울기", value: "\(fmt(f?.lateralTiltDeg))° · 수평 성분 \(fmt(f?.horizontalG, 2))")
                    LabeledContent("안정 유지 시간", value: "\(fmt(f?.stableDuration))초")
                    Text("기기 자세 값이며 사용자의 신체 자세를 뜻하지 않습니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("선형 가속도 userAcceleration (g, 최근 30초)") {
                    SeriesChart(points: SeriesBuilder.axes(controller.chartSamples) { ($0.ax, $0.ay, $0.az) })
                }

                Section("각속도 rotationRate (rad/s, 최근 30초)") {
                    SeriesChart(points: SeriesBuilder.axes(controller.chartSamples) { ($0.rx, $0.ry, $0.rz) })
                }

                let history = Array(controller.history.suffix(liveHistoryPoints))

                Section("움직임 분산 (\(fmt(settings.rules.motionWindowSeconds))초 윈도우)") {
                    Text("가속도 크기 분산").font(.caption).foregroundStyle(.secondary)
                    SeriesChart(points: SeriesBuilder.series(history.map { ($0.t, [("가속도 분산", $0.accVar)]) }),
                                height: 120)
                    Text("각속도 크기 분산").font(.caption).foregroundStyle(.secondary)
                    SeriesChart(points: SeriesBuilder.series(history.map { ($0.t, [("각속도 분산", $0.gyroVar)]) }),
                                height: 120)
                    let f = controller.features
                    LabeledContent("가속도 평균 / 분산", value: "\(fmt(f?.accMean, 4)) / \(fmt(f?.accVar, 5))")
                    LabeledContent("각속도 평균 / 분산", value: "\(fmt(f?.gyroMean, 3)) / \(fmt(f?.gyroVar, 4))")
                }

                Section("점수 변화") {
                    SeriesChart(points: SeriesBuilder.series(history.map {
                        ($0.t, [("총점", $0.total), ("자세", $0.posture), ("움직임", $0.motion), ("취침시간", $0.bedtime)])
                    }), threshold: settings.rules.threshold, yDomain: 0...100, height: 200)
                }
            }
            .navigationTitle("센서 분석")
        }
    }

    private func valueCell(_ title: String, _ value: Double?, _ unit: String, _ digits: Int = 1) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(fmt(value, digits))\(unit)").font(.body.monospacedDigit())
        }
    }
}
