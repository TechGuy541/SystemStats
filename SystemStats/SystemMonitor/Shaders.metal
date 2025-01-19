//Tech Guy 2025

#include <metal_stdlib>
using namespace metal;

kernel void gpuLoadKernel(void) {

    float result = 0;
    for (int i = 0; i < 100; i++) {
        result += sin(float(i));
    }
} 
