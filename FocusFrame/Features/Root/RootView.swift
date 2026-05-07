import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Timer", systemImage: "timer") {
                TimerView()
            }
            Tab("History", systemImage: "list.bullet") {
                HistoryView()
            }
        }
        .tint(.focusAccent)
    }
}
