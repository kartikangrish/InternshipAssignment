import RealityKit
import ARKit
import Combine

class ARViewModel: ObservableObject {
    @Published var arView: ARView!
    
    // Set to track the AR session and configuration
    private var cancellables: Set<AnyCancellable> = []
    
    init() {
        arView = ARView(frame: .zero)
        
        // Configure the AR session for scene reconstruction
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.sceneReconstruction = .mesh
        
        arView.session.run(config)
        
        // Handle coaching overlay for user guidance
        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coachingOverlay.session = arView.session
        coachingOverlay.goal = .anyPlane
        arView.addSubview(coachingOverlay)
    }
    
    // Add furniture to the scene
    func addFurniture(named modelName: String) {
        guard let modelEntity = try? ModelEntity.loadModel(named: modelName) else {
            print("Failed to load model")
            return
        }
        
        // Enable physics for the model
        modelEntity.generateCollisionShapes(recursive: true)
        arView.installGestures([.translation, .rotation], for: modelEntity)
        
        // Anchor the model to the scene
        let anchorEntity = AnchorEntity(plane: .horizontal)
        anchorEntity.addChild(modelEntity)
        arView.scene.addAnchor(anchorEntity)
    }
}
