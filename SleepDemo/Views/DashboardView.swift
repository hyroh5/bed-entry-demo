import SwiftUI

struct DashboardView: View {
    @Environment(MeasurementController.self) private var controller
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        NavigationStack {
            List {
                Section { scoreHeader }

                Section("하드 게이트") {
                    let gate = controller.location.gate(settings: settings.app, rules: settings.rules)
                    LabeledContent("위치") { Badge(text: gate.status.label, color: gate.status.color) }
                    Text(gate.reason).font(.footnote).foregroundStyle(.secondary)
                    LabeledContent("앱 활성 상태") {
                        Badge(text: controller.device.isAppActive ? "활성" : "비활성",
                              color: controller.device.isAppActive ? .green : .gray)
                    }
                }

                Section("항목별 점수") {
                    scoreRow("기기 자세", controller.assessment?.posture, weight: settings.rules.weightPosture)
                    scoreRow("움직임 안정성", controller.assessment?.motion, weight: settings.rules.weightMotion)
                    scoreRow("목표 취침 시간", controller.assessment?.bedtime, weight: settings.rules.weightBedtime)
                }

                Section("기기 상태") {
                    LabeledContent("충전 상태", value: controller.device.battery.label)
                    Text("충전 상태는 기록만 하고 점수에는 반영하지 않습니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("측정") {
                    if controller.isMeasuring {
                        Button(role: .destructive) { controller.stop() } label: {
                            Label("측정 종료", systemImage: "stop.circle.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        if let s = controller.session {
                            LabeledContent("시작", value: s.startedAt.formatted(date: .omitted, time: .standard))
                            LabeledContent("룰 버전", value: s.ruleVersion)
                        }
                        if controller.isPaused {
                            Text("앱 비활성 — 측정 일시 중지").foregroundStyle(.orange)
                        }
                    } else {
                        Button { controller.start() } label: {
                            Label("측정 시작", systemImage: "play.circle.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if !controller.motionAvailable {
                        Text("Device Motion 사용 불가 — 실제 iPhone 테스트 대상")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }

                Section {
                    HStack(spacing: 12) {
                        Button { controller.submitLabel(inBed: true) } label: {
                            Text("예").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        Button { controller.submitLabel(inBed: false) } label: {
                            Text("아니요").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .controlSize(.large)
                    .disabled(!controller.isMeasuring)
                    if let message = controller.message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("현재 침대에 들어와 있나요?")
                } footer: {
                    Text("점수가 높을 때뿐 아니라 낮을 때도 응답해 주세요. 응답은 기록만 되고 판정에 즉시 반영되지 않습니다.")
                }
            }
            .navigationTitle("잠자리 진입 감지")
        }
    }

    private var scoreHeader: some View {
        let a = controller.assessment
        let state = a?.state ?? .unknown
        let total = a?.total
        return VStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: (total ?? 0) / 100)
                    .stroke(state.color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: total)
                VStack(spacing: 2) {
                    Text(fmt(total))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("/ 100 · 임계값 \(fmt(settings.rules.threshold))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 170, height: 170)

            Badge(text: controller.isMeasuring ? state.rawValue : "측정 대기", color: controller.isMeasuring ? state.color : .gray)
            if let a {
                Text(a.reason).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if a.rawState == .possiblyInBed, a.state != .possiblyInBed {
                    ProgressView(value: min(a.secondsAboveThreshold, settings.rules.holdSeconds),
                                 total: max(settings.rules.holdSeconds, 1)) {
                        Text("판정 유지 시간").font(.caption)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func scoreRow(_ title: String, _ value: Double?, weight: Double) -> some View {
        let sum = max(settings.rules.weightPosture + settings.rules.weightMotion + settings.rules.weightBedtime, 0.0001)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Text("가중치 \(fmt(weight / sum * 100))%").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(fmt(value)).monospacedDigit().bold()
            }
            ProgressView(value: (value ?? 0) / 100)
        }
    }
}
