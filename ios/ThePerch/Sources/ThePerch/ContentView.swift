import SwiftUI

/// The main dashboard view, now replaced by MainTabView.
/// This file is kept for backward compatibility but the real UI is in MainTabView.
struct ContentView: View {
    var body: some View {
        MainTabView()
    }
}

#Preview {
    ContentView()
        .environment(DashboardViewModel())
}
