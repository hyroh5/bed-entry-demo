import SwiftUI

struct RuleSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var confirmReset = false

    var body: some View {
        @Bindable var settings = settings
        let r = $settings.rules

        NavigationStack {
            Form {
                Section {
                    LabeledContent("현재 룰 버전", value: settings.rules.version)
                } footer: {
                    Text("모든 값은 초기 가설입니다. 측정 중 변경하면 이후 판정부터 적용되며, 판정 기록마다 룰 버전이 저장됩니다.")
                }

                Section {
                    NumberField(title: "기기 자세", value: r.weightPosture)
                    NumberField(title: "움직임 안정성", value: r.weightMotion)
                    NumberField(title: "목표 취침 시간", value: r.weightBedtime)
                } header: {
                    Text("항목별 가중치")
                } footer: {
                    Text("합으로 정규화합니다.")
                }

                Section {
                    BandEditor(bands: r.screenTiltBands, maxDeg: 180)
                } header: {
                    Text("화면 기울기 범위 → 점수")
                } footer: {
                    Text("0° = 화면이 위를 향해 수평, 90° = 수직, 180° = 화면이 아래를 향함. 윈도우 평균 중력 벡터 기준.")
                }

                Section {
                    BandEditor(bands: r.lateralTiltBands, maxDeg: 90)
                    NumberField(title: "적용 최소 수평 성분", value: r.lateralMinHorizontalG, unit: "g")
                } header: {
                    Text("측면 기울기 범위 → 점수")
                } footer: {
                    Text("0° = 세로로 섬, 90° = 옆으로 눕힘. 자세 점수는 화면·측면 점수 중 큰 값입니다.")
                }

                Section("움직임 안정성") {
                    NumberField(title: "통계 윈도우", value: r.motionWindowSeconds, unit: "초")
                    NumberField(title: "가속도 평균 하한", value: r.accMeanLow, unit: "g")
                    NumberField(title: "가속도 평균 상한", value: r.accMeanHigh, unit: "g")
                    NumberField(title: "가속도 분산 하한", value: r.accVarLow)
                    NumberField(title: "가속도 분산 상한", value: r.accVarHigh)
                    NumberField(title: "각속도 평균 하한", value: r.gyroMeanLow, unit: "rad/s")
                    NumberField(title: "각속도 평균 상한", value: r.gyroMeanHigh, unit: "rad/s")
                    NumberField(title: "각속도 분산 하한", value: r.gyroVarLow)
                    NumberField(title: "각속도 분산 상한", value: r.gyroVarHigh)
                    NumberField(title: "안정 판정 가속도", value: r.stableAccThreshold, unit: "g")
                    NumberField(title: "안정 판정 각속도", value: r.stableGyroThreshold, unit: "rad/s")
                    NumberField(title: "안정 유지 만점 시간", value: r.stableDurationForFull, unit: "초")
                    NumberField(title: "세부 가중치: 가속도", value: r.motionSubWeightAcc)
                    NumberField(title: "세부 가중치: 각속도", value: r.motionSubWeightGyro)
                    NumberField(title: "세부 가중치: 유지 시간", value: r.motionSubWeightDuration)
                    Text("하한 이하 만점, 상한 이상 0점, 사이는 선형. 가속도·각속도 각각 평균과 분산 점수 중 낮은 값을 씁니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("목표 취침 시간 허용 범위") {
                    NumberField(title: "만점 범위 (±)", value: r.bedtimePlateauMinutes, unit: "분")
                    NumberField(title: "목표 이전 적용 범위", value: r.bedtimeWindowBeforeMinutes, unit: "분")
                    NumberField(title: "목표 이후 적용 범위", value: r.bedtimeWindowAfterMinutes, unit: "분")
                }

                Section("최종 판정") {
                    NumberField(title: "판정 임계값", value: r.threshold, unit: "점")
                    NumberField(title: "판정 유지 시간", value: r.holdSeconds, unit: "초")
                    NumberField(title: "최소 데이터 비율", value: r.minDataRatio)
                }

                Section("위치 게이트") {
                    NumberField(title: "허용 위치 정확도", value: r.maxLocationAccuracy, unit: "m")
                    NumberField(title: "위치 최대 경과 시간", value: r.maxLocationAgeSeconds, unit: "초")
                }

                Section("정답 수집") {
                    NumberField(title: "응답 시 저장할 직전 구간", value: r.labelContextSeconds, unit: "초")
                }

                Section {
                    Button("기본값으로 초기화", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle("룰 설정")
            .keyboardDoneToolbar()
            .confirmationDialog("룰 설정을 기본값으로 되돌릴까요?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("초기화", role: .destructive) { settings.resetRules() }
            }
        }
    }
}

private struct BandEditor: View {
    @Binding var bands: [ScoreBand]
    let maxDeg: Double

    var body: some View {
        ForEach($bands) { $band in
            HStack(spacing: 6) {
                field($band.minDeg)
                Text("~")
                field($band.maxDeg)
                Text("°").foregroundStyle(.secondary)
                Spacer()
                Text("점수").foregroundStyle(.secondary).font(.footnote)
                field($band.score)
            }
        }
        .onDelete { bands.remove(atOffsets: $0) }
        Button("범위 추가") {
            let start = bands.last?.maxDeg ?? 0
            bands.append(ScoreBand(minDeg: min(start, maxDeg), maxDeg: maxDeg, score: 0))
        }
    }

    private func field(_ value: Binding<Double>) -> some View {
        TextField("", value: value, format: .number)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .frame(width: 52)
            .textFieldStyle(.roundedBorder)
    }
}
