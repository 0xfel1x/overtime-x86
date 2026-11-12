import Foundation

struct Item {
    var name: String
    var size: Int
}

func largeItems(_ items: [Item]) throws -> [Item] {
    let predicate = #Predicate<Item> { $0.size > 3 && $0.name.contains("a") }
    return try items.filter(predicate)
}

@available(macOS 15, iOS 18, *)
func isPositive(_ value: Int) throws -> Bool {
    let expression = #Expression<Int, Bool> { $0 > 0 }
    return try expression.evaluate(value)
}

func currentBundle() -> Bundle { #bundle }
