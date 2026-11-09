import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("대시보드", systemImage: "gauge.with.dots.needle.67percent") }
            SensorAnalysisView()
                .tabItem { Label("센서", systemImage: "waveform.path.ecg") }
            RecordsView()
                .tabItem { Label("기록", systemImage: "list.bullet.rectangle") }
            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape") }
            RuleSettingsView()
                .tabItem { Label("룰", systemImage: "slider.horizontal.3") }
        }
    }
}
