import UIKit
import MetalKit
import AVFoundation

// This View Controller manages the MetalKit View and the camera session.
class ViewController: UIViewController {

    var mtkView: MTKView!
    var renderer: Renderer!
    var captureSession: AVCaptureSession!
    var videoOutput: AVCaptureVideoDataOutput!

    override func viewDidLoad() {
        super.viewDidLoad()

        // 1. Setup MetalKit View
        mtkView = self.view as? MTKView
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        mtkView.device = device
        mtkView.framebufferOnly = false // Required for texture sampling
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        // 2. Setup the Renderer
        // The renderer will handle all drawing and Metal logic.
        renderer = Renderer(mtkView: mtkView)
        mtkView.delegate = renderer

        // 3. Setup Camera
        setupCamera()
    }

    func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .hd1280x720 // A good balance of quality and performance

        // Find the back camera
        guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Failed to get the camera device")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: captureDevice)
            captureSession.addInput(input)
        } catch {
            print("Error setting device input: \(error)")
            return
        }

        // Setup the video output
        videoOutput = AVCaptureVideoDataOutput()
        // Required for Metal texture cache
        let videoQueue = DispatchQueue(label: "videoQueue", qos: .userInteractive)
        videoOutput.setSampleBufferDelegate(renderer, queue: videoQueue)
        
        // Set the pixel format for the camera output. BGRA is native for Metal.
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        } else {
            print("Could not add video data output to the session")
            return
        }
        
        // Start the session on a background thread to avoid blocking the UI
        DispatchQueue.global(qos: .background).async {
            self.captureSession.startRunning()
        }
    }
}
