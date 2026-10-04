import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox
import HardyFlowObjC

/// Model describing an available audio input device.
public struct AudioInputDevice: Identifiable, Sendable, Hashable {
    public let id: AudioDeviceID
    public let name: String
    public let isBuiltIn: Bool
    public let isBluetooth: Bool
    
    public init(id: AudioDeviceID, name: String, isBuiltIn: Bool, isBluetooth: Bool) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.isBluetooth = isBluetooth
    }
}

/// Manages the low-level microphone audio engine, hardware format negotiation, audio buffer taps, and real-time RMS metering.
public final class AudioEngineManager: @unchecked Sendable {
    public static let shared = AudioEngineManager()
    
    private let audioEngine = AVAudioEngine()
    private let engineQueue = DispatchQueue(label: "com.hardyflow.audioengine", qos: .userInteractive)
    private static let queueKey = DispatchSpecificKey<Void>()
    private var configChangeWorkItem: DispatchWorkItem?
    private var isTapInstalled: Bool = false
    
    public private(set) var isRunning: Bool = false
    public var selectedDeviceID: AudioDeviceID?
    
    /// Whisper Mode: Digital pre-gain boost for quiet whispered speech (Phase 4).
    public var isWhisperModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isWhisperModeEnabled, forKey: "HardyFlow_WhisperModeEnabled")
        }
    }
    public var whisperGainMultiplier: Float = 2.8
    
    /// Handler invoked for each incoming PCM audio buffer.
    public var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    
    /// Handler invoked on the main queue with normalized audio power (0.0 to 1.0) for live waveform visualization.
    public var onAudioLevelChanged: ((Float) -> Void)?
    
    private init() {
        self.isWhisperModeEnabled = UserDefaults.standard.bool(forKey: "HardyFlow_WhisperModeEnabled")
        engineQueue.setSpecific(key: Self.queueKey, value: ())
        setupAudioSessionNotifications()
    }
    
    private func performOnEngineQueue<T>(_ block: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            return try block()
        } else {
            return try engineQueue.sync(execute: block)
        }
    }
    
    /// Enumerates all audio input devices detected on macOS.
    public func getAvailableInputDevices() -> [AudioInputDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        guard status == noErr else { return [] }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs) == noErr else { return [] }
        
        var devices: [AudioInputDevice] = []
        for id in deviceIDs {
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &streamAddress, 0, nil, &streamSize)
            guard streamSize > 0 else { continue }
            
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfName: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            var name = "Unknown Microphone"
            if withUnsafeMutablePointer(to: &cfName, { ptr in
                AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, ptr) == noErr
            }) {
                name = cfName as String
            }
            
            var transportAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var transport: UInt32 = 0
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(id, &transportAddress, 0, nil, &transportSize, &transport)
            
            let isBuiltIn = (transport == kAudioDeviceTransportTypeBuiltIn)
            let isBluetooth = (transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE)
            devices.append(AudioInputDevice(id: id, name: name, isBuiltIn: isBuiltIn, isBluetooth: isBluetooth))
        }
        return devices
    }
    
    private func applyDevice(to inputNode: AVAudioInputNode, deviceID: AudioDeviceID) {
        var devID = deviceID
        if #available(macOS 27.0, *) {
            inputNode.withAudioUnit { audioUnit in
                if let audioUnit = audioUnit {
                    AudioUnitSetProperty(
                        audioUnit,
                        kAudioOutputUnitProperty_CurrentDevice,
                        kAudioUnitScope_Global,
                        0,
                        &devID,
                        UInt32(MemoryLayout<AudioDeviceID>.size)
                    )
                }
            }
        } else {
            if let audioUnit = inputNode.audioUnit {
                AudioUnitSetProperty(
                    audioUnit,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &devID,
                    UInt32(MemoryLayout<AudioDeviceID>.size)
                )
            }
        }
    }
    
    private func setupAudioSessionNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioEngineConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: nil
        )
    }
    
    @objc private func handleAudioEngineConfigurationChange(notification: Notification) {
        configChangeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.performOnEngineQueue {
                // Only attempt recovery if the engine was marked as running but was stopped by system
                guard self.isRunning, !self.audioEngine.isRunning else { return }
                print("🔄 [AudioEngineManager] Audio hardware configuration changed and engine halted; restarting tap...")
                do {
                    self.stopInternal()
                    try self.startInternal()
                } catch {
                    print("⚠️ [AudioEngineManager] Failed to restart audio engine after config change: \(error)")
                }
            }
        }
        configChangeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }
    
    /// Starts capturing audio from the default or selected input device and broadcasting buffers.
    public func start() throws {
        try performOnEngineQueue {
            try startInternal()
        }
    }
    
    /// Stops the audio engine and clears the tap.
    public func stop() {
        performOnEngineQueue {
            stopInternal()
        }
    }
    
    /// Immediately stops the audio engine and purges all temporary audio buffer delegates and closures,
    /// guaranteeing zero audio data remains buffered in memory.
    /// Note: HardyFlow operates purely in-RAM with transient PCM buffers; no audio is ever written to disk.
    public func purgeTemporaryAudioMemory() {
        performOnEngineQueue {
            stopInternal()
            onAudioBuffer = nil
            onAudioLevelChanged = nil
        }
        print("🧹 [AudioEngineManager] Audio memory purged. Zero audio saved to disk or retained in memory.")
    }
    
    private func restartEngine() throws {
        try performOnEngineQueue {
            stopInternal()
            try startInternal()
        }
    }
    
    private func stopInternal() {
        configChangeWorkItem?.cancel()
        guard isRunning else { return }
        
        if isTapInstalled {
            var tapError: NSError?
            HardyFlowTryCatch({
                self.audioEngine.inputNode.removeTap(onBus: 0)
            }, &tapError)
            isTapInstalled = false
            if let tapError = tapError {
                print("⚠️ [AudioEngineManager] Safe tap removal notice: \(tapError.localizedDescription)")
            }
        }
        
        var stopError: NSError?
        HardyFlowTryCatch({
            self.audioEngine.stop()
            self.audioEngine.reset()
        }, &stopError)
        if let stopError = stopError {
            print("⚠️ [AudioEngineManager] Safe engine stop notice: \(stopError.localizedDescription)")
        }
        
        isRunning = false
        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevelChanged?(0.0)
        }
        print("⏹️ [AudioEngineManager] Audio engine stopped.")
    }
    
    private func startInternal() throws {
        if isRunning && audioEngine.isRunning && isTapInstalled {
            return
        }
        
        let inputNode = audioEngine.inputNode
        
        // Determine best audio input device
        let availableDevices = getAvailableInputDevices()
        var targetDevice: AudioInputDevice?
        
        if let selectedID = selectedDeviceID, let found = availableDevices.first(where: { $0.id == selectedID }) {
            targetDevice = found
        } else if let builtIn = availableDevices.first(where: { $0.isBuiltIn }) {
            // Built-in Microphone gives pristine 48kHz audio without Bluetooth codec degradation
            targetDevice = builtIn
        }
        
        if let target = targetDevice {
            applyDevice(to: inputNode, deviceID: target.id)
            print("🎙️ [AudioEngineManager] Configured input device: '\(target.name)' (ID: \(target.id), Built-in: \(target.isBuiltIn))")
        }
        
        // Safely remove any existing tap on bus 0 before installing
        var removeError: NSError?
        HardyFlowTryCatch({
            inputNode.removeTap(onBus: 0)
        }, &removeError)
        isTapInstalled = false
        
        // Inspect native hardware output format on bus 0
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        guard nativeFormat.sampleRate > 0 && nativeFormat.channelCount > 0 else {
            print("⚠️ [AudioEngineManager] Microphone hardware not ready (sample rate: \(nativeFormat.sampleRate)Hz, channels: \(nativeFormat.channelCount)).")
            throw NSError(
                domain: "HardyFlowAudioError",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "Microphone hardware not ready. Please verify audio input permissions."]
            )
        }
        
        let formatToUse: AVAudioFormat? = nativeFormat
        let bufferSize: AVAudioFrameCount = 1024
        
        var installError: NSError?
        let tapSuccess = HardyFlowTryCatch({
            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: formatToUse) { [weak self] (buffer, _) in
                guard let self = self else { return }
                
                // Whisper Mode: Apply digital soft-limiting pre-gain boost to quiet whispered audio
                if self.isWhisperModeEnabled, let channelData = buffer.floatChannelData {
                    let frameCount = Int(buffer.frameLength)
                    let channelCount = Int(buffer.format.channelCount)
                    let gain = self.whisperGainMultiplier
                    for ch in 0..<channelCount {
                        let ptr = channelData[ch]
                        for i in 0..<frameCount {
                            let boosted = ptr[i] * gain
                            ptr[i] = tanhf(boosted)
                        }
                    }
                }
                
                // Forward buffer to recognition consumers
                self.onAudioBuffer?(buffer)
                
                // Calculate normalized RMS audio level for waveform visualizer
                let level = self.calculateRMSLevel(from: buffer)
                DispatchQueue.main.async {
                    self.onAudioLevelChanged?(level)
                }
            }
        }, &installError)
        
        guard tapSuccess else {
            isTapInstalled = false
            let desc = installError?.localizedDescription ?? "Failed to install audio tap on input node."
            print("❌ [AudioEngineManager] Caught tap installation exception safely: \(desc)")
            throw NSError(domain: "HardyFlowAudioError", code: 1003, userInfo: [NSLocalizedDescriptionKey: desc])
        }
        
        isTapInstalled = true
        
        var prepareError: NSError?
        HardyFlowTryCatch({
            self.audioEngine.prepare()
        }, &prepareError)
        
        var startError: NSError?
        let startSuccess = HardyFlowTryCatch({
            do {
                try self.audioEngine.start()
            } catch {
                print("❌ [AudioEngineManager] AVAudioEngine.start() error: \(error.localizedDescription)")
            }
        }, &startError)
        
        guard startSuccess && audioEngine.isRunning else {
            let desc = startError?.localizedDescription ?? "Failed to start AVAudioEngine."
            print("❌ [AudioEngineManager] Failed to start engine safely: \(desc)")
            throw NSError(domain: "HardyFlowAudioError", code: 1004, userInfo: [NSLocalizedDescriptionKey: desc])
        }
        
        isRunning = true
        print("🎙️ [AudioEngineManager] Audio engine started successfully (Hardware format: \(nativeFormat.sampleRate)Hz, \(nativeFormat.channelCount) ch).")
    }
    
    /// Computes root-mean-square (RMS) power converted to a normalized 0.0 ... 1.0 range.
    private func calculateRMSLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0.0 }
        
        let channelDataArray = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        var sumSquares: Float = 0.0
        for sample in channelDataArray {
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Float(channelDataArray.count))
        
        // Convert to dB scale with a floor of -60dB
        let minDb: Float = -60.0
        let db = 20.0 * log10(max(rms, 0.00001))
        let clampedDb = max(minDb, min(0.0, db))
        
        // Normalize linearly from [minDb, 0] to [0.0, 1.0] with slight curve emphasis
        let normalized = (clampedDb - minDb) / (-minDb)
        return pow(normalized, 1.5)
    }
}
