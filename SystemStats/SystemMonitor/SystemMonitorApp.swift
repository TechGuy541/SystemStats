//Tech Guy 2025


import SwiftUI

@main
struct SystemMonitorApp: App {
    @StateObject private var systemStats = SystemStats()
    
    init() {
        
        NSApplication.shared.setActivationPolicy(.accessory)
    }
    
    var body: some Scene {
        MenuBarExtra {
            ContentView()
        } label: {
            Image(systemName: "gauge.medium")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(getColorForHighestUsage())
                .font(.system(size: 12))
        }
        .menuBarExtraStyle(.window)
    }
    
    private func getColorForHighestUsage() -> Color {
        let usages = [
            (value: systemStats.cpuUsage, color: Color.red),
            (value: systemStats.gpuUsage, color: Color.green),
            (value: systemStats.memoryUsage, color: Color.blue)
        ]
        
        return usages.max(by: { $0.value < $1.value })?.color ?? .primary
    }
} 
