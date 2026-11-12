import SwiftUI
import TipKit

struct FavoriteTip: Tip {
    // The macro needs the type spelled out.
    @Parameter static var hasSeenIntro: Bool = false

    var title: Text { Text("Favorites") }
    var rules: [Rule] {
        #Rule(Self.$hasSeenIntro) { $0 == true }
    }
}
