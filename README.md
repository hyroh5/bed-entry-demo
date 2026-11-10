# SleepDemo — 잠자리 진입 데이터 수집 앱

iPhone 센서와 위치, 사용자가 직접 입력한 "침대 안/밖" 상태를 함께 기록하는 SwiftUI 앱입니다. 지금 단계에서는 판정을 하지 않고 데이터만 모읍니다. 모은 데이터로 나중에 판정 방법(룰, 결정트리 등)을 오프라인에서 비교합니다.

- iOS 17+, Swift / SwiftUI, Core Motion, Core Location, SwiftData, Swift Charts, WebKit

## 실행

```bash
brew install xcodegen   # 없을 때만
xcodegen generate       # project.yml → SleepDemo.xcodeproj
open SleepDemo.xcodeproj
```

실제 iPhone에서 실행하려면 Xcode에서 SleepDemo 타깃의 **Signing & Capabilities → Team**을 지정하세요. 번들 ID(`com.jeongdaegyun.sleepdemo`)가 다른 앱과 겹치면 바꿔도 됩니다.

테스트: `xcodebuild test -scheme SleepDemo -destination 'platform=iOS Simulator,name=iPhone 17'`

## 화면

| 탭 | 내용 |
|---|---|
| 수집 | 측정 시작/종료, 상태 슬라이드(침대 밖 / 침대 안), 샘플·위치 기록 수 |
| 웹 | 앱 안에서 쓰는 웹 브라우저. 측정을 끊지 않고 폰을 쓸 수 있고, 위쪽에서 상태 슬라이드도 바꿀 수 있습니다. |
| 센서 | 실시간 자세, 가속도·각속도 그래프 |
| 기록 | 세션 목록과 상태 전환 내역, JSON/CSV 내보내기 |
| 설정 | 집 좌표, 센서 측정 주기 |

## 기록 방식
- 앱이 화면에 떠 있을 때만 기록합니다. 다른 앱으로 넘어가거나 화면을 잠그면 센서와 위치 기록을 멈추고, 돌아오면 다시 시작합니다. 측정 중에는 화면 자동 잠금을 끕니다.
- **원시 센서**는 기본 20Hz입니다. attitude, gravity, userAcceleration, rotationRate, 충전 상태를 담아 약 5초 단위 배치(binary plist)로 저장합니다.
- **상태 전환**은 상태 슬라이드를 바꿀 때마다 시각과 새 상태를 남깁니다.
- **위치**는 새 위치를 받을 때마다(최대 1Hz) 좌표, 정확도, 집까지 거리를 저장합니다. 집까지 거리는 집 좌표를 설정했을 때만 남습니다. 집 좌표 자체는 세션에 저장하지 않습니다.

## 내보내기
- JSON 1개 파일: 세션별 `samples`, `transitions`, `locations`
- CSV 3개 파일
  - `samples`: 원시 센서 기록. 각 샘플 시점의 상태 슬라이드 값(`in_bed`)이 들어 있고, 첫 전환 이전은 빈 값입니다.
  - `transitions`: 상태 전환 기록
  - `locations`: 위치 기록

## 시뮬레이터 / 실제 기기 구분
| 항목 | 시뮬레이터 | 실제 iPhone |
|---|---|---|
| UI, 세션 저장, 상태 전환, 내보내기, 웹 | ✅ | ✅ |
| Device Motion | ❌ 사용 불가 | ✅ |
| 충전 상태 | ❌ `unknown` | ✅ |
| 위치 | 시뮬레이터 위치 설정으로 가능 | ✅ |
