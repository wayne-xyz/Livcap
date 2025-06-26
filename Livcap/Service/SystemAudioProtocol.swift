import Foundation

@available(macOS 10.15, *)
protocol SystemAudioProtocol: AnyObject {
    func startCapture() async throws
    func stopCapture()
    func systemAudioStream() -> AsyncStream<[Float]>
    var systemAudioLevel: Float { get }
} 