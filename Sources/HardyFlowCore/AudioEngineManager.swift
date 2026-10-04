import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

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
    
    private var audioEngine = AVAudioEngine()
    private let engineQueue = DispatchQueue(label: "com.hardyflow.audioengine", qos: .userInteractive)
    private static let queueKey = DispatchSpecificKey<Void>()
    private var configChangeWorkItem: DispatchWorkItem?
    
    public private(set) var isRunning: Bool = false
    public var selectedDeviceID: AudioDeviceID?
    
    /// Handler invoked for each incoming PCM audio buffer.
    public var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    
    /// Handler invoked on the main queue with normalized audio power (0.0 to 1.0) for live waveform visualization.
    public var onAudioLevelChanged: ((Float) -> Void)?
    
    private init() {
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
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRunning = false
        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevelChanged?(0.0)
        }
        print("⏹️ [AudioEngineManager] Audio engine stopped.")
    }
    
    private func startInternal() throws {
        if isRunning {
            return
        }
        
        audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        
        // Determine best audio input device
        let availableDevices = getAvailableInputDevices()
        var targetDevice: AudioInputDevice?
        
        if let selectedID = selectedDeviceID, let found = availableDevices.first(where: { $0.id == selectedID }) {
            targetDevice = found
        } else if let builtIn = availableDevices.first(where: { $0.isBuiltIn }) {
            // If AirPods / Bluetooth headphones are connected, default input switches to Bluetooth SCO (telephone quality).
            // Selecting the Built-in Microphone gives pristine 48kHz studio audio without Bluetooth codec degradation!
            targetDevice = builtIn
        }
        
        if let target = targetDevice {
            applyDevice(to: inputNode, deviceID: target.id)
            print("🎙️ [AudioEngineManager] Configured input device: '\(target.name)' (ID: \(target.id), Built-in: \(target.isBuiltIn))")
        }
        
        // Remove any existing tap on bus 0 before installing
        inputNode.removeTap(onBus: 0)
        
        // Inspect native hardware output format on bus 0
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        let formatToUse: AVAudioFormat? = (nativeFormat.sampleRate > 0 && nativeFormat.channelCount > 0) ? nativeFormat : nil
        
        let bufferSize: AVAudioFrameCount = 1024
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: formatToUse) { [weak self] (buffer, _) in
            guard let self = self else { return }
            
            // Forward buffer to recognition consumers
            self.onAudioBuffer?(buffer)
            
            // Calculate normalized RMS audio level for waveform visualizer
            let level = self.calculateRMSLevel(from: buffer)
            DispatchQueue.main.async {
                self.onAudioLevelChanged?(level)
            }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
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
