import SwiftUI
import RealityKit

struct ContentView: View {
    @StateObject private var viewModel = ARViewModel()
    
    // List of available furniture models
    private let furnitureModels = ["chair_swan", "cup_saucer_set", "fender_stratocaster", "gramophone", "pot_plant", "teapot", "toy_biplane", "toy_car", "tv_retro", "wateringcan"]
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ARViewContainer(viewModel: viewModel)
                .edgesIgnoringSafeArea(.all)
            
            // Furniture selection UI
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 30) {
                    ForEach(furnitureModels, id: \.self) { modelName in
                        Button(action: {
                            viewModel.addFurniture(named: modelName)
                        }) {
                            Image(uiImage: UIImage(named: modelName)!)
                                .resizable()
                                .frame(height: 80)
                                .aspectRatio(1/1, contentMode: .fit)
                                .background(Color.white.opacity(0.8))
                                .cornerRadius(12)
                        }
                    }
                }
                .padding()
            }
        }
    }
}
