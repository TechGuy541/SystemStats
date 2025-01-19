import SwiftUI

struct ContentView: View {
    @StateObject private var systemStats = SystemStats()
    @State private var selectedStat: StatType = .cpu
    @State private var cpuData: [Double] = Array(repeating: 0, count: 60)
    @State private var gpuData: [Double] = Array(repeating: 0, count: 60)
    @State private var ramData: [Double] = Array(repeating: 0, count: 60)
    
    enum StatType {
        case cpu, gpu, ram
    }
    
    var body: some View {
        VStack(spacing: 8) {
            
            VStack(spacing: 4) {
                StatButton(title: "CPU", value: systemStats.cpuUsage, color: .red, isSelected: selectedStat == .cpu) {
                    selectedStat = .cpu
                }
                StatButton(title: "GPU", value: systemStats.gpuUsage, color: .green, isSelected: selectedStat == .gpu) {
                    selectedStat = .gpu
                }
                StatButton(title: "RAM", value: systemStats.memoryUsage, color: .blue, isSelected: selectedStat == .ram) {
                    selectedStat = .ram
                }
            }
            .padding(.vertical, 8)
            
            
            GeometryReader { geometry in
                Path { path in
                    let width = geometry.size.width / CGFloat(59)
                    let height = geometry.size.height
                    let data = selectedData
                    
                    path.move(to: CGPoint(x: 0, y: height * (1 - data[0] / 100)))
                    
                    for index in 1..<data.count {
                        let point = CGPoint(
                            x: width * CGFloat(index),
                            y: height * (1 - data[index] / 100)
                        )
                        path.addLine(to: point)
                    }
                }
                .stroke(selectedColor, lineWidth: 2)
            }
            .frame(height: 200)
            .padding()
            .background(Color.black.opacity(0.1))
            .cornerRadius(8)
        }
        .frame(width: 300)
        .onAppear {
            startCollectingData()
        }
    }
    
    private var selectedData: [Double] {
        switch selectedStat {
        case .cpu: return cpuData
        case .gpu: return gpuData
        case .ram: return ramData
        }
    }
    
    private var selectedColor: Color {
        switch selectedStat {
        case .cpu: return .red
        case .gpu: return .green
        case .ram: return .blue
        }
    }
    
    private func startCollectingData() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            cpuData.removeFirst()
            cpuData.append(systemStats.cpuUsage)
            
            gpuData.removeFirst()
            gpuData.append(systemStats.gpuUsage)
            
            ramData.removeFirst()
            ramData.append(systemStats.memoryUsage)
        }
    }
}

struct StatButton: View {
    let title: String
    let value: Double
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(value))%")
                    .font(.system(size: 12, weight: .bold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(isSelected ? color.opacity(0.2) : Color.clear)
            .foregroundColor(color)
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
