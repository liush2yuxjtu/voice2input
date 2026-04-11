import AppKit
import ApplicationServices
import Carbon
import Foundation

enum TextInjectionError: LocalizedError {
    case accessibilityDenied
    case cannotPreparePasteboard
    case failedToSwitchInputSource

    var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            return "文本注入需要辅助功能权限。"
        case .cannotPreparePasteboard:
            return "无法写入系统剪贴板。"
        case .failedToSwitchInputSource:
            return "无法切换到 ASCII 输入源。"
        }
    }
}

@MainActor
final class TextInjector {
    private let inputSourceManager = InputSourceManager()
    private let permissionCenter = PermissionCenter()

    func inject(text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard AXIsProcessTrusted() else {
            throw TextInjectionError.accessibilityDenied
        }
        try permissionCenter.ensurePostEventAccess()

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        let originalSource = inputSourceManager.currentSource()
        let needsASCIISource = originalSource?.isCJK ?? false

        if needsASCIISource {
            guard let asciiSource = inputSourceManager.preferredASCIISource() else {
                throw TextInjectionError.failedToSwitchInputSource
            }

            let status = TISSelectInputSource(asciiSource)
            guard status == noErr else {
                throw TextInjectionError.failedToSwitchInputSource
            }
            try? await Task.sleep(for: .milliseconds(120))
        }

        pasteboard.clearContents()
        guard pasteboard.setString(trimmed, forType: .string) else {
            snapshot.restore(to: pasteboard)
            throw TextInjectionError.cannotPreparePasteboard
        }

        try? await Task.sleep(for: .milliseconds(50))
        postCommandV()
        try? await Task.sleep(for: .milliseconds(140))

        if needsASCIISource, let originalSource {
            _ = TISSelectInputSource(originalSource.source)
            try? await Task.sleep(for: .milliseconds(80))
        }

        snapshot.restore(to: pasteboard)
    }

    private func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

private struct InputSourceSnapshot {
    let source: TISInputSource
    let identifier: String
    let languages: [String]

    var isCJK: Bool {
        let cjkPrefixes = ["zh", "ja", "ko"]
        if languages.contains(where: { code in cjkPrefixes.contains(where: { code.lowercased().hasPrefix($0) }) }) {
            return true
        }
        return identifier.contains("inputmethod") && languages.isEmpty == false
    }
}

private final class InputSourceManager {
    func currentSource() -> InputSourceSnapshot? {
        guard let sourceRef = TISCopyCurrentKeyboardInputSource() else {
            return nil
        }

        let source = sourceRef.takeRetainedValue()
        return snapshot(for: source)
    }

    func preferredASCIISource() -> TISInputSource? {
        if let source = findPreferredABCSource() {
            return source
        }

        return TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue()
    }

    private func findPreferredABCSource() -> TISInputSource? {
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsASCIICapable as String: kCFBooleanTrue as Any,
            kTISPropertyInputSourceIsSelectCapable as String: kCFBooleanTrue as Any
        ] as CFDictionary

        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as NSArray? else {
            return nil
        }

        let preferredIDs = ["com.apple.keylayout.ABC", "com.apple.keylayout.US"]
        for case let source as TISInputSource in list {
            let sourceID = stringProperty(for: source, key: kTISPropertyInputSourceID) ?? ""
            if preferredIDs.contains(sourceID) {
                return source
            }
        }

        return nil
    }

    private func snapshot(for source: TISInputSource) -> InputSourceSnapshot {
        InputSourceSnapshot(
            source: source,
            identifier: stringProperty(for: source, key: kTISPropertyInputSourceID) ?? "",
            languages: arrayProperty(for: source, key: kTISPropertyInputSourceLanguages)
        )
    }

    private func stringProperty(for source: TISInputSource, key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private func arrayProperty(for source: TISInputSource, key: CFString) -> [String] {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return []
        }

        let value = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as NSArray
        return value.compactMap { $0 as? String }
    }
}

private struct PasteboardSnapshot {
    private struct Item {
        let values: [NSPasteboard.PasteboardType: Data]
    }

    private let items: [Item]

    init(pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    values[type] = data
                }
            }
            return Item(values: values)
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        let restoredItems = items.map { item -> NSPasteboardItem in
            let pasteboardItem = NSPasteboardItem()
            for (type, data) in item.values {
                pasteboardItem.setData(data, forType: type)
            }
            return pasteboardItem
        }

        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}
