import Foundation
import CoreAudio
import AudioToolbox
import AppKit

// MARK: - CLI Args

struct CLIOptions {
    var runAsDaemon: Bool = false
    var bypassExplicit: Bool? = nil // on/off/toggle handled separately
    var toggleBypass: Bool = false
    var forceDefault: String? = nil // "bgm" | "su1" | device name contains
    var diagnose: Bool = false
}

func parseArguments() -> CLIOptions {
    var opts = CLIOptions()
    var args = CommandLine.arguments.dropFirst()
    while let arg = args.first {
        args = args.dropFirst()
        switch arg {
        case "--daemon":
            opts.runAsDaemon = true
        case "--bypass":
            guard let next = args.first else { break }
            args = args.dropFirst()
            if next == "on" { opts.bypassExplicit = true }
            else if next == "off" { opts.bypassExplicit = false }
            else if next == "toggle" { opts.toggleBypass = true }
        case "--set-default":
            if let next = args.first { opts.forceDefault = next; args = args.dropFirst() }
        case "--diagnose":
            opts.diagnose = true
        default:
            break
        }
    }
    return opts
}

// MARK: - CoreAudio helpers

enum AudioError: Error { case osstatus(OSStatus) }

func getDefaultOutputDeviceID() throws -> AudioDeviceID {
    var deviceID = AudioDeviceID(0)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID)
    if status != noErr { throw AudioError.osstatus(status) }
    return deviceID
}

func getDefaultSystemOutputDeviceID() throws -> AudioDeviceID {
    var deviceID = AudioDeviceID(0)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID)
    if status != noErr { throw AudioError.osstatus(status) }
    return deviceID
}

func setDefaultOutputDeviceID(_ deviceID: AudioDeviceID) throws {
    var deviceIDVar = deviceID
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &deviceIDVar)
    if status != noErr { throw AudioError.osstatus(status) }
}

func setDefaultSystemOutputDeviceID(_ deviceID: AudioDeviceID) throws {
    var deviceIDVar = deviceID
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &deviceIDVar)
    if status != noErr { throw AudioError.osstatus(status) }
}

func copyDeviceName(_ deviceID: AudioDeviceID) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr else { return nil }
    var cfStr = Unmanaged<CFString>?.none
    let status = withUnsafeMutablePointer(to: &cfStr) { ptr -> OSStatus in
        var tmp: CFString? = nil
        let st = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &tmp)
        if let tmp = tmp { ptr.pointee = Unmanaged.passRetained(tmp) }
        return st
    }
    guard status == noErr, let cf = cfStr?.takeRetainedValue() else { return nil }
    return cf as String
}

func allOutputDevices() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else { return [] }
    let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.stride
    var ids = Array(repeating: AudioDeviceID(0), count: count)
    let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids)
    if status != noErr { return [] }
    return ids
}

func findDeviceID(byNameContains needle: String) -> AudioDeviceID? {
    for id in allOutputDevices() {
        if let name = copyDeviceName(id), name.localizedCaseInsensitiveContains(needle) {
            return id
        }
    }
    return nil
}

func deviceSupportsMainVolume(_ deviceID: AudioDeviceID) -> Bool {
    // Check for VirtualMainVolume
    var addrVirt = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    if AudioObjectHasProperty(deviceID, &addrVirt) {
        return true
    }
    // Fallback: traditional scalar volume property on output scope
    var addrVol = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    return AudioObjectHasProperty(deviceID, &addrVol)
}

func diagnoseDevices() {
    let defaultOut = try? getDefaultOutputDeviceID()
    let defaultSys = try? getDefaultSystemOutputDeviceID()
    print("=== Devices (output) ===")
    for id in allOutputDevices() {
        let name = copyDeviceName(id) ?? "<unknown>"
        let supports = deviceSupportsMainVolume(id)
        let markOut = (defaultOut == id) ? " [DefaultOutput]" : ""
        let markSys = (defaultSys == id) ? " [DefaultSystem]" : ""
        print("- \(name) :: supportsMainVolume=\(supports)\(markOut)\(markSys)")
    }
}

// MARK: - Bypass state storage

struct BypassStore {
    static let defaults = UserDefaults(suiteName: "com.deagle.su1volumebridge")!
    static let key = "bypass"
    static func set(_ v: Bool) { defaults.set(v, forKey: key) }
    static func get() -> Bool { defaults.object(forKey: key) as? Bool ?? false }
}

// MARK: - Background Music integration (minimal)

func ensureBackgroundMusicRunning() {
    let workspace = NSWorkspace.shared
    let bundleID = "com.bearisdriving.BGM.App"
    if !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty { return }
    let appURL = URL(fileURLWithPath: "/Applications/Background Music.app")
    let config = NSWorkspace.OpenConfiguration()
    config.activates = false
    config.hides = true
    workspace.openApplication(at: appURL, configuration: config) { _, _ in }
}

func ensureDefaultOutputIsBackgroundMusic() {
    guard let bgmDevice = findDeviceID(byNameContains: "Background Music") else { return }
    do {
        let curOut = try getDefaultOutputDeviceID()
        if curOut != bgmDevice { try setDefaultOutputDeviceID(bgmDevice) }
        // Важно: держим именно "Background Music", а не "Background Music (UI Sounds)" как system output
        let curSys = try getDefaultSystemOutputDeviceID()
        if curSys != bgmDevice { try setDefaultSystemOutputDeviceID(bgmDevice) }
    } catch {
        // noop for now
    }
}

func resolveSU1DeviceID() -> AudioDeviceID? {
    return findDeviceID(byNameContains: "SMSL") ?? findDeviceID(byNameContains: "SU-1") ?? findDeviceID(byNameContains: "USB DAC")
}

func switchDefaultOutputToSU1() {
    guard let su1 = resolveSU1DeviceID() else { return }
    do {
        try setDefaultOutputDeviceID(su1)
        try setDefaultSystemOutputDeviceID(su1)
    } catch { }
}

// Placeholder: внутри BGM выбрать SU-1 как output. Реализуем позже (CLI/XPC в форке BGM).
@discardableResult
func selectOutputDeviceInsideBackgroundMusic(nameContains: String) -> Bool {
    // AppleScript через osascript. Требуется разрешение на Automation (AppleEvents).
    let script = """
    tell application "Background Music"
      set targetDevice to first output device whose name contains "\(nameContains)"
      set selected output device to targetDevice
    end tell
    """
    let process = Process()
    process.launchPath = "/usr/bin/osascript"
    process.arguments = ["-e", script]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

func selectSU1InsideBackgroundMusicIfPossible() {
    let candidates = ["SU-1", "SMSL", "USB DAC"]
    for c in candidates {
        if selectOutputDeviceInsideBackgroundMusic(nameContains: c) { return }
    }
}

// MARK: - Device watcher (simplified)

final class DeviceWatcher {
    private var queue = DispatchQueue(label: "com.deagle.su1volumebridge.audio")
    private var observers: [AudioObjectID: Any] = [:]

    func start() {
        // Подписка на смену дефолтного устройства — чтобы возвращать BGM при необходимости
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let systemObj = AudioObjectID(kAudioObjectSystemObject)
        let callback: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async { onAudioTopologyChanged() }
        }
        AudioObjectAddPropertyListenerBlock(systemObj, &addr, queue, callback)
        observers[systemObj] = callback

        // Подписка на изменения набора устройств (подключение/отключение SU-1)
        var addrDevices = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(systemObj, &addrDevices, queue, callback)

        // Подписка на смену системного устройства
        var addrSys = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(systemObj, &addrSys, queue, callback)
    }
}

// MARK: - Orchestration

func onAudioTopologyChanged() {
    let bypass = BypassStore.get()
    if bypass {
        // Если SU-1 есть — выбрать его. Иначе вернуться на встроенные колонки.
        if let su1 = resolveSU1DeviceID() {
            // Сообщение, если устройство не поддерживает системный volume (ожидаемо для USB DAC)
            if !deviceSupportsMainVolume(su1) {
                // nothing to do; just acknowledge
            }
            switchDefaultOutputToSU1()
        }
        else if let builtIn = findDeviceID(byNameContains: "MacBook") ?? findDeviceID(byNameContains: "Built-in") {
            do { try setDefaultOutputDeviceID(builtIn) } catch { }
        }
        return
    }
    ensureBackgroundMusicRunning()
    ensureDefaultOutputIsBackgroundMusic()
    selectSU1InsideBackgroundMusicIfPossible()
}

func runDaemon() {
    onAudioTopologyChanged()
    let watcher = DeviceWatcher()
    watcher.start()
    RunLoop.current.run()
}

// MARK: - Main

let opts = parseArguments()

if let setBypass = opts.bypassExplicit {
    BypassStore.set(setBypass)
}
if opts.toggleBypass {
    BypassStore.set(!BypassStore.get())
}

if opts.runAsDaemon {
    runDaemon()
} else {
    if opts.diagnose {
        diagnoseDevices()
    } else if let which = opts.forceDefault {
        switch which.lowercased() {
        case "bgm":
            ensureBackgroundMusicRunning(); ensureDefaultOutputIsBackgroundMusic()
        case "su1":
            switchDefaultOutputToSU1()
        default:
            if let dev = findDeviceID(byNameContains: which) {
                do { try setDefaultOutputDeviceID(dev) } catch { }
            } else { onAudioTopologyChanged() }
        }
    } else {
        onAudioTopologyChanged()
    }
}


