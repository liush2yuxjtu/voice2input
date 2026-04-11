import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let permissions = PermissionCenter()
    private let refinementService = LLMRefinementService()
    private let functionKeyMonitor = GlobalFunctionKeyMonitor()
    private let speechService = SpeechRecognitionService()
    private let overlayController = FloatingOverlayController()
    private let textInjector = TextInjector()
    private var hasShownMonitorFailureAlert = false

    private lazy var coordinator = VoiceInputCoordinator(
        settings: settings,
        permissions: permissions,
        speechService: speechService,
        overlayController: overlayController,
        textInjector: textInjector,
        refinementService: refinementService
    )

    private var statusItem: NSStatusItem?
    private var llmSettingsWindowController: LLMSettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.write("Application did finish launching")
        setupStatusItem()
        setupFunctionKeyMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        functionKeyMonitor.stop()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "waveform.and.mic", accessibilityDescription: "Voice2Input")
        item.button?.image?.isTemplate = true
        item.menu = makeMenu()
        statusItem = item
    }

    private func setupFunctionKeyMonitor() {
        DebugLog.write("Preflight listen access = \(permissions.hasInputMonitoringAccess())")
        do {
            try permissions.ensureInputMonitoringAccess()
        } catch {
            DebugLog.write("Input monitoring setup failed: \(error.localizedDescription)")
            showFnMonitorFailureAlertIfNeeded(message: error.localizedDescription)
            refreshMenu()
            return
        }

        functionKeyMonitor.onFunctionKeyChange = { [weak self] isPressed in
            self?.coordinator.handleFunctionKeyChange(isPressed)
        }

        if !functionKeyMonitor.start() {
            DebugLog.write("Function key monitor start() returned false")
            permissions.promptForAccessibility()
            showFnMonitorFailureAlertIfNeeded(message: "应用未能建立全局键盘监听。请确认“输入监控”和“辅助功能”都已允许。")
        } else {
            DebugLog.write("Function key monitor active tap = \(functionKeyMonitor.activeTapName)")
        }

        refreshMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let statusTitle = functionKeyMonitor.isRunning
            ? "Fn Monitor: Active (\(functionKeyMonitor.activeTapName))"
            : "Fn Monitor: Permission Required"
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(.separator())

        let languageItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()
        for option in LanguageOption.allCases {
            let item = NSMenuItem(title: option.menuTitle, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = option == settings.selectedLanguage ? .on : .off
            languageMenu.addItem(item)
        }
        menu.setSubmenu(languageMenu, for: languageItem)
        menu.addItem(languageItem)

        let llmItem = NSMenuItem(title: "LLM Refinement", action: nil, keyEquivalent: "")
        let llmMenu = NSMenu()

        let enableItem = NSMenuItem(title: "Enabled", action: #selector(toggleLLMRefinement), keyEquivalent: "")
        enableItem.target = self
        enableItem.state = settings.llmEnabled ? .on : .off
        llmMenu.addItem(enableItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openLLMSettings), keyEquivalent: "")
        settingsItem.target = self
        llmMenu.addItem(settingsItem)

        menu.setSubmenu(llmMenu, for: llmItem)
        menu.addItem(llmItem)

        menu.addItem(.separator())

        let permissionsItem = NSMenuItem(title: "Open Privacy Settings", action: #selector(openPrivacySettings), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        let retryMonitorItem = NSMenuItem(title: "Retry Fn Monitor", action: #selector(retryFunctionKeyMonitor), keyEquivalent: "")
        retryMonitorItem.target = self
        menu.addItem(retryMonitorItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Voice2Input", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func refreshMenu() {
        statusItem?.menu = makeMenu()
    }

    @objc
    private func selectLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = LanguageOption(rawValue: rawValue) else {
            return
        }

        settings.selectedLanguage = language
        refreshMenu()
    }

    @objc
    private func toggleLLMRefinement() {
        settings.llmEnabled.toggle()
        refreshMenu()
    }

    @objc
    private func openLLMSettings() {
        if llmSettingsWindowController == nil {
            llmSettingsWindowController = LLMSettingsWindowController(
                settings: settings,
                refinementService: refinementService
            )
        }

        llmSettingsWindowController?.show()
    }

    @objc
    private func openPrivacySettings() {
        permissions.promptForAccessibility()
        permissions.openPrivacySettings()
    }

    @objc
    private func retryFunctionKeyMonitor() {
        functionKeyMonitor.stop()
        hasShownMonitorFailureAlert = false
        setupFunctionKeyMonitor()
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }

    private func showFnMonitorFailureAlertIfNeeded(message: String) {
        guard !hasShownMonitorFailureAlert else { return }
        hasShownMonitorFailureAlert = true

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Fn 热键未激活"
        alert.informativeText = """
        \(message)

        请在 System Settings > Privacy & Security 中确认对 Voice2Input 开启：
        1. Input Monitoring
        2. Accessibility

        打开后重新点击 “Retry Fn Monitor”，或直接重启应用。
        """
        alert.addButton(withTitle: "Open Privacy Settings")
        alert.addButton(withTitle: "Retry Fn Monitor")
        alert.addButton(withTitle: "OK")

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openPrivacySettings()
        case .alertSecondButtonReturn:
            retryFunctionKeyMonitor()
        default:
            break
        }
    }
}
