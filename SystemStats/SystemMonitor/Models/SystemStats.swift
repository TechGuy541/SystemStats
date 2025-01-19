//Tech Guy 2025

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
    
    private var gpuService: io_service_t = 0
    private var previousGPUTime: UInt64 = 0
    private var previousSystemTime: UInt64 = 0
    
    init() {
        setupGPUMonitoring()
        startMonitoring()
    }
    
    private func setupGPUMonitoring() {
        print("Setting up GPU monitoring...")
        let matching = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0
        
        let result = IOServiceGetMatchingServices(kIOMasterPortDefault, matching, &iterator)
        print("IOServiceGetMatchingServices result: \(result)")
        
        if result == KERN_SUCCESS {
            gpuService = IOIteratorNext(iterator)
            print("Found GPU service: \(gpuService)")
            IOObjectRelease(iterator)
        }
        
        if gpuService == 0 {
            print("No GPU accelerator found")
        }
    }
    
    private func getGPUUsage() -> Double {
        guard gpuService != 0 else { return 0 }
        
        var properties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(gpuService, &properties, kCFAllocatorDefault, 0)
        
        guard result == KERN_SUCCESS,
              let props = properties?.takeRetainedValue() as? [String: Any],
              let stats = props["PerformanceStatistics"] as? [String: Any] else {
            return 0
        }
        
       
        let rendererUtilization = stats["Renderer Utilization %"] as? Int ?? 0
        
  
        let deviceUtilization = stats["Device Utilization %"] as? Int ?? 0
        let tilerUtilization = stats["Tiler Utilization %"] as? Int ?? 0
        print("Device: \(deviceUtilization)%, Renderer: \(rendererUtilization)%, Tiler: \(tilerUtilization)%")
        
        
        return Double(rendererUtilization)
    }
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
        
        updateStats()
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
            
            
            let active = Double(stats.active_count) * Double(pageSize)
            let inactive = Double(stats.inactive_count) * Double(pageSize)
            let wired = Double(stats.wire_count) * Double(pageSize)
            let compressed = Double(stats.compressor_page_count) * Double(pageSize)
            
            let used = active + wired + compressed
            let total = Double(ProcessInfo.processInfo.physicalMemory)
            
          
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
        
        return 100.0 
    }
    
    deinit {
        if let previousCPUInfo = previousCPUInfo {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: previousCPUInfo), vm_size_t(previousCPUInfoCnt))
        }
        if gpuService != 0 {
            IOObjectRelease(gpuService)
        }
        timer?.invalidate()
    }
} 
