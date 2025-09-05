import Foundation
import OSLog
import CoreAudio
import AudioToolbox

final class AudioDeviceMonitor {
    typealias DeviceChangeCallback = (_ defaultInputName: String?) -> Void

    private let logger = Logger(subsystem: "com.livcap.audio", category: "AudioDeviceMonitor")
    private var deviceChangeCallback: DeviceChangeCallback?

    // Debounce to avoid multiple fires per change
    private var pendingNotify: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.1

    init() {
        setupCoreAudioListeners()
        logger.info("AudioDeviceMonitor initialized")
    }

    deinit {
        teardownCoreAudioListeners()
    }

    func onDeviceChanged(_ callback: @escaping DeviceChangeCallback) {
        self.deviceChangeCallback = callback
    }

    // MARK: - Notify helper
    private func emitChange() {
        // Debounce
        pendingNotify?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let name = self.currentDefaultInputName()
            self.logger.info("🔄 Audio input device changed to: \(name ?? "unknown")")
            self.deviceChangeCallback?(name)
        }
        pendingNotify = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    // MARK: - Core Audio (macOS)
    private var propertyAddresses: [AudioObjectPropertyAddress] = []
    private var listenersInstalled = false

    private func setupCoreAudioListeners() {
        // We care about: default input device + device list changes
        let defaultInputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let devicesAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        propertyAddresses = [defaultInputAddr, devicesAddr]

        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)

        for var addr in propertyAddresses {
            let status = AudioObjectAddPropertyListenerBlock(
                systemObjectID,
                &addr,
                DispatchQueue.main,
                { [weak self] _, _ in
                    self?.emitChange()
                }
            )
            if status != noErr {
                logger.error("Failed to add CoreAudio listener: \(status)")
            }
        }
        listenersInstalled = true
    }

    private func teardownCoreAudioListeners() {
        guard listenersInstalled else { return }
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        for var addr in propertyAddresses {
            let status = AudioObjectRemovePropertyListenerBlock(systemObjectID, &addr, DispatchQueue.main, { _, _ in })
            if status != noErr {
                logger.error("Failed to remove CoreAudio listener: \(status)")
            }
        }
        listenersInstalled = false
    }

    private func currentDefaultInputID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(0)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        return (status == noErr && deviceID != 0) ? deviceID : nil
    }

    private func currentDefaultInputName() -> String? {
        guard let dev = currentDefaultInputID() else { return nil }
        var name: CFString = "" as CFString
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(dev, &address, 0, nil, &dataSize, &name)
        if status == noErr { return name as String }
        return nil
    }
}
