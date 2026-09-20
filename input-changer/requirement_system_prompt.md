You are an expert macOS Swift developer. Your task is to write a single-file, production-ready, standalone macOS menu bar application in Swift that dynamically manages and remembers input languages (keyboard layouts) on a per-application basis.

### Environment & Toolchain Requirements
- Operating System: macOS (Apple Silicon / M-Series/ m4 max chip with 36GB ram)
- Target Language: Swift 5+
- Frameworks Allowed: AppKit, Carbon (specifically Text Input Services / TIS), SwiftUI (or NSMenu for UI)
- Build Constraint: The code must compile cleanly using `swiftc` via Command Line Tools (xcode-select), without requiring a full Xcode `.xcodeproj` bundle or external dependencies. and should use as minimal resource as possible while running.

### Core Architecture & Logic Specifications

1. Menu Bar / Extra Status Item UI:
   - Run purely as a Menu Bar app (`LSUIElement = true` / accessory app) without a Dock icon.
   - Provide a toggle in the Menu Bar extra menu to Enable/Disable the automatic switching engine on the fly.
   - Provide a visual status indicator in the menu bar showing whether auto-switching is active, along with the current app name and its associated input source.
   - Include a simple Settings panel or menu items allowing the user to select/change the global "Default Input Source" (e.g., U.S. English) and per app default input source, which will be used for that app. while Default Input Source will be used all other apps.

2. Input Language State Management Engine:
   - Default Behavior: When an app is activated for the first time, switch to the user-selected Global Default Language.
   - Active App Tracking: Listen to system-wide app activation events
   - User Preference Override & Memory:
     - Continuously monitor input source changes (using `NSTextInputContext.keyboardInputSourceDidChangeNotification` or Carbon notifications).
     - When the user manually switches their keyboard layout while inside a specific application (e.g., switching from English to Russian inside Google Chrome), capture this change and persist the app's bundle identifier alongside its newly selected input source ID in memory / `UserDefaults`.
     - Context Switching Logic: When switching back to Google Chrome from another application, restore its most recent user-selected input source (Russian), rather than resetting it to English.
     - Resetting Behavior: If the user manually changes the input source back to English while inside Google Chrome, update the saved preference for Google Chrome to English. Subsequent switches back to Google Chrome will then restore English.

3. Low-Level System APIs:
   - Use Carbon framework's Text Input Services (`TISSelectInputSource`, `TISCopyCurrentKeyboardInputSource`, `TISCreateInputSourceList`) to query available layouts and programmatically switch keyboard layouts.
   - Store mapping configurations persistently using `UserDefaults` keyed by bundle identifiers (`NSRunningApplication.bundleIdentifier`).

### Output Requirements
1. Deliver the full, working source code inside a single `main.swift` file.
2. Ensure proper imports (`AppKit`, `Carbon`).
3. Include explicit CLI compilation instructions using `swiftc` with linked frameworks (`-framework AppKit -framework Carbon`).
4. Provide step-by-step post-build instructions explaining how to grant Accessibility permissions under "System Settings > Privacy & Security > Accessibility" so `TISSelectInputSource` can function.


The details of using Swift requirements may change and can be changed depending on your needs. Because these were also written by another AI, there can be some mistakes like instead of using "TIS select input source," maybe you will need something else. Use that. Don't limit yourself with these app-specific requirements, but limit yourself with the requirements that I gave as a user experience.


It is working good. It can change the input source and remember the default for specific apps and can change that default if I change the app name app input source when I'm using the app. It's okay, but running the terminal command, I stopped the terminal command, but the app didn't stop. It disappeared from the toolbar but didn't start. It's still changing, and I can still see it from the terminal running apps. Can you fix it?
input-changer (master) ./InputChanger
^C
input-changer (master) htop | grep InputChanger

input-changer (master) ps aux | grep -i inputchanger
bkmobil           7024   0.0  0.0 410733664   1664 s000  S+    3:12AM   0:00.00 grep -i inputchanger