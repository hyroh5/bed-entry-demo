# SleepDemo — iOS 잠자리 진입 감지 데모

iPhone의 기기 자세·움직임·목표 취침 시간으로 "침대에 들어가 스마트폰을 사용하는 상태"인지 추정하는 SwiftUI 앱입니다. 실제 수면 여부는 판단하지 않습니다.

- iOS 17+, Swift / SwiftUI, Core Motion, Core Location, SwiftData, Swift Charts
- 머신러닝·개인화 없음 (하드 게이트 + 고정 룰 점수)

## 실행

```bash
brew install xcodegen   # 없을 때만
xcodegen generate       # project.yml → SleepDemo.xcodeproj
open SleepDemo.xcodeproj
```

실제 iPhone에서 실행하려면 Xcode에서 SleepDemo 타깃의 **Signing & Capabilities → Team**을 지정하세요. 번들 ID(`com.jeongdaegyun.sleepdemo`)가 겹치면 바꿔도 됩니다.

테스트: `xcodebuild test -scheme SleepDemo -destination 'platform=iOS Simulator,name=iPhone 17'`

## 구조

| 파일 | 책임 |
|---|---|
| `Services/MotionService` | `CMDeviceMotion` 수집 (기본 20Hz) |
| `Services/LocationService` | 집 반경 하드 게이트 (PASS / BLOCKED / UNKNOWN / 제한 해제) |
| `Services/DeviceStateService` | 충전 상태, 앱 활성 상태(`scenePhase`) |
| `Services/FeatureExtractor` | 윈도우 통계량: 가속도·각속도 크기의 평균/분산, 평균 중력 기울기, 안정 유지 시간 |
| `Services/RuleEngine` | 자세·움직임·취침시간 점수, 가중 합산, 유지 시간 판정 |
| `Persistence/` | SwiftData 모델(세션·샘플 배치·판정 기록·사용자 응답)과 저장소 |
| `Services/ExportService` | JSON(1개) / CSV(samples, scores, labels, label_context) 내보내기 |
| `MeasurementController` | 서비스를 묶어 세션 진행. 센서 20Hz, UI 4Hz, 판정·저장 1Hz |

## 판정 흐름

1. 앱이 활성 상태가 아니면 `BLOCKED`. 측정을 일시 중지하고 센서·위치를 끕니다. 화면이 꺼졌다는 뜻으로 보지 않습니다.
2. 위치 제한을 쓰는데 집 반경 밖이면 `BLOCKED`.
3. 윈도우 샘플이 `주기 × 윈도우 × 최소 데이터 비율`보다 적거나, 위치 권한·정확도·신선도가 부족하면 `UNKNOWN`.
4. 총점(0~100)이 임계값 이상이면 유지 시간을 세고, 유지 시간을 채우면 `POSSIBLY_IN_BED`, 그 전에는 `NOT_IN_BED`.

모든 가중치·각도 범위·분산 임계값·취침 허용 범위·임계값·유지 시간은 **룰** 탭에서 바꿀 수 있습니다. 설정 내용의 해시를 룰 버전으로 쓰고, 세션과 판정 기록마다 함께 저장합니다.

### 기기 기울기 정의 (평균 중력 벡터 기준)
- **화면 기울기**: 0° = 화면이 위를 향해 수평, 90° = 수직, 180° = 화면이 아래를 향함 (누워서 위로 들고 보는 자세)
- **측면 기울기**: 0° = 세로로 섬, 90° = 옆으로 눕힘. 중력의 화면 평면 성분이 `적용 최소 수평 성분` 이상일 때만 씁니다.
- 자세 점수는 둘 중 큰 값이며, 기본 각도 범위는 임시값입니다.

## 저장 데이터
- 원시 샘플은 약 5초 단위 배치(binary plist)로 저장합니다.
- 판정 기록(1초 간격)에는 점수, 상태, 게이트, 충전 상태, 룰 버전, 윈도우 통계량이 들어갑니다.
- 사용자 응답에는 응답 시점 예측과 직전 N초(기본 30초) 원시 샘플을 함께 저장합니다.
- 오분류는 예측이 `NOT_IN_BED` 또는 `POSSIBLY_IN_BED`일 때만 계산합니다.
- 집 좌표는 세션에 저장하지 않으며, 반경과 게이트 설정만 남깁니다.

## 시뮬레이터 / 실제 기기 구분
| 항목 | 시뮬레이터 | 실제 iPhone |
|---|---|---|
| UI, 세션 저장, 응답, 내보내기 | ✅ | ✅ |
| Device Motion (자세·가속도·자이로) | ❌ 사용 불가 → 항상 `UNKNOWN` | ✅ |
| 충전 상태 | ❌ `unknown` | ✅ |
| 위치 | 시뮬레이터 위치 설정으로 가능 | ✅ |
