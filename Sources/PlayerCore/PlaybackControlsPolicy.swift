import Foundation

/// Ephemeral presentation policy. Never changes saved playback or sidebar settings.
public struct PlaybackControlsPolicy: Sendable {
    public static let idleDelay = 3.0
    public private(set) var fullscreen = false
    public private(set) var hidden = false
    private var lastActivity = 0.0
    public init() {}
    public mutating func setFullscreen(_ value: Bool, at time: Double) {
        fullscreen = value; hidden = false; lastActivity = time
    }
    public mutating func activity(at time: Double) {
        hidden = false; lastActivity = time
    }
    public mutating func evaluate(at time: Double, canHide: Bool, interactionHeld: Bool) {
        guard fullscreen && canHide && !interactionHeld else {
            hidden = false; lastActivity = time; return
        }
        hidden = time - lastActivity >= Self.idleDelay
    }
}
