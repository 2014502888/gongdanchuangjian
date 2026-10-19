import SwiftUI

@main
struct GongdanApp: App {
    init() {
        NeiwangHarConfig.shared.load()
    }
    var body: some Scene {
        WindowGroup {
            GongdanMainView()
        }
    }
}
