import AppIntents

// The newer SDKs renamed @AssistantIntent(schema:) to @AppIntent(schema:) together with
// the member it generates; the older Xcode implements only the old member name.
// make-sdk.sh lets the new spelling accept the old member, so both work. (Only one
// type per app may adopt a schema, so the old spelling is not repeated here.)
@available(macOS 15, iOS 18, *)
@AppIntent(schema: .system.search)
struct SearchBooksIntent: ShowInAppSearchResultsIntent {
    static let searchScopes: [StringSearchScope] = [.general]
    var criteria: StringSearchCriteria

    @MainActor func perform() async throws -> some IntentResult { .result() }
}

@available(macOS 15, iOS 18, *)
@UnionValue
enum BookReference {
    case title(String)
    case number(Int)
}

@available(macOS 26, iOS 26, *)
struct BookEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Book"
    static let defaultQuery = BookQuery()

    var id: String
    @ComputedProperty var title: String { "Book \(id)" }
    @DeferredProperty var pageCount: Int {
        get async throws { 100 }
    }

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "Book \(id)") }
}

@available(macOS 26, iOS 26, *)
struct BookQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [BookEntity] {
        identifiers.map { BookEntity(id: $0) }
    }
}
