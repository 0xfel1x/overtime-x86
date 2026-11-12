import CoreML
import Foundation
import Metal

/// The checks both apps run; one line per check.
enum ToolCheck {
    static func run() -> [String] {
        [
            "objc: \(OTGreeter().greeting(for: "Overtime")), \(OTGreeter.platformName)",
            "c++: \(OTChecksum.checksum(of: "Overtime"))",
            "c: \(ot_hypot(3, 4))",
            "string catalog: \(String(localized: "greeting"))",
            "core ml: \(coreML())",
            "metal: \(metal())",
        ]
    }

    /// Runs the add_arrays kernel from the app's default.metallib.
    private static func metal() -> String {
        guard let device = MTLCreateSystemDefaultDevice() else { return "no GPU" }
        guard let library = device.makeDefaultLibrary() else { return "no shader library (shaders left out)" }
        let a: [Float] = [1, 2, 3, 4]
        let b: [Float] = [10, 20, 30, 40]
        let length = a.count * MemoryLayout<Float>.stride
        guard let function = library.makeFunction(name: "add_arrays"),
              let pipeline = try? device.makeComputePipelineState(function: function),
              let commands = device.makeCommandQueue()?.makeCommandBuffer(),
              let encoder = commands.makeComputeCommandEncoder(),
              let bufferA = device.makeBuffer(bytes: a, length: length),
              let bufferB = device.makeBuffer(bytes: b, length: length),
              let result = device.makeBuffer(length: length) else { return "setup failed" }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(bufferA, offset: 0, index: 0)
        encoder.setBuffer(bufferB, offset: 0, index: 1)
        encoder.setBuffer(result, offset: 0, index: 2)
        encoder.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1),
                                     threadsPerThreadgroup: MTLSize(width: a.count, height: 1, depth: 1))
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        let values = UnsafeBufferPointer(start: result.contents().assumingMemoryBound(to: Float.self), count: a.count)
        return values.map { String(Int($0)) }.joined(separator: " ")
    }

    private static func coreML() -> String {
        do {
            let model = try Adder(configuration: MLModelConfiguration())
            let input = try MLMultiArray(shape: [2], dataType: .double)
            input[0] = 2
            input[1] = 3
            return "2 + 3 = \(try model.prediction(x: input).y)"
        } catch {
            return "failed: \(error)"
        }
    }
}
