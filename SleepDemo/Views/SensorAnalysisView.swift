import SwiftUI

struct SensorAnalysisView: View {
    @Environment(MeasurementController.self) private var controller

    var body: some View {
        NavigationStack {
            List {
                if !controller.motionAvailable {
                    Section {
                        Text("이 기기에서는 Device Motion을 사용할 수 없습니다. 센서 값과 그래프는 실제 iPhone에서 확인하세요.")
                            .foregroundStyle(.orange)
                    }
                } else if !controller.isMeasuring {
                    Section { Text("측정을 시작하면 실시간 값이 표시됩니다.").foregroundStyle(.secondary) }
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
                }

                Section("선형 가속도 userAcceleration (g, 최근 30초)") {
                    SeriesChart(points: SeriesBuilder.axes(controller.chartSamples) { ($0.ax, $0.ay, $0.az) })
                }

                Section("각속도 rotationRate (rad/s, 최근 30초)") {
                    SeriesChart(points: SeriesBuilder.axes(controller.chartSamples) { ($0.rx, $0.ry, $0.rz) })
                }
            }
            .navigationTitle("센서")
        }
    }

    private func valueCell(_ title: String, _ value: Double?, _ unit: String, _ digits: Int = 1) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(fmt(value, digits))\(unit)").font(.body.monospacedDigit())
        }
    }
}
