#include <metal_stdlib>
using namespace metal;

// Structure to pass data from Vertex to Fragment Shader
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Structure for uniforms passed from the CPU
struct Uniforms {
    float time;
};

// ===================================================================
//
//                        VERTEX SHADERS
//
// ===================================================================

// --- Vertex Shader: Animated Wave Distortion ---
// Displaces vertices using a sine wave that animates over time.
vertex VertexOut vertex_wave(const device packed_float3* vertex_array [[buffer(0)]],
                             const device packed_float2* texcoord_array [[buffer(0)]], // Note: Interleaved data
                             constant float &time [[buffer(1)]],
                             uint vertex_id [[vertex_id]]) {
    
    // De-interleave vertex data
    float3 position = vertex_array[vertex_id];
    float2 texCoord = texcoord_array[vertex_id];

    VertexOut out;
    
    // Calculate displacement
    float displacement = 0.1 * sin(position.x * 20.0 + time * 5.0);
    position.y += displacement;
    
    out.position = float4(position, 1.0);
    out.texCoord = texCoord;
    
    return out;
}

// --- Vertex Shader: Magnifying Glass (Warp) ---
// To use this, you'd need a more finely tessellated mesh and pass mouse/touch
// coordinates as a uniform.
vertex VertexOut vertex_magnify(const device packed_float3* vertex_array [[buffer(0)]],
                                const device packed_float2* texcoord_array [[buffer(0)]],
                                constant float2 &touchPos [[buffer(1)]], // Normalized touch position (0-1)
                                uint vertex_id [[vertex_id]]) {
    
    float3 position = vertex_array[vertex_id];
    float2 texCoord = texcoord_array[vertex_id];
    
    VertexOut out;
    
    float2 center = touchPos * 2.0 - 1.0; // Convert from 0-1 to -1 to 1
    center.y *= -1.0; // Invert Y for screen coordinates
    float radius = 0.5;
    float distance = distance(position.xy, center);
    
    if (distance < radius) {
        float factor = 1.0 - distance / radius;
        position.xy -= normalize(position.xy - center) * factor * 0.2;
    }
    
    out.position = float4(position, 1.0);
    out.texCoord = texCoord;
    
    return out;
}


// ===================================================================
//
//                       FRAGMENT SHADERS
//
// ===================================================================

// --- Fragment Shader: Advanced Color Effects ---
// Applies Chromatic Aberration, Vignette, and Film Grain.
fragment float4 fragment_effects(VertexOut in [[stage_in]],
                                 texture2d<float> sourceTexture [[texture(0)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    // --- 1. Chromatic Aberration ---
    // Sample the texture at slightly different points for R, G, B channels.
    float2 offset = float2(0.01, 0.0);
    float r = sourceTexture.sample(s, in.texCoord - offset).r;
    float g = sourceTexture.sample(s, in.texCoord).g;
    float b = sourceTexture.sample(s, in.texCoord + offset).b;
    float4 color = float4(r, g, b, 1.0);
    
    // --- 2. Vignette ---
    // Darken the edges of the screen.
    float2 dist = in.texCoord - float2(0.5);
    float vignette = 1.0 - dot(dist, dist) * 1.5;
    color.rgb *= vignette;
    
    // --- 3. Film Grain ---
    // Add procedural noise.
    float grain = (fract(sin(dot(in.texCoord, float2(12.9898, 78.233))) * 43758.5453) - 0.5) * 0.15;
    color.rgb += grain;
    
    // --- 4. Tone Mapping (Simple Reinhard) ---
    // Compresses high dynamic range colors into a displayable range.
    color.rgb = color.rgb / (color.rgb + float3(1.0));
    
    // Clamp final color to ensure it's valid
    return clamp(color, 0.0, 1.0);
}


// ===================================================================
//
//                        COMPUTE SHADERS (KERNELS)
//
// ===================================================================

// --- Compute Kernel: Separable Gaussian Blur (Horizontal) ---
kernel void compute_gaussian_horizontal(texture2d<float, access::read> inTexture [[texture(0)]],
                                        texture2d<float, access::write> outTexture [[texture(1)]],
                                        uint2 gid [[thread_position_in_grid]]) {
    
    // A 5x1 Gaussian kernel
    float weights[] = { 0.0545, 0.2442, 0.4026, 0.2442, 0.0545 };
    float4 sum = float4(0.0);
    
    for (int i = -2; i <= 2; ++i) {
        sum += inTexture.read(gid + uint2(i, 0)) * weights[i + 2];
    }
    
    outTexture.write(sum, gid);
}

// --- Compute Kernel: Separable Gaussian Blur (Vertical) ---
kernel void compute_gaussian_vertical(texture2d<float, access::read> inTexture [[texture(0)]],
                                      texture2d<float, access::write> outTexture [[texture(1)]],
                                      uint2 gid [[thread_position_in_grid]]) {
    
    float weights[] = { 0.0545, 0.2442, 0.4026, 0.2442, 0.0545 };
    float4 sum = float4(0.0);
    
    for (int i = -2; i <= 2; ++i) {
        sum += inTexture.read(gid + uint2(0, i)) * weights[i + 2];
    }
    
    outTexture.write(sum, gid);
}

// --- Compute Kernel: Edge Detection (Sobel Filter) ---
kernel void compute_edge_detection(texture2d<float, access::read> inTexture [[texture(0)]],
                                   texture2d<float, access::write> outTexture [[texture(1)]],
                                   uint2 gid [[thread_position_in_grid]]) {
    
    // Sobel operators
    float Gx[9] = { -1, 0, 1, -2, 0, 2, -1, 0, 1 };
    float Gy[9] = { -1, -2, -1, 0, 0, 0, 1, 2, 1 };
    
    float sumX = 0.0;
    float sumY = 0.0;
    
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float intensity = inTexture.read(gid + uint2(x,y)).r; // Use red channel for intensity
            int index = (y + 1) * 3 + (x + 1);
            sumX += intensity * Gx[index];
            sumY += intensity * Gy[index];
        }
    }
    
    float magnitude = sqrt(sumX * sumX + sumY * sumY);
    outTexture.write(float4(magnitude, magnitude, magnitude, 1.0), gid);
}
