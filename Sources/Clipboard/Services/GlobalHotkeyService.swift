import Carbon
import Foundation

@MainActor
protocol GlobalHotkeyServing: AnyObject {
    var onHotKeyPressed: (() -> Void)? { get set }

    func register(shortcut: HotkeyShortcut)
}

@MainActor
final class GlobalHotkeyService: GlobalHotkeyServing {
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private var registeredShortcut: HotkeyShortcut?

    var onHotKeyPressed: (() -> Void)?

    func register(shortcut: HotkeyShortcut) {
        guard shortcut.isValid else { return }
        guard registeredShortcut != shortcut || hotKeyReference == nil else { return }

        installEventHandlerIfNeeded()
        unregisterHotKey()

        let hotKeyID = EventHotKeyID(signature: AppConstants.hotKeySignature, id: AppConstants.hotKeyIdentifier)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )

        registeredShortcut = status == noErr ? shortcut : nil
    }

    private func unregisterHotKey() {
        guard let hotKeyReference else { return }

        UnregisterEventHotKey(hotKeyReference)
        self.hotKeyReference = nil
        registeredShortcut = nil
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerReference == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, event, userData in
            guard
                let event,
                let userData
            else {
                return noErr
            }

            let service = Unmanaged<GlobalHotkeyService>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()

            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            guard hotKeyID.signature == AppConstants.hotKeySignature, hotKeyID.id == AppConstants.hotKeyIdentifier else {
                return noErr
            }

            Task { @MainActor in
                service.onHotKeyPressed?()
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerReference
        )
    }
}
