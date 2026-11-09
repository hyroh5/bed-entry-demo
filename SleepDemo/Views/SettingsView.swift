import CoreLocation
import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(MeasurementController.self) private var controller

    var body: some View {
        @Bindable var settings = settings
        let location = controller.location

        NavigationStack {
            Form {
                Section("목표 취침 시간") {
                    DatePicker("목표 시각", selection: bedtimeBinding, displayedComponents: .hourAndMinute)
                    Text("점수 적용 범위는 룰 설정에서 변경합니다.").font(.footnote).foregroundStyle(.secondary)
                }

                Section {
                    Toggle("위치 제한 사용", isOn: $settings.app.locationGateEnabled)
                    NumberField(title: "허용 반경", value: $settings.app.homeRadius, unit: "m")
                    HStack {
                        Text("위도")
                        TextField("미설정", value: $settings.app.homeLatitude, format: .number.precision(.fractionLength(0...7)))
                            .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("경도")
                        TextField("미설정", value: $settings.app.homeLongitude, format: .number.precision(.fractionLength(0...7)))
                            .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("집 위치")
                } footer: {
                    Text("위치 제한을 끄면 집 밖(여행·외박)에서도 판정합니다. 집 밖에서는 BLOCKED, 권한·정확도 부족 시 UNKNOWN으로 처리합니다.")
                }

                Section("현재 위치") {
                    LabeledContent("권한", value: authorizationText(location.authorization))
                    if let loc = location.lastLocation {
                        LabeledContent("좌표", value: String(format: "%.5f, %.5f", loc.coordinate.latitude, loc.coordinate.longitude))
                        LabeledContent("정확도", value: "±\(Int(loc.horizontalAccuracy))m")
                        LabeledContent("수신 시각", value: loc.timestamp.formatted(date: .omitted, time: .standard))
                        if let lat = settings.app.homeLatitude, let lon = settings.app.homeLongitude {
                            LabeledContent("집까지 거리", value: "\(Int(loc.distance(from: CLLocation(latitude: lat, longitude: lon))))m")
                        }
                    }
                    if let error = location.lastError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                    Button("현재 위치 요청") { location.requestOnce() }
                    Button("현재 위치를 집으로 설정") {
                        guard let loc = location.lastLocation else { return }
                        settings.app.homeLatitude = loc.coordinate.latitude
                        settings.app.homeLongitude = loc.coordinate.longitude
                    }
                    .disabled(location.lastLocation == nil)
                }

                Section {
                    Stepper("\(Int(settings.app.samplingHz)) Hz", value: $settings.app.samplingHz, in: 5...100, step: 5)
                } header: {
                    Text("센서 측정 주기")
                } footer: {
                    Text("변경 내용은 다음 측정 세션부터 적용됩니다. UI는 4Hz, 판정·저장은 1Hz로 갱신됩니다.")
                }
            }
            .navigationTitle("설정")
            .keyboardDoneToolbar()
        }
    }

    private var bedtimeBinding: Binding<Date> {
        Binding(
            get: {
                let m = settings.app.targetBedtimeMinutes
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                settings.app.targetBedtimeMinutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }

    private func authorizationText(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "요청 전"
        case .restricted: "제한됨"
        case .denied: "거부됨"
        case .authorizedAlways: "항상 허용"
        case .authorizedWhenInUse: "앱 사용 중 허용"
        @unknown default: "알 수 없음"
        }
    }
}
