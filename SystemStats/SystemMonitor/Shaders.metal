#include <metal_stdlib>
using namespace metal;

kernel void gpuLoadKernel(void) {
    // Reduced workload
    float result = 0;
    for (int i = 0; i < 100; i++) {  // Reduced iterations
        result += sin(float(i));
    }
} 