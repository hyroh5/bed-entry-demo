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
                Section {
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
                    Text("측정 중 위치 좌표·정확도를 기록하고, 집이 설정돼 있으면 집까지 거리도 함께 남깁니다. 집 좌표 자체는 세션에 저장하지 않습니다.")
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
                    Text("변경 내용은 다음 측정 세션부터 적용됩니다.")
                }
            }
            .navigationTitle("설정")
            .keyboardDoneToolbar()
        }
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
