import AppKit
import Carbon
import ServiceManagement

private struct InputSourceDescriptor {
    let id: String
    let name: String
    let source: TISInputSource
}

private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum PreferenceKey {
        static let engineEnabled = "engineEnabled"
        static let globalDefaultSourceID = "globalDefaultSourceID"
        static let applicationSourceIDs = "applicationSourceIDs"
    }

    private let defaults = UserDefaults(suiteName: "com.inputchanger.MenuBar") ?? .standard
    private let workspace = NSWorkspace.shared
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusMenu = NSMenu()

    private var inputSources: [InputSourceDescriptor] = []
    private var engineEnabled = true
    private var globalDefaultSourceID = ""
    private var applicationSourceIDs: [String: String] = [:]
    private var activeBundleIdentifier: String?
    private var activeApplicationName = "No Active App"
    private var expectedProgrammaticSourceID: String?
    private var expectedProgrammaticSourceDeadline = Date.distantPast
    private var lastError: String?
    private var launchAtLoginError: String?
    private var engineObserversInstalled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        loadPreferences()
        reloadInputSources()
        normalizeGlobalDefault()
        registerLaunchAtLoginIfNeeded()

        statusMenu.autoenablesItems = false
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        statusItem.button?.font = NSFont.menuBarFont(ofSize: 0)

        if engineEnabled {
            startEngineObservers()
        }

        if let frontmostApplication = workspace.frontmostApplication {
            trackApplication(frontmostApplication)
        } else {
            updateStatusItem()
        }
        rebuildMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if !engineEnabled, let frontmostApplication = workspace.frontmostApplication {
            updateActiveApplication(frontmostApplication)
        }
        reloadInputSources()
        normalizeGlobalDefault()
        updateStatusItem()
        rebuildMenu()
    }

    private func loadPreferences() {
        if defaults.object(forKey: PreferenceKey.engineEnabled) == nil {
            engineEnabled = true
        } else {
            engineEnabled = defaults.bool(forKey: PreferenceKey.engineEnabled)
        }
        globalDefaultSourceID = defaults.string(forKey: PreferenceKey.globalDefaultSourceID) ?? ""
        let storedMappings = defaults.dictionary(forKey: PreferenceKey.applicationSourceIDs) ?? [:]
        applicationSourceIDs = storedMappings.reduce(into: [:]) { result, element in
            if let sourceID = element.value as? String {
                result[element.key] = sourceID
            }
        }
    }

    private func saveApplicationMappings() {
        defaults.set(applicationSourceIDs, forKey: PreferenceKey.applicationSourceIDs)
    }

    private var isRunningFromApplicationBundle: Bool {
        Bundle.main.bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }

    private func registerLaunchAtLoginIfNeeded() {
        guard isRunningFromApplicationBundle, SMAppService.mainApp.status == .notRegistered else { return }
        do {
            try SMAppService.mainApp.register()
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Launch at Login could not be enabled: \(error.localizedDescription)"
        }
    }

    private func startEngineObservers() {
        guard !engineObserversInstalled else { return }
        workspace.notificationCenter.addObserver(self, selector: #selector(applicationActivated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(inputSourceChanged(_:)), name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(enabledInputSourcesChanged(_:)), name: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String), object: nil)
        engineObserversInstalled = true
    }

    private func stopEngineObservers() {
        guard engineObserversInstalled else { return }
        workspace.notificationCenter.removeObserver(self, name: NSWorkspace.didActivateApplicationNotification, object: nil)
        DistributedNotificationCenter.default().removeObserver(self, name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
        DistributedNotificationCenter.default().removeObserver(self, name: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String), object: nil)
        engineObserversInstalled = false
    }

    private func reloadInputSources() {
        let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
        var descriptors: [InputSourceDescriptor] = []

        for case let source as TISInputSource in list {
            guard stringProperty(source, kTISPropertyInputSourceCategory) == (kTISCategoryKeyboardInputSource as String), boolProperty(source, kTISPropertyInputSourceIsEnabled), boolProperty(source, kTISPropertyInputSourceIsSelectCapable), let id = stringProperty(source, kTISPropertyInputSourceID), let name = stringProperty(source, kTISPropertyLocalizedName) else {
                continue
            }
            descriptors.append(InputSourceDescriptor(id: id, name: name, source: source))
        }

        inputSources = descriptors.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
    }

    private func normalizeGlobalDefault() {
        guard source(withID: globalDefaultSourceID) == nil else { return }

        if let current = currentInputSource(), source(withID: current.id) != nil {
            globalDefaultSourceID = current.id
        } else if let firstSource = inputSources.first {
            globalDefaultSourceID = firstSource.id
        } else {
            globalDefaultSourceID = ""
        }
        defaults.set(globalDefaultSourceID, forKey: PreferenceKey.globalDefaultSourceID)
    }

    private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return false }
        let value = Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue()
        return CFBooleanGetValue(value)
    }

    private func currentInputSource() -> InputSourceDescriptor? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let id = stringProperty(source, kTISPropertyInputSourceID) else { return nil }
        let name = stringProperty(source, kTISPropertyLocalizedName) ?? id
        return InputSourceDescriptor(id: id, name: name, source: source)
    }

    private func source(withID id: String) -> InputSourceDescriptor? {
        inputSources.first { $0.id == id }
    }

    private func displayName(forSourceID id: String) -> String {
        source(withID: id)?.name ?? "Unavailable (\(id))"
    }

    @objc private func applicationActivated(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        DispatchQueue.main.async { [weak self] in
            self?.trackApplication(application)
        }
    }

    private func trackApplication(_ application: NSRunningApplication) {
        updateActiveApplication(application)
        guard engineEnabled else { return }

        if let desiredSourceID = desiredSourceIDForActiveApplication() {
            selectInputSource(withID: desiredSourceID)
        }
    }

    private func updateActiveApplication(_ application: NSRunningApplication) {
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }

        activeBundleIdentifier = application.bundleIdentifier
        activeApplicationName = application.localizedName ?? application.bundleIdentifier ?? "Unknown App"
        lastError = nil
        updateStatusItem()
    }

    private func desiredSourceIDForActiveApplication() -> String? {
        if let bundleIdentifier = activeBundleIdentifier, let savedSourceID = applicationSourceIDs[bundleIdentifier], source(withID: savedSourceID) != nil {
            return savedSourceID
        }
        return source(withID: globalDefaultSourceID)?.id
    }

    @objc private func inputSourceChanged(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.handleInputSourceChange()
        }
    }

    private func handleInputSourceChange() {
        guard let currentSource = currentInputSource() else { return }

        if currentSource.id == expectedProgrammaticSourceID, Date() <= expectedProgrammaticSourceDeadline {
            expectedProgrammaticSourceID = nil
            expectedProgrammaticSourceDeadline = .distantPast
            lastError = nil
            updateStatusItem()
            return
        }

        expectedProgrammaticSourceID = nil
        expectedProgrammaticSourceDeadline = .distantPast
        lastError = nil

        if engineEnabled, let bundleIdentifier = activeBundleIdentifier {
            applicationSourceIDs[bundleIdentifier] = currentSource.id
            saveApplicationMappings()
        }
        updateStatusItem()
    }

    @objc private func enabledInputSourcesChanged(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reloadInputSources()
            self.normalizeGlobalDefault()
            if self.engineEnabled, let desiredSourceID = self.desiredSourceIDForActiveApplication() {
                self.selectInputSource(withID: desiredSourceID)
            }
            self.updateStatusItem()
        }
    }

    @discardableResult
    private func selectInputSource(withID id: String) -> Bool {
        guard engineEnabled else { return false }
        guard let inputSource = source(withID: id) else {
            lastError = "The saved input source is not currently enabled: \(id)"
            updateStatusItem()
            return false
        }

        if currentInputSource()?.id == id {
            expectedProgrammaticSourceID = nil
            expectedProgrammaticSourceDeadline = .distantPast
            lastError = nil
            updateStatusItem()
            return true
        }

        expectedProgrammaticSourceID = id
        expectedProgrammaticSourceDeadline = Date().addingTimeInterval(2.0)
        let result = TISSelectInputSource(inputSource.source)

        guard result == noErr else {
            expectedProgrammaticSourceID = nil
            expectedProgrammaticSourceDeadline = .distantPast
            lastError = "Could not select \(inputSource.name) (OSStatus \(result))."
            updateStatusItem()
            return false
        }

        lastError = nil
        updateStatusItem()
        return true
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let indicator = engineEnabled ? "●" : "○"
        let currentSource = currentInputSource()
        let sourceName = currentSource?.name ?? "No Input Source"
        let sourceLabel = currentSource.map(menuBarInputSourceName) ?? sourceName
        button.title = "\(indicator) \(applicationInitials(activeApplicationName)): \(shortened(sourceLabel, limit: 16))"
        button.toolTip = "Automatic switching is \(engineEnabled ? "enabled" : "disabled"). \(activeApplicationName) is using \(sourceName)."
    }

    private func applicationInitials(_ applicationName: String) -> String {
        let words = applicationName.split { !$0.isLetter && !$0.isNumber }
        let initials = words.compactMap(\.first).map { String($0) }.joined().uppercased()
        return initials.isEmpty ? "?" : initials
    }

    private func menuBarInputSourceName(_ inputSource: InputSourceDescriptor) -> String {
        let identity = "\(inputSource.id) \(inputSource.name)"
        if identity.range(of: "turkish", options: .caseInsensitive) != nil {
            return "TR"
        }
        return inputSource.name
    }

    private func shortened(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(max(1, limit - 1))) + "…"
    }

    private func rebuildMenu() {
        statusMenu.removeAllItems()

        let engineItem = NSMenuItem(title: "Automatic Switching", action: #selector(toggleEngine(_:)), keyEquivalent: "")
        engineItem.target = self
        engineItem.state = engineEnabled ? .on : .off
        engineItem.isEnabled = true
        statusMenu.addItem(engineItem)

        statusMenu.addItem(.separator())
        addInformationItem("App: \(activeApplicationName)")
        addInformationItem("Current Input Source: \(currentInputSource()?.name ?? "Unknown")")

        if let bundleIdentifier = activeBundleIdentifier, let savedSourceID = applicationSourceIDs[bundleIdentifier] {
            addInformationItem("Saved for This App: \(displayName(forSourceID: savedSourceID))")
        } else {
            addInformationItem("Saved for This App: Uses Global Default")
        }

        if let lastError {
            statusMenu.addItem(.separator())
            addInformationItem("Error: \(lastError)")
        }

        if let launchAtLoginError {
            statusMenu.addItem(.separator())
            addInformationItem("Error: \(launchAtLoginError)")
        }

        statusMenu.addItem(.separator())
        addGlobalDefaultMenu()
        addCurrentApplicationMenu()

        statusMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit InputChanger", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        quitItem.isEnabled = true
        statusMenu.addItem(quitItem)
    }

    private func addInformationItem(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        statusMenu.addItem(item)
    }

    private func addGlobalDefaultMenu() {
        let rootItem = NSMenuItem(title: "Global Default Input Source", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        if inputSources.isEmpty {
            let emptyItem = NSMenuItem(title: "No Selectable Input Sources", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        } else {
            for inputSource in inputSources {
                let item = NSMenuItem(title: inputSource.name, action: #selector(setGlobalDefault(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = inputSource.id
                item.state = inputSource.id == globalDefaultSourceID ? .on : .off
                item.isEnabled = true
                submenu.addItem(item)
            }
        }

        rootItem.submenu = submenu
        rootItem.isEnabled = true
        statusMenu.addItem(rootItem)
    }

    private func addCurrentApplicationMenu() {
        let rootItem = NSMenuItem(title: "Input Source for \(activeApplicationName)", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        guard let bundleIdentifier = activeBundleIdentifier else {
            let unavailableItem = NSMenuItem(title: "This app has no bundle identifier", action: nil, keyEquivalent: "")
            unavailableItem.isEnabled = false
            submenu.addItem(unavailableItem)
            rootItem.submenu = submenu
            rootItem.isEnabled = true
            statusMenu.addItem(rootItem)
            return
        }

        let useGlobalItem = NSMenuItem(title: "Use Global Default", action: #selector(useGlobalDefaultForCurrentApplication(_:)), keyEquivalent: "")
        useGlobalItem.target = self
        useGlobalItem.state = applicationSourceIDs[bundleIdentifier] == nil ? .on : .off
        useGlobalItem.isEnabled = true
        submenu.addItem(useGlobalItem)
        submenu.addItem(.separator())

        for inputSource in inputSources {
            let item = NSMenuItem(title: inputSource.name, action: #selector(setCurrentApplicationSource(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = inputSource.id
            item.state = applicationSourceIDs[bundleIdentifier] == inputSource.id ? .on : .off
            item.isEnabled = true
            submenu.addItem(item)
        }

        rootItem.submenu = submenu
        rootItem.isEnabled = true
        statusMenu.addItem(rootItem)
    }

    @objc private func toggleEngine(_ sender: NSMenuItem) {
        engineEnabled.toggle()
        defaults.set(engineEnabled, forKey: PreferenceKey.engineEnabled)
        expectedProgrammaticSourceID = nil
        expectedProgrammaticSourceDeadline = .distantPast
        lastError = nil

        if engineEnabled {
            startEngineObservers()
            if let frontmostApplication = workspace.frontmostApplication, frontmostApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                trackApplication(frontmostApplication)
            } else if let desiredSourceID = desiredSourceIDForActiveApplication() {
                selectInputSource(withID: desiredSourceID)
            }
        } else {
            stopEngineObservers()
        }
        updateStatusItem()
        rebuildMenu()
    }

    @objc private func setGlobalDefault(_ sender: NSMenuItem) {
        guard let sourceID = sender.representedObject as? String, source(withID: sourceID) != nil else { return }
        globalDefaultSourceID = sourceID
        defaults.set(sourceID, forKey: PreferenceKey.globalDefaultSourceID)
        lastError = nil

        if engineEnabled, let bundleIdentifier = activeBundleIdentifier, applicationSourceIDs[bundleIdentifier] == nil {
            selectInputSource(withID: sourceID)
        } else if engineEnabled, activeBundleIdentifier == nil {
            selectInputSource(withID: sourceID)
        }
        updateStatusItem()
        rebuildMenu()
    }

    @objc private func setCurrentApplicationSource(_ sender: NSMenuItem) {
        guard let bundleIdentifier = activeBundleIdentifier, let sourceID = sender.representedObject as? String, source(withID: sourceID) != nil else { return }
        applicationSourceIDs[bundleIdentifier] = sourceID
        saveApplicationMappings()
        lastError = nil

        if engineEnabled {
            selectInputSource(withID: sourceID)
        }
        updateStatusItem()
        rebuildMenu()
    }

    @objc private func useGlobalDefaultForCurrentApplication(_ sender: NSMenuItem) {
        guard let bundleIdentifier = activeBundleIdentifier else { return }
        applicationSourceIDs.removeValue(forKey: bundleIdentifier)
        saveApplicationMappings()
        lastError = nil

        if engineEnabled, !globalDefaultSourceID.isEmpty {
            selectInputSource(withID: globalDefaultSourceID)
        }
        updateStatusItem()
        rebuildMenu()
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}

private let application = NSApplication.shared
private let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()
