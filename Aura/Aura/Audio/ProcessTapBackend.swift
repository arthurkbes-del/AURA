// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import CoreAudio
import Foundation

public struct SystemOutputDevice: Identifiable, Hashable, Sendable {
    public var id: String { uid }
    public let objectID: AudioObjectID
    public let uid: String
    public let name: String
}

public struct SystemAudioApplication: Identifiable, Hashable, Sendable {
    public var id: AudioObjectID { objectID }
    public let objectID: AudioObjectID
    public let pid: Int32
    public let bundleID: String
    public let name: String
    public init(objectID: AudioObjectID, pid: Int32, bundleID: String, name: String) {
        self.objectID = objectID; self.pid = pid; self.bundleID = bundleID; self.name = name
    }
    public var belongsToAura: Bool { bundleID == "com.evoluere.aura" || bundleID.hasPrefix("com.evoluere.aura.") }
}

struct SystemAudioCapturePolicy {
    let processes: [AudioObjectID]
    let exclusive: Bool
    func matchesCurrent(selection: SystemAudioSelection, ownPID: Int32, applications: [SystemAudioApplication]) -> Bool {
        guard let current = try? Self.make(selection: selection, ownPID: ownPID, applications: applications) else { return false }
        return exclusive == current.exclusive && Set(processes) == Set(current.processes)
    }
    static func make(selection: SystemAudioSelection, ownPID: Int32, applications: [SystemAudioApplication]) throws -> Self {
        guard applications.contains(where: { $0.pid == ownPID }) else {
            throw SystemAudioError("AURA's audio process could not be resolved. Capture was not started to prevent feedback.")
        }
        if let pid = selection.applicationPID {
            guard let application = applications.first(where: { $0.pid == pid }), pid != ownPID,
                  !application.belongsToAura,
                  selection.applicationBundleID == nil || selection.applicationBundleID == application.bundleID else {
                throw SystemAudioError("The selected audio process exited, changed identity or belongs to AURA. Refresh the source list.")
            }
            return Self(processes: [application.objectID], exclusive: false)
        }
        guard selection.applicationBundleID == nil else {
            throw SystemAudioError("The saved application is not running. Refresh and select it, or explicitly choose All applications.")
        }
        return Self(processes: applications.filter { $0.pid == ownPID || $0.belongsToAura }.map(\.objectID), exclusive: true)
    }
}

enum HALAccess {
    static func check(_ status: OSStatus, _ action: String) throws {
        guard status == noErr else { throw SystemAudioError("\(action) failed (Core Audio \(status)). Check audio capture permission and device availability, then retry.") }
    }
    static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, initial: T) throws -> T {
        var address = address(selector, scope), value = initial, size = UInt32(MemoryLayout<T>.size)
        try check(withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }, "Read audio property")
        return value
    }
    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        try value(object, selector, initial: Optional<CFString>.none).map { $0 as String } ?? ""
    }
    static func objects(_ selector: AudioObjectPropertySelector) throws -> [AudioObjectID] {
        var address = address(selector), size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size), "Read audio inventory size")
        guard size > 0, size % 4 == 0, size < 1_048_576 else { return [] }
        var result = [AudioObjectID](repeating: 0, count: Int(size) / 4)
        try check(result.withUnsafeMutableBytes { AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, $0.baseAddress!) }, "Read audio inventory")
        return Array(result.prefix(Int(size) / 4))
    }
    static func channels(_ object: AudioObjectID, scope: AudioObjectPropertyScope) throws -> Int {
        var address = address(kAudioDevicePropertyStreamConfiguration, scope), size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size), "Read stream configuration size")
        guard size >= MemoryLayout<AudioBufferList>.size, size < 1_048_576 else { return 0 }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, storage), "Read stream channels")
        return UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

@MainActor public enum SystemAudioInventory {
    public static let defaultOutputUID = "aura.system-default"
    public static func defaultOutputID() throws -> AudioObjectID {
        try HALAccess.value(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID(0))
    }
    public static func outputs() throws -> [SystemOutputDevice] {
        try HALAccess.objects(kAudioHardwarePropertyDevices).compactMap { device in
            guard (try? HALAccess.channels(device, scope: kAudioObjectPropertyScopeOutput)) ?? 0 > 0,
                  let uid = try? HALAccess.string(device, kAudioDevicePropertyDeviceUID),
                  !uid.hasPrefix("com.evoluere.aura.session.") else { return nil }
            return SystemOutputDevice(objectID: device, uid: uid, name: (try? HALAccess.string(device, kAudioObjectPropertyName)) ?? "Output \(device)")
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public static func applications() throws -> [SystemAudioApplication] {
        try HALAccess.objects(kAudioHardwarePropertyProcessObjectList).compactMap { object in
            guard let pid = try? HALAccess.value(object, kAudioProcessPropertyPID, initial: Int32(0)), pid > 0 else { return nil }
            let bundle = (try? HALAccess.string(object, kAudioProcessPropertyBundleID)) ?? ""
            let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? (bundle.isEmpty ? "Audio process \(pid)" : bundle)
            return SystemAudioApplication(objectID: object, pid: pid, bundleID: bundle, name: name)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Owns only private resources created by this instance. Physical output device
/// properties, default routing and volume are never changed.
@MainActor public final class ProcessTapBackend: SystemAudioBackend {
    public private(set) var sampleRate = 48_000.0
    public private(set) var outputName = "No output"
    public var metrics: SystemAudioMetrics { latestMetrics }
    private var latestMetrics = SystemAudioMetrics()
    private var health = CaptureHealthPolicy(now: 0)
    private var overloadMonitoring = false
    private var selection: SystemAudioSelection?
    private var device: AudioObjectID = 0
    private var deviceUID = ""
    private var registration: AudioDeviceIOProcID?
    private var tap: AudioObjectID = 0
    private var tapUID = ""
    private var tapDescription: CATapDescription?
    private var aggregate: AudioObjectID = 0
    private let aggregateUID = "com.evoluere.aura.session.\(UUID().uuidString)"
    private var io: AudioDeviceIOProcID?
    private var startAttempted = false
    private var bridge: SystemAudioRenderBridge?
    private var policy: SystemAudioCapturePolicy?
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, DispatchQueue?, AudioObjectPropertyListenerBlock)] = []
    private var sleepObserver: NSObjectProtocol?

    public init() {}
    nonisolated private static func silentBlock() -> AudioDeviceIOBlock {
        { @Sendable _, _, _, output, _ in
            for buffer in UnsafeMutableAudioBufferListPointer(output) {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
        }
    }
    nonisolated private static func renderBlock(_ bridge: SystemAudioRenderBridge) -> AudioDeviceIOBlock {
        { @Sendable _, input, inputTime, output, _ in
            let time = inputTime.pointee
            bridge.render(input: input, output: output, sampleTime: time.mFlags.contains(.sampleTimeValid) ? time.mSampleTime : nil)
        }
    }
    nonisolated private static func overloadBlock(_ bridge: SystemAudioRenderBridge) -> AudioObjectPropertyListenerBlock {
        { @Sendable _, _ in bridge.recordOverload() }
    }

    public func resolve(_ selection: SystemAudioSelection) throws {
        self.selection = selection
        let outputs = try SystemAudioInventory.outputs()
        if selection.deviceUID == SystemAudioInventory.defaultOutputUID { device = try SystemAudioInventory.defaultOutputID() }
        else { device = outputs.first(where: { $0.uid == selection.deviceUID })?.objectID ?? 0 }
        guard let output = outputs.first(where: { $0.objectID == device }) else { throw SystemAudioError("Selected output is unavailable. Refresh and select an output.") }
        deviceUID = output.uid; outputName = output.name
        // Register a silent, never-started client so AURA has an unambiguous HAL
        // process object before an exclusive tap is created. No audio is emitted.
        try HALAccess.check(AudioDeviceCreateIOProcIDWithBlock(&registration, device, nil, Self.silentBlock()), "Register AURA audio identity")
        policy = try SystemAudioCapturePolicy.make(selection: selection, ownPID: getpid(), applications: SystemAudioInventory.applications())
    }

    public func createTap() throws {
        guard let policy else { throw SystemAudioError("Audio identity was not prepared.") }
        let description = policy.exclusive
            ? CATapDescription(excludingProcesses: policy.processes, deviceUID: deviceUID, stream: 0)
            : CATapDescription(processes: policy.processes, deviceUID: deviceUID, stream: 0)
        description.isPrivate = true; description.name = "AURA output processing"
        // Probe capture without muting the ordinary path. Output remains gated
        // until real nonzero PCM is verified by the control-side health policy.
        description.muteBehavior = .unmuted
        tapDescription = description
        try HALAccess.check(AudioHardwareCreateProcessTap(description, &tap), "Create process tap")
        tapUID = try HALAccess.string(tap, kAudioTapPropertyUID)
    }

    public func createAggregate() throws {
        guard tap != 0, !tapUID.isEmpty else { throw SystemAudioError("Capture tap is not ready.") }
        let composition: [String: Any] = [kAudioAggregateDeviceNameKey: "AURA Processing (private)",
            kAudioAggregateDeviceUIDKey: aggregateUID, kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: deviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: deviceUID, kAudioSubDeviceInputChannelsKey: 0]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]]]
        try HALAccess.check(AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregate), "Create private audio device")
    }

    public func prepareIO(_ configuration: AudioConfiguration) throws {
        guard try HALAccess.channels(aggregate, scope: kAudioObjectPropertyScopeInput) == 2,
              try HALAccess.channels(aggregate, scope: kAudioObjectPropertyScopeOutput) == 2 else {
            throw SystemAudioError("This output does not provide a supported stereo path. No microphone input is used.")
        }
        let input = try HALAccess.value(aggregate, kAudioDevicePropertyStreamFormat, scope: kAudioObjectPropertyScopeInput, initial: AudioStreamBasicDescription())
        let output = try HALAccess.value(aggregate, kAudioDevicePropertyStreamFormat, scope: kAudioObjectPropertyScopeOutput, initial: AudioStreamBasicDescription())
        for format in [input, output] {
            guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0, format.mBitsPerChannel == 32,
                  format.mChannelsPerFrame == 2 else { throw SystemAudioError("This output's PCM format is not supported yet.") }
        }
        guard input.mSampleRate == output.mSampleRate else { throw SystemAudioError("Capture and output rates differ; this path needs unvalidated conversion and was not started.") }
        sampleRate = input.mSampleRate
        let bridge = try SystemAudioRenderBridge(sampleRate: sampleRate, maximumFrames: 65_536, configuration: configuration, outputEnabled: false)
        self.bridge = bridge
        try HALAccess.check(AudioDeviceCreateIOProcIDWithBlock(&io, aggregate, nil, Self.renderBlock(bridge)), "Prepare processing callback")
    }

    private func listen(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        reason: String, when: (@MainActor () -> Bool)? = nil,
                        changed: @escaping @MainActor (String) -> Void) throws {
        var address = HALAccess.address(selector, scope)
        let block: AudioObjectPropertyListenerBlock = { @Sendable _, _ in
            Task { @MainActor in if when?() ?? true { changed(reason) } }
        }
        try HALAccess.check(AudioObjectAddPropertyListenerBlock(object, &address, .main, block), "Monitor audio changes")
        listeners.append((object, address, .main, block))
    }
    public func addListeners(_ changed: @escaping @MainActor (String) -> Void) throws {
        try listen(device, kAudioDevicePropertyDeviceIsAlive, reason: "Output disconnected. Select an available output and start again.", changed: changed)
        try listen(device, kAudioDevicePropertyNominalSampleRate, reason: "Output sample rate changed. Start again to reconnect safely.", changed: changed)
        try listen(device, kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeOutput, reason: "Output streams changed. Start again to reconnect.", changed: changed)
        if selection?.deviceUID == SystemAudioInventory.defaultOutputUID {
            try listen(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, reason: "System output changed. Start again to use the new output.", changed: changed)
        }
        if let selection, let policy {
            try listen(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList,
                       reason: "Audio process identity changed. Refresh and start again.",
                       when: {
                guard let applications = try? SystemAudioInventory.applications() else { return true }
                return !policy.matchesCurrent(selection: selection, ownPID: getpid(), applications: applications)
            }, changed: changed)
        }
        if let bridge {
            var address = HALAccess.address(kAudioDeviceProcessorOverload)
            if AudioObjectHasProperty(aggregate, &address) {
                let block = Self.overloadBlock(bridge)
                try HALAccess.check(AudioObjectAddPropertyListenerBlock(aggregate, &address, nil, block), "Monitor HAL overload events")
                listeners.append((aggregate, address, nil, block)); overloadMonitoring = true
            }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in changed("Mac is going to sleep. Start processing again after waking.") }
        }
    }
    public func start() throws {
        guard let io else { throw SystemAudioError("Processing callback is not ready.") }
        startAttempted = true
        health = CaptureHealthPolicy(now: ProcessInfo.processInfo.systemUptime)
        try HALAccess.check(AudioDeviceStart(aggregate, io), "Start output processing")
    }
    private func setTapMute(_ behavior: CATapMuteBehavior) throws {
        guard let tapDescription else { throw SystemAudioError("Capture description is unavailable.") }
        tapDescription.muteBehavior = behavior
        var updated: CATapDescription? = tapDescription
        var address = HALAccess.address(kAudioTapPropertyDescription)
        try HALAccess.check(withUnsafePointer(to: &updated) {
            AudioObjectSetPropertyData(tap, &address, 0, nil, UInt32(MemoryLayout<CATapDescription?>.size), $0)
        }, "Update capture mute behavior")
    }
    public func service() throws {
        guard let bridge else { return }
        var snapshot = bridge.metrics
        switch health.evaluate(snapshot, now: ProcessInfo.processInfo.systemUptime) {
        case .activate:
            try setTapMute(.mutedWhenTapped)
            bridge.setOutputEnabled(true)
        case .deactivate:
            bridge.setOutputEnabled(false)
            try setTapMute(.unmuted)
        case .stalled:
            bridge.setOutputEnabled(false)
            try setTapMute(.unmuted)
            throw SystemAudioError("Audio capture callbacks stopped. Ordinary audio was restored; check permission/device and start again.")
        case .none: break
        }
        snapshot.processingOutputActive = health.outputActive
        snapshot.overloadMonitoringAvailable = overloadMonitoring
        latestMetrics = snapshot
    }
    public func apply(_ configuration: AudioConfiguration) -> Bool { bridge?.apply(configuration) ?? false }
    public func stop() throws {
        guard let io, startAttempted else { return }
        bridge?.setOutputEnabled(false)
        try HALAccess.check(AudioDeviceStop(aggregate, io), "Stop output processing")
        startAttempted = false
    }
    public func removeListeners() {
        for (object, var address, queue, block) in listeners { _ = AudioObjectRemovePropertyListenerBlock(object, &address, queue, block) }
        listeners.removeAll()
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        sleepObserver = nil
    }
    public func destroyIO() throws {
        guard let io else { return }
        guard !startAttempted else { throw SystemAudioError("Processing has not stopped; callback resources retained for retry.") }
        try HALAccess.check(AudioDeviceDestroyIOProcID(aggregate, io), "Release processing callback")
        self.io = nil; bridge = nil
    }
    public func destroyAggregate() throws {
        guard aggregate != 0 else { return }
        guard io == nil else { throw SystemAudioError("Callback is still owned; aggregate retained.") }
        guard try HALAccess.string(aggregate, kAudioDevicePropertyDeviceUID) == aggregateUID else {
            throw SystemAudioError("Audio device identity changed; refusing to destroy an unowned device.")
        }
        try HALAccess.check(AudioHardwareDestroyAggregateDevice(aggregate), "Release private audio device")
        aggregate = 0
    }
    public func destroyTap() throws {
        guard tap != 0 else { return }
        guard aggregate == 0 else { throw SystemAudioError("Aggregate still owns the tap; retained for retry.") }
        // Creation may succeed before reading its UID fails. That handle is still
        // ours; a known UID, when present, must match before destroying it.
        if !tapUID.isEmpty, try HALAccess.string(tap, kAudioTapPropertyUID) != tapUID {
            throw SystemAudioError("Tap identity changed; refusing to destroy an unowned tap.")
        }
        try HALAccess.check(AudioHardwareDestroyProcessTap(tap), "Release process tap")
        tap = 0; tapUID = ""; tapDescription = nil
    }
    public func releaseRegistration() throws {
        guard let registration else { return }
        guard io == nil, aggregate == 0, tap == 0 else { throw SystemAudioError("Session cleanup incomplete; audio identity retained.") }
        let present = try HALAccess.objects(kAudioHardwarePropertyDevices).contains(device)
        let observedUID = present ? try HALAccess.string(device, kAudioDevicePropertyDeviceUID) : nil
        try HALResourceRelease.releaseNeverStartedRegistration(expectedUID: deviceUID, observedUID: observedUID) {
            try HALAccess.check(AudioDeviceDestroyIOProcID(device, registration), "Release AURA audio identity")
        }
        self.registration = nil
    }
}
