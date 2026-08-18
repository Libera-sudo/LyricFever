import AppKit
import ScriptingBridge

// Generic ScriptingBridge protocol shims inherited by Apple's generated
// MusicApplication and MusicItem bindings.
@objc public protocol SBObjectProtocol: NSObjectProtocol {
    func get() -> Any!
}

@objc public protocol SBApplicationProtocol: SBObjectProtocol {
    func activate()
    var delegate: SBApplicationDelegate! { get set }
    var isRunning: Bool { get }
}
