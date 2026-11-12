#include <metal_stdlib>
using namespace metal;

/// Adds two arrays element by element; ToolCheck runs it on the GPU.
kernel void add_arrays(device const float *a [[buffer(0)]],
                       device const float *b [[buffer(1)]],
                       device float *result [[buffer(2)]],
                       uint index [[thread_position_in_grid]]) {
    result[index] = a[index] + b[index];
}
