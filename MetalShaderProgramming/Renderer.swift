import MetalKit
import AVFoundation

// This class handles all the Metal rendering logic.
class Renderer: NSObject, MTKViewDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineStates: [String: MTLRenderPipelineState] = [:]
    var computePipelineStates: [String: MTLComputePipelineState] = [:]

    // Vertex data for a full-screen quad
    var vertexBuffer: MTLBuffer!
    // A time uniform for animations
    var time: Float = 0

    // Texture management for camera input
    var textureCache: CVMetalTextureCache!
    var sourceTexture: MTLTexture?
    
    // Intermediate textures for multi-pass effects like Gaussian blur
    var intermediateTexture: MTLTexture!

    init(mtkView: MTKView) {
        self.device = mtkView.device!
        self.commandQueue = device.makeCommandQueue()!

        super.init()

        buildVertexData()
        buildPipelines(mtkView: mtkView)
        buildTextureCache()
    }

    // Create a simple quad mesh that covers the screen
    private func buildVertexData() {
        // A quad is defined by 4 vertices, with position and texture coordinates
        let vertices: [Float] = [
            // Positions      // TexCoords
            -1.0, -1.0, 0.0,  0.0, 1.0,
             1.0, -1.0, 0.0,  1.0, 1.0,
            -1.0,  1.0, 0.0,  0.0, 0.0,
             1.0,  1.0, 0.0,  1.0, 0.0
        ]
        vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.size, options: [])
    }

    // Load shaders and create pipeline states
    private func buildPipelines(mtkView: MTKView) {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Could not load default Metal library")
        }

        // --- RENDER PIPELINES ---
        let vertexProgram = library.makeFunction(name: "vertex_wave")!
        let fragmentProgram = library.makeFunction(name: "fragment_effects")!

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexProgram
        pipelineDescriptor.fragmentFunction = fragmentProgram
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3 // position
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2 // texCoord
        vertexDescriptor.attributes[1].offset = 3 * MemoryLayout<Float>.size
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = 5 * MemoryLayout<Float>.size
        pipelineDescriptor.vertexDescriptor = vertexDescriptor


        do {
            pipelineStates["main"] = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Could not create render pipeline state: \(error)")
        }
        
        // --- COMPUTE PIPELINES ---
        let gaussianH = library.makeFunction(name: "compute_gaussian_horizontal")!
        let gaussianV = library.makeFunction(name: "compute_gaussian_vertical")!
        let edgeDetect = library.makeFunction(name: "compute_edge_detection")!

        do {
            computePipelineStates["gaussianH"] = try device.makeComputePipelineState(function: gaussianH)
            computePipelineStates["gaussianV"] = try device.makeComputePipelineState(function: gaussianV)
            computePipelineStates["edgeDetect"] = try device.makeComputePipelineState(function: edgeDetect)
        } catch {
            fatalError("Could not create compute pipeline state: \(error)")
        }
    }
    
    // Create a texture cache for converting camera frames to Metal textures efficiently
    private func buildTextureCache() {
        var newTextureCache: CVMetalTextureCache?
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &newTextureCache) != kCVReturnSuccess {
            fatalError("Unable to allocate texture cache")
        }
        textureCache = newTextureCache
    }
    
    // Delegate method called when the view size changes
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // This is where you would handle view resizing, if necessary
    }

    // Main draw loop
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let sourceTexture = sourceTexture,
              let pipelineState = pipelineStates["main"],
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        
        // Update time for animations
        time += 0.016 // Approximately 60 FPS

        // --- OPTIONAL: COMPUTE PASS ---
        // To enable a compute pass (like blur), uncomment the following block.
        // You would also need a UI to select which effect is active.
        /*
        let finalTexture: MTLTexture
        if effect_is_blur {
             // Create intermediate texture if it doesn't exist or size is wrong
            if intermediateTexture == nil || intermediateTexture.width != sourceTexture.width || intermediateTexture.height != sourceTexture.height {
                let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: sourceTexture.width, height: sourceTexture.height, mipmapped: false)
                desc.usage = [.shaderRead, .shaderWrite]
                intermediateTexture = device.makeTexture(descriptor: desc)
            }
        
            runComputePass(commandBuffer: commandBuffer, pipelineName: "gaussianH", source: sourceTexture, destination: intermediateTexture)
            runComputePass(commandBuffer: commandBuffer, pipelineName: "gaussianV", source: intermediateTexture, destination: drawable.texture)
            finalTexture = drawable.texture // The final result is now in the drawable
        } else {
            finalTexture = sourceTexture // No compute pass, use original
        }
        */
        
        // --- RENDER PASS ---
        let renderPassDescriptor = view.currentRenderPassDescriptor!
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBytes(&time, length: MemoryLayout<Float>.size, index: 1)
        
        // The source texture for the fragment shader
        renderEncoder.setFragmentTexture(sourceTexture, index: 0)

        // Draw the quad as two triangles
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    // Helper for running compute shaders
    private func runComputePass(commandBuffer: MTLCommandBuffer, pipelineName: String, source: MTLTexture, destination: MTLTexture) {
        guard let computePipelineState = computePipelineStates[pipelineName],
              let computeCommandEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
        
        computeCommandEncoder.setComputePipelineState(computePipelineState)
        computeCommandEncoder.setTexture(source, index: 0)
        computeCommandEncoder.setTexture(destination, index: 1)
        
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroupCount = MTLSize(
            width: (source.width + threadgroupSize.width - 1) / threadgroupSize.width,
            height: (source.height + threadgroupSize.height - 1) / threadgroupSize.height,
            depth: 1
        )
        
        computeCommandEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        computeCommandEncoder.endEncoding()
    }

    // Delegate method to receive camera frames
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvTexture)
        
        if status == kCVReturnSuccess, let texture = cvTexture {
            self.sourceTexture = CVMetalTextureGetTexture(texture)
        }
    }
}
