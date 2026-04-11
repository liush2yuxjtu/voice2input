import ApplicationServices
import Foundation

final class GlobalFunctionKeyMonitor {
    var onFunctionKeyChange: ((Bool) -> Void)?
    private(set) var isRunning = false
    private(set) var activeTapName = "none"

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isFunctionKeyPressed = false

    func start() -> Bool {
        stop()

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<GlobalFunctionKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }

        let tapCandidates: [(CGEventTapLocation, String)] = [
            (.cghidEventTap, "cghidEventTap"),
            (.cgSessionEventTap, "cgSessionEventTap")
        ]

        var createdTap: CFMachPort?
        var createdTapName = "none"
        for (tapLocation, tapName) in tapCandidates {
            if let tap = CGEvent.tapCreate(
                tap: tapLocation,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            ) {
                createdTap = tap
                createdTapName = tapName
                DebugLog.write("Function key monitor created \(tapName)")
                break
            } else {
                DebugLog.write("Function key monitor failed to create \(tapName)")
            }
        }

        guard let tap = createdTap else {
            DebugLog.write("Function key monitor failed for all tap locations")
            return false
        }

        eventTap = tap
        activeTapName = createdTapName
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        DebugLog.write("Function key monitor enabled with \(createdTapName)")
        return true
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        runLoopSource = nil
        eventTap = nil
        isFunctionKeyPressed = false
        isRunning = false
        activeTapName = "none"
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == 63 else {
            return Unmanaged.passUnretained(event)
        }

        let isPressed = event.flags.contains(.maskSecondaryFn)
        if isPressed != isFunctionKeyPressed {
            isFunctionKeyPressed = isPressed
            DispatchQueue.main.async { [weak self] in
                self?.onFunctionKeyChange?(isPressed)
            }
        }

        return nil
    }
}
