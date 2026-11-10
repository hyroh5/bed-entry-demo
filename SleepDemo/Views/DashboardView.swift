import SwiftUI

struct DashboardView: View {
    @Environment(MeasurementController.self) private var controller

    var body: some View {
        NavigationStack {
            List {
                Section("측정") {
                    if controller.isMeasuring {
                        Button(role: .destructive) { controller.stop() } label: {
                            Label("측정 종료", systemImage: "stop.circle.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        if let s = controller.session {
                            LabeledContent("시작", value: s.startedAt.formatted(date: .omitted, time: .standard))
                        }
                        LabeledContent("원시 샘플", value: "\(controller.sampleCount)")
                        LabeledContent("위치 기록", value: "\(controller.locationCount)")
                        if controller.isPaused {
                            Text("앱 비활성 — 측정 중지됨").foregroundStyle(.orange)
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
                    UserStatePicker().controlSize(.large)
                    if controller.isMeasuring, controller.userInBed == nil {
                        Text("현재 상태를 선택하세요. 선택 전 구간은 '정답 없음'으로 저장됩니다.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    if let message = controller.message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("지금 침대에 들어와 있나요?")
                } footer: {
                    Text("상태가 바뀌는 순간 바로 바꿔 주세요. 웹 탭 상단에서도 바꿀 수 있습니다.")
                }

                Section {
                    LabeledContent("충전 상태", value: controller.device.battery.label)
                    if let loc = controller.location.lastLocation {
                        LabeledContent("위치 정확도", value: "±\(Int(loc.horizontalAccuracy))m")
                        LabeledContent("집까지 거리", value: controller.distanceToHome(loc).map { "\(Int($0))m" } ?? "집 미설정")
                    } else {
                        LabeledContent("위치", value: controller.location.isAuthorized ? "수신 대기" : "권한 없음")
                    }
                } header: {
                    Text("기록 중인 상태")
                } footer: {
                    Text("앱이 화면에 떠 있을 때만 센서·위치를 기록합니다. 다른 앱으로 넘어가거나 화면을 잠그면 기록이 멈춥니다.")
                }
            }
            .navigationTitle("데이터 수집")
        }
    }
}
