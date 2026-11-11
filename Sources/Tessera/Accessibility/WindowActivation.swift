import AppKit

/// Gives keyboard focus to one specific window.
///
/// The public route (activate the app, then mark the window main over AX) is unreliable when the app
/// has windows on several displays: activation is asynchronous and the app then re-focuses whichever
/// window *it* last had key, undoing the request. So, like AltTab and yabai, ask the window server
/// directly through SkyLight to bring the process forward with that exact window, then make it key.
/// The private calls are looked up at runtime; if a macOS release drops them, the AX route is used.
enum WindowActivation {
    /// `element` is the window's AX counterpart, when the app exposes one.
    static func focus(_ windowID: CGWindowID, pid: pid_t, element window: AXWindow?) {
        if let skyLight = SkyLight.shared, skyLight.focus(windowID, pid: pid) {
            if let window { AXUIElementPerformAction(window.element, kAXRaiseAction as CFString) }
            return
        }
        let app = AXUIElementCreateApplication(pid)
        app.set(kAXFrontmostAttribute, kCFBooleanTrue)
        if let window {
            window.element.set(kAXMainAttribute, kCFBooleanTrue)
            AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        }
    }
}

/// `@unchecked Sendable`: immutable C function pointers, resolved once.
private struct SkyLight: @unchecked Sendable {
    private typealias GetProcessForPID = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias SetFrontProcessWithOptions = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    private typealias PostEventRecordTo = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError

    private let processForPID: GetProcessForPID
    private let setFrontProcess: SetFrontProcessWithOptions
    private let postEventRecord: PostEventRecordTo

    /// kCPSUserGenerated: treat the switch as if the user clicked the window.
    private static let userGenerated: UInt32 = 0x200

    static let shared: SkyLight? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let processForPID = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "GetProcessForPID"), // RTLD_DEFAULT
              let setFront = dlsym(handle, "_SLPSSetFrontProcessWithOptions"),
              let post = dlsym(handle, "SLPSPostEventRecordTo")
        else { return nil }
        return SkyLight(processForPID: unsafeBitCast(processForPID, to: GetProcessForPID.self),
                        setFrontProcess: unsafeBitCast(setFront, to: SetFrontProcessWithOptions.self),
                        postEventRecord: unsafeBitCast(post, to: PostEventRecordTo.self))
    }()

    func focus(_ windowID: CGWindowID, pid: pid_t) -> Bool {
        var psn = ProcessSerialNumber()
        guard processForPID(pid, &psn) == noErr,
              setFrontProcess(&psn, windowID, Self.userGenerated) == .success
        else { return false }
        makeKey(windowID, psn: &psn)
        return true
    }

    /// The two synthetic window-server records (focus-in phases 1 and 2) that make a window key
    /// within its now-frontmost app; layout as used by yabai and AltTab.
    private func makeKey(_ windowID: CGWindowID, psn: inout ProcessSerialNumber) {
        for phase: UInt8 in [0x01, 0x02] {
            var record = [UInt8](repeating: 0, count: 0xf8)
            record[0x04] = 0xf8
            record[0x08] = phase
            record[0x3a] = 0x10
            for i in 0x20..<0x30 { record[i] = 0xff }
            withUnsafeBytes(of: windowID.littleEndian) { record.replaceSubrange(0x3c..<0x40, with: $0) }
            _ = record.withUnsafeMutableBufferPointer { postEventRecord(&psn, $0.baseAddress!) }
        }
    }
}
