import Observation

@Observable final class Counter {
    var count = 0
    @ObservationIgnored var cache: [Int] = []
}

func observedCount(_ counter: Counter) -> Int {
    withObservationTracking { counter.count } onChange: {}
}
