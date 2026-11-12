import Distributed

@DebugDescription
struct Point {
    var x: Int
    var y: Int
    var debugDescription: String { "(\(x), \(y))" }
}

enum RequestContext {
    @TaskLocal static var requestID = "none"
}

// The generated stub needs macOS 15 / iOS 18 although the macro is declared earlier.
@available(macOS 15, iOS 18, *)
@Resolvable
protocol Greeter: DistributedActor where ActorSystem == LocalTestingDistributedActorSystem {
    distributed func greet(_ name: String) -> String
}
