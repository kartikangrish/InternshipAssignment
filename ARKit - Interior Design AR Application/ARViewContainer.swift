import SwiftUI
import RealityKit

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var viewModel: ARViewModel
    
    func makeUIView(context: Context) -> ARView {
        return viewModel.arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}
