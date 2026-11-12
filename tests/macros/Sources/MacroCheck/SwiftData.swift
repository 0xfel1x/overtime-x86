import Foundation
import SwiftData

@Model final class Note {
    @Attribute(.unique) var title: String
    var body: String
    @Relationship(deleteRule: .cascade) var tags: [Tag] = []
    @Transient var isSelected = false

    init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

@Model final class Tag {
    var name: String
    init(name: String) { self.name = name }
}

@available(macOS 15, iOS 18, *)
@Model final class IndexedNote {
    #Index<IndexedNote>([\.title], [\.title, \.created])
    #Unique<IndexedNote>([\.title])
    var title: String
    var created: Date

    init(title: String, created: Date) {
        self.title = title
        self.created = created
    }
}

@ModelActor actor NoteStore {
    func noteCount() throws -> Int { try modelContext.fetchCount(FetchDescriptor<Note>()) }
}
