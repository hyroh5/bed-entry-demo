import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("수집", systemImage: "record.circle") }
            BrowserView()
                .tabItem { Label("웹", systemImage: "safari") }
            SensorAnalysisView()
                .tabItem { Label("센서", systemImage: "waveform.path.ecg") }
            RecordsView()
                .tabItem { Label("기록", systemImage: "list.bullet.rectangle") }
            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape") }
        }
    }
}
