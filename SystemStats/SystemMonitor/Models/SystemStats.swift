import Foundation
import IOKit
import IOKit.ps
import Metal
import QuartzCore

class SystemStats: ObservableObject {
    @Published var cpuUsage: Double = 0
    @Published var memoryUsage: Double = 0
    @Published var gpuUsage: Double = 0
    @Published var batteryLevel: Double = 0
    
    private var previousCPUInfo: processor_info_array_t?
    private var previousCPUInfoCnt: mach_msg_type_number_t = 0
    private var timer: Timer?
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var lastGPUTime: TimeInterval = 0
    
    init() {
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device?.makeCommandQueue()
        startMonitoring()
    }
    
    private func getGPUUsage() -> Double {
        guard let device = device,
              let commandQueue = commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return 0
        }
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let currentTime = CACurrentMediaTime()
        
        // Get optional values
        let startTime: TimeInterval? = commandBuffer.gpuStartTime
        let endTime: TimeInterval? = commandBuffer.gpuEndTime
        
        if let start = startTime, let end = endTime {
            let gpuDuration = end - start
            let timeDelta = currentTime - lastGPUTime
            
            if lastGPUTime == 0 {
                lastGPUTime = currentTime
                return 0
            }
            
            lastGPUTime = currentTime
            
            // Calculate GPU utilization as a percentage
            let utilization = (gpuDuration / timeDelta) * 100.0
            return min(max(utilization, 0), 100)
        }
        
        return 0
    }
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
    }
    
    private func updateStats() {
        cpuUsage = getCPUUsage()
        memoryUsage = getMemoryUsage()
        gpuUsage = getGPUUsage()
        batteryLevel = getBatteryLevel()
    }
    
    private func getCPUUsage() -> Double {
        var processorInfo: processor_info_array_t?
        var numCPUs: natural_t = 0
        var numCPUsU: natural_t = 0
        let err = host_processor_info(mach_host_self(),
                                    PROCESSOR_CPU_LOAD_INFO,
                                    &numCPUs,
                                    &processorInfo,
                                    &numCPUsU)
        
        guard err == KERN_SUCCESS, let processorInfo = processorInfo else {
            return 0.0
        }
        
        var totalUsage: Double = 0.0
        
        if let previousCPUInfo = previousCPUInfo {
            for i in 0..<Int(numCPUs) {
                let inUse = Double(processorInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_USER)]
                    + processorInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_SYSTEM)]
                    + processorInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_NICE)])
                
                let total = inUse + Double(processorInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_IDLE)])
                
                let prevInUse = Double(previousCPUInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_USER)]
                    + previousCPUInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_SYSTEM)]
                    + previousCPUInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_NICE)])
                
                let prevTotal = prevInUse + Double(previousCPUInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_IDLE)])
                
                let delta = total - prevTotal
                let usage = (delta == 0) ? 0.0 : ((inUse - prevInUse) / delta) * 100.0
                totalUsage += usage
            }
        }
        
        if let prevCPUInfo = previousCPUInfo {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prevCPUInfo), vm_size_t(previousCPUInfoCnt))
        }
        
        previousCPUInfo = processorInfo
        previousCPUInfoCnt = numCPUsU
        
        return min(max(totalUsage / Double(numCPUs), 0), 100)
    }
    
    private func getMemoryUsage() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &stats) { statsPtr -> kern_return_t in
            statsPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
                host_statistics64(mach_host_self(),
                                HOST_VM_INFO64,
                                ptr,
                                &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let pageSize = vm_kernel_page_size
            
            // Calculate used memory (active + inactive + wired + compressed)
            let active = Double(stats.active_count) * Double(pageSize)
            let inactive = Double(stats.inactive_count) * Double(pageSize)
            let wired = Double(stats.wire_count) * Double(pageSize)
            let compressed = Double(stats.compressor_page_count) * Double(pageSize)
            
            let used = active + wired + compressed
            let total = Double(ProcessInfo.processInfo.physicalMemory)
            
            // Convert to percentage of total memory
            return min((used / total) * 100.0, 100.0)
        }
        
        return 0
    }
    
    private func getBatteryLevel() -> Double {
        let powerSource = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let powerSourcesList = IOPSCopyPowerSourcesList(powerSource).takeRetainedValue() as Array
        
        for ps in powerSourcesList {
            if let powerSourceDesc = IOPSGetPowerSourceDescription(powerSource, ps).takeUnretainedValue() as? [String: Any] {
                if let capacity = powerSourceDesc[kIOPSCurrentCapacityKey] as? Int {
                    return Double(capacity)
                }
            }
        }
        
        return 100.0 // Return 100 if on AC power or no battery found
    }
    
    deinit {
        if let previousCPUInfo = previousCPUInfo {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: previousCPUInfo), vm_size_t(previousCPUInfoCnt))
        }
        timer?.invalidate()
    }
} 