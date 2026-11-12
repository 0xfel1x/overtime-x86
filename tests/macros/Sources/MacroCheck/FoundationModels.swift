import FoundationModels

@available(macOS 26, iOS 26, *)
@Generable
struct Recipe {
    @Guide(description: "A short title")
    var title: String
    @Guide(.range(1...12))
    var servings: Int
}
