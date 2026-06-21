#include <metal_stdlib>
using namespace metal;

struct MaskDecodeParams {
    uint width;
    uint height;
    uint min_x;
    uint max_x;
    uint min_y;
    uint max_y;
    float threshold;
};

kernel void yolo_mask_decode_spmd(
    device const float* coefficients [[buffer(0)]],
    device const float* prototypes [[buffer(1)]],
    device uchar* output [[buffer(2)]],
    constant MaskDecodeParams& params [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    const uint x = gid.x;
    const uint y = gid.y;
    const uint out_index = y * params.width + x;

    if (x < params.min_x || x > params.max_x || y < params.min_y || y > params.max_y) {
        output[out_index] = 0;
        return;
    }

    float total = 0.0f;
    const uint plane_size = params.width * params.height;
    for (uint channel = 0; channel < 32; ++channel) {
        const uint proto_index = channel * plane_size + out_index;
        total += coefficients[channel] * prototypes[proto_index];
    }

    const float probability = 1.0f / (1.0f + exp(-total));
    if (probability < params.threshold) {
        output[out_index] = 0;
        return;
    }

    const float shaped = clamp((probability - params.threshold) / (1.0f - params.threshold), 0.0f, 1.0f);
    output[out_index] = static_cast<uchar>(70.0f + shaped * 125.0f);
}
