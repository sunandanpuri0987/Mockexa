import Foundation
import AVFoundation
import Speech
import Combine

/// Persona Voice Configuration matching Mockexa GD Participants
public struct PersonaVoiceConfig {
    public let voice: AVSpeechSynthesisVoice?
    public let rate: Float
    public let pitch: Float
}

/// Abstract Voice Provider Interface for Pluggable Speech Synthesis (System TTS / High Quality Neural TTS)
@MainActor
public protocol VoiceProvider: AnyObject {
    var isSpeaking: Bool { get }
    func speak(text: String, speakerName: String, completion: @escaping () -> Void)
    func stopSpeaking()
}

/// Native Apple AVSpeechSynthesizer System TTS Provider
@MainActor
public final class SystemTTSProvider: NSObject, VoiceProvider, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var onFinish: (() -> Void)?
    @Published public private(set) var isSpeakingState: Bool = false
    
    public var isSpeaking: Bool {
        return synthesizer.isSpeaking || isSpeakingState
    }
    
    override public init() {
        super.init()
        synthesizer.delegate = self
    }
    
    public static func naturalVoice(for speakerName: String) -> PersonaVoiceConfig {
        let norm = speakerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let englishVoices = allVoices.filter { $0.language.hasPrefix("en") }
        
        func findVoice(preferredNames: [String], genderPreference: AVSpeechSynthesisVoiceGender) -> AVSpeechSynthesisVoice? {
            // 1. Prefer premium or enhanced quality matching preferred names
            for quality in [AVSpeechSynthesisVoiceQuality.premium, .enhanced, .default] {
                for name in preferredNames {
                    if let v = englishVoices.first(where: { $0.quality == quality && $0.name.localizedCaseInsensitiveContains(name) }) {
                        return v
                    }
                }
            }
            // 2. Prefer premium/enhanced quality matching preferred gender
            for quality in [AVSpeechSynthesisVoiceQuality.premium, .enhanced] {
                if let v = englishVoices.first(where: { $0.quality == quality && $0.gender == genderPreference }) {
                    return v
                }
            }
            // 3. Fallback matching gender
            if let v = englishVoices.first(where: { $0.gender == genderPreference }) {
                return v
            }
            // 4. Default system fallback
            return englishVoices.first ?? AVSpeechSynthesisVoice(language: "en-US")
        }
        
        if norm.contains("hr interviewer") || norm.contains("recruiter") {
            // HR Interviewer — warm, polished, professional female voice
            let v = findVoice(preferredNames: ["Samantha", "Ava", "Serena", "Victoria"], genderPreference: .female)
            return PersonaVoiceConfig(voice: v, rate: 0.48, pitch: 1.0)
        } else if norm.contains("maya") || norm.contains("shah") {
            // Dr. Maya Shah: Clinical Statistician — Calm, analytical, measured female voice
            let v = findVoice(preferredNames: ["Samantha", "Victoria", "Ava", "Zoe", "Moira"], genderPreference: .female)
            return PersonaVoiceConfig(voice: v, rate: 0.49, pitch: 1.0)
        } else if norm.contains("jordan") || norm.contains("lee") {
            // Jordan Lee: Public-Interest Ethicist — Thoughtful, conversational male voice
            let v = findVoice(preferredNames: ["Alex", "Daniel", "Oliver", "Tom", "Aaron"], genderPreference: .male)
            return PersonaVoiceConfig(voice: v, rate: 0.50, pitch: 1.0)
        } else if norm.contains("arjun") || norm.contains("mehta") {
            // Arjun Mehta: AI Entrepreneur — Energetic, persuasive, articulate male voice
            let v = findVoice(preferredNames: ["Rishi", "Arthur", "Daniel", "Jamie"], genderPreference: .male)
            return PersonaVoiceConfig(voice: v, rate: 0.52, pitch: 1.0)
        } else if norm.contains("elena") || norm.contains("ruiz") {
            // Elena Ruiz: Policy Economist — Composed, structured female voice
            let v = findVoice(preferredNames: ["Kate", "Serena", "Fiona", "Tessa", "Samantha"], genderPreference: .female)
            return PersonaVoiceConfig(voice: v, rate: 0.49, pitch: 1.0)
        } else {
            let v = englishVoices.first ?? AVSpeechSynthesisVoice(language: "en-US")
            return PersonaVoiceConfig(voice: v, rate: 0.50, pitch: 1.0)
        }
    }
    
    public func speak(text: String, speakerName: String, completion: @escaping () -> Void) {
        stopSpeaking()
        self.onFinish = completion
        
        let config = Self.naturalVoice(for: speakerName)
        let utterance = AVSpeechUtterance(string: text)
        
        if let v = config.voice {
            utterance.voice = v
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        
        utterance.rate = config.rate
        utterance.pitchMultiplier = 1.0 // Strictly 1.0 everywhere per requirement
        
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute.outputs.first?.portName ?? "Speaker"
        let sampleRate = session.sampleRate
        let voiceName = utterance.voice?.name ?? "Default"
        let language = utterance.voice?.language ?? "en-US"
        let qualityStr = utterance.voice?.quality == .premium ? "premium" : (utterance.voice?.quality == .enhanced ? "enhanced" : "default")
        
        print("""
        [VOICE][TTS]
        provider=SystemTTSProvider (AVSpeechSynthesizer)
        voice=\(voiceName)
        language=\(language)
        quality=\(qualityStr)
        rate=\(utterance.rate)
        pitch=\(utterance.pitchMultiplier)
        route=\(route)
        sampleRate=\(sampleRate)
        """)
        
        isSpeakingState = true
        synthesizer.speak(utterance)
    }
    
    public func stopSpeaking() {
        // Cancellation is not a natural completion. Clear the callback before
        // stopping so a superseded utterance cannot auto-enable the microphone
        // while the next neural clip is beginning playback.
        onFinish = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            print("[VOICE][TTS] SystemTTS stopped immediately")
        }
        isSpeakingState = false
    }
    
    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeakingState = false
            let cb = self.onFinish
            self.onFinish = nil
            cb?()
            print("[VOICE][TTS] SystemTTS finished speaking utterance")
        }
    }
    
    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeakingState = false
            self.onFinish = nil
            print("[VOICE][TTS] SystemTTS cancelled utterance")
        }
    }
}

/// Real Neural TTS Provider fetching high-fidelity MP3 audio from backend /tts route and playing via AVAudioPlayer
@MainActor
public final class HighQualityTTSProvider: NSObject, VoiceProvider, AVAudioPlayerDelegate {
    private var audioPlayer: AVAudioPlayer?
    private var onFinish: (() -> Void)?
    private let systemFallback = SystemTTSProvider()
    private var requestTask: Task<Void, Never>?
    private var requestGeneration = UUID()
    @Published public private(set) var isSpeakingState: Bool = false
    
    public var isSpeaking: Bool {
        return (audioPlayer?.isPlaying ?? false) || isSpeakingState || systemFallback.isSpeaking
    }
    
    public func speak(text: String, speakerName: String, completion: @escaping () -> Void) {
        stopSpeaking()
        self.onFinish = completion
        
        let cleanText = VoiceFoundation.sanitizeTextForTTS(text)
        guard !cleanText.isEmpty else {
            completion()
            return
        }
        
        // Target backend /tts endpoint
        guard let url = URL(string: "\(PrepConfig.baseURL)/tts") else {
            print("[VOICE][TTS] status=fallback reason=Invalid_TTS_URL speaker=\(speakerName)")
            systemFallback.speak(text: cleanText, speakerName: speakerName, completion: completion)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        
        let body: [String: Any] = [
            "text": cleanText,
            "speaker": speakerName
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            print("[VOICE][TTS] status=fallback reason=JSON_Serialization_Failed error=\(error) speaker=\(speakerName)")
            systemFallback.speak(text: cleanText, speakerName: speakerName, completion: completion)
            return
        }
        
        isSpeakingState = true
        print("[VOICE][TTS] request started for speaker: \(speakerName)")
        
        let generation = UUID()
        requestGeneration = generation

        // Give the backend time to return a complete clip. The old 750 ms guard
        // routinely cancelled valid neural requests and switched voices mid-flow.
        // Keep a bounded fallback for a genuinely stalled provider.
        let latencyGuardTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self = self, self.requestGeneration == generation, !Task.isCancelled else { return }
            if self.isSpeakingState && (self.audioPlayer == nil || !self.audioPlayer!.isPlaying) {
                print("[VOICE][TTS] Backend audio timed out after 8s; using system voice for this turn")
                self.requestTask?.cancel()
                self.isSpeakingState = false
                self.systemFallback.speak(text: cleanText, speakerName: speakerName, completion: completion)
            }
        }

        requestTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                latencyGuardTask.cancel()
                try Task.checkCancellation()
                guard self.requestGeneration == generation else { return }
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    print("[VOICE][TTS] status=fallback reason=Backend_HTTP_\(code) speaker=\(speakerName)")
                    self.isSpeakingState = false
                    self.onFinish = nil
                    self.systemFallback.speak(text: cleanText, speakerName: speakerName, completion: completion)
                    return
                }
                let provider = httpResponse.value(forHTTPHeaderField: "X-TTS-Provider") ?? "Neural"
                let cache = httpResponse.value(forHTTPHeaderField: "X-TTS-Cache") ?? "UNKNOWN"
                print("[VOICE][TTS] provider=\(provider) cache=\(cache) audio bytes=\(data.count) speaker=\(speakerName)")
                self.playAudioData(data, text: cleanText, speakerName: speakerName, completion: completion)
            } catch is CancellationError {
                latencyGuardTask.cancel()
                print("[VOICE][TTS] request cancelled speaker=\(speakerName)")
            } catch {
                latencyGuardTask.cancel()
                guard self.requestGeneration == generation else { return }
                print("[VOICE][TTS] status=fallback reason=Network_Error error=\(error) speaker=\(speakerName)")
                self.isSpeakingState = false
                self.onFinish = nil
                self.systemFallback.speak(text: cleanText, speakerName: speakerName, completion: completion)
            }
        }
    }
    
    private func playAudioData(_ data: Data, text: String, speakerName: String, completion: @escaping () -> Void) {
        do {
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.prepareToPlay()
            self.audioPlayer = player
            
            let duration = player.duration
            let session = AVAudioSession.sharedInstance()
            let route = session.currentRoute.outputs.first?.portName ?? "Speaker"
            let sampleRate = session.sampleRate
            
            print("""
            [VOICE][TTS] provider=NeuralTTS (OpenAI/ElevenLabs via Backend /tts)
            [VOICE][TTS] voice=\(speakerName)
            [VOICE][TTS] format=audio/mpeg (MP3)
            [VOICE][TTS] audio bytes=\(data.count)
            [VOICE][TTS] sampleRate=\(sampleRate)
            [VOICE][TTS] duration=\(String(format: "%.2fs", duration))
            [VOICE][TTS] route=\(route)
            [VOICE][TTS] playback started
            """)
            
            isSpeakingState = true
            guard player.play() else {
                throw NSError(domain: "VoiceFoundation", code: 5, userInfo: [NSLocalizedDescriptionKey: "Audio player could not start playback."])
            }
        } catch {
            print("[VOICE][TTS] AVAudioPlayer failed to play neural audio: \(error), falling back to SystemTTS")
            isSpeakingState = false
            onFinish = nil
            audioPlayer = nil
            systemFallback.speak(text: text, speakerName: speakerName, completion: completion)
        }
    }
    
    public func stopSpeaking() {
        requestGeneration = UUID()
        requestTask?.cancel()
        requestTask = nil
        // Do not run the natural-finish callback for an interruption or a new
        // turn. That callback may start STT and reconfigure AVAudioSession in
        // the middle of the next ElevenLabs clip, which sounds like crackling.
        onFinish = nil
        if let player = audioPlayer, player.isPlaying {
            player.stop()
            print("[VOICE][TTS] Neural AVAudioPlayer stopped immediately")
        }
        audioPlayer = nil
        isSpeakingState = false
        systemFallback.stopSpeaking()
    }
    
    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.audioPlayer === player else { return }
            self.isSpeakingState = false
            self.audioPlayer = nil
            print("[VOICE][TTS] playback finished successfully=\(flag)")
            let cb = self.onFinish
            self.onFinish = nil
            cb?()
        }
    }
    
    public nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            guard self.audioPlayer === player else { return }
            self.isSpeakingState = false
            self.audioPlayer = nil
            let cb = self.onFinish
            self.onFinish = nil
            cb?()
            print("[VOICE][TTS] Neural AVAudioPlayer decode error: \(error?.localizedDescription ?? "unknown")")
        }
    }
}

/// Main Voice Foundation Coordinator managing Audio Session, STT, and TTS
@MainActor
public final class VoiceFoundation: NSObject, ObservableObject {
    public static let shared = VoiceFoundation()
    
    public enum PermissionStatus: String {
        case notDetermined
        case authorized
        case denied
        case restricted
    }
    
    public enum VoiceState: String {
        case idle
        case speaking
        case listening
        case processing
    }
    
    // MARK: - Published State Properties
    @Published public private(set) var micPermission: PermissionStatus = .notDetermined
    @Published public private(set) var speechPermission: PermissionStatus = .notDetermined
    @Published public private(set) var currentState: VoiceState = .idle
    @Published public private(set) var recognizedText: String = ""
    @Published public private(set) var bestRecognizedText: String = ""
    @Published public private(set) var errorMessage: String? = nil
    @Published public private(set) var lastSTTError: String? = nil
    @Published public private(set) var audioBufferCount: Int = 0
    @Published public private(set) var detectedSampleRate: Double = 0.0
    @Published public private(set) var detectedChannelCount: Int = 0
    @Published public private(set) var isEngineRunning: Bool = false
    @Published public private(set) var isInputAvailable: Bool = false
    @Published public private(set) var isAudioSessionActive: Bool = false
    @Published public private(set) var inputRoutePortName: String = "None"
    @Published public private(set) var outputRoutePortName: String = "None"
    @Published public private(set) var isTapInstalled: Bool = false
    @Published public private(set) var isRecognizerAvailable: Bool = false
    @Published public private(set) var isSilenceTimerRunning: Bool = false
    @Published public private(set) var sttStatusText: String = "Listening…"
    @Published public private(set) var silenceCountdown: Int? = nil
    
    // Silence & Auto-Submit Callback
    public var onSilenceDetected: ((String) -> Void)?
    private var silenceTask: Task<Void, Never>?
    private var lastRecognizedLength: Int = 0
    
    public var isListening: Bool { currentState == .listening }
    public var isSpeaking: Bool { currentState == .speaking || ttsProvider.isSpeaking }
    public var isProcessing: Bool { currentState == .processing }
    
    // Primary Pluggable Voice Provider (defaults to HighQualityTTSProvider)
    public var ttsProvider: VoiceProvider = HighQualityTTSProvider()
    
    // MARK: - Internal Framework Engines
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var bufferCount: Int = 0
    private var hasReceivedSTTResult: Bool = false
    
    override public init() {
        super.init()
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        updatePermissionStatuses()
    }
    
    // MARK: - Permission Handling
    public func updatePermissionStatuses() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: micPermission = .authorized
        case .denied: micPermission = .denied
        case .undetermined: micPermission = .notDetermined
        @unknown default: micPermission = .notDetermined
        }
        
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: speechPermission = .authorized
        case .denied: speechPermission = .denied
        case .restricted: speechPermission = .restricted
        case .notDetermined: speechPermission = .notDetermined
        @unknown default: speechPermission = .notDetermined
        }
        
        if let recognizer = speechRecognizer {
            isRecognizerAvailable = recognizer.isAvailable
        } else {
            isRecognizerAvailable = false
        }
    }
    
    public func requestPermissions() async -> Bool {
        let micGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        
        updatePermissionStatuses()
        return micGranted && (speechStatus == .authorized)
    }
    
    // MARK: - Deterministic State & Audio Session Lifecycle
    private func configureAudioSession(for state: VoiceState) throws {
        let session = AVAudioSession.sharedInstance()
        
        switch state {
        case .speaking:
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            // Match the MP3 source rate before activation. This avoids a route
            // reconfiguration/resample at playback start that can sound like
            // a crack or brief metallic distortion on simulator/Bluetooth.
            try? session.setPreferredSampleRate(44_100)
            try? session.setPreferredIOBufferDuration(0.0116)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            isAudioSessionActive = true
        case .listening:
#if targetEnvironment(simulator)
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
#else
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
#endif
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            isAudioSessionActive = true
        case .processing, .idle:
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            isAudioSessionActive = false
        }
        
        let route = session.currentRoute.outputs.first?.portName ?? "Speaker"
        let inputRoute = session.currentRoute.inputs.first?.portName ?? "Microphone"
        inputRoutePortName = inputRoute
        outputRoutePortName = route
        isInputAvailable = session.isInputAvailable
        
        print("""
        [VOICE][SESSION]
        state=\(state.rawValue)
        category=\(session.category.rawValue)
        mode=\(session.mode.rawValue)
        inputPort=\(inputRoute)
        outputPort=\(route)
        inputChannels=\(session.inputNumberOfChannels)
        sampleRate=\(session.sampleRate)
        isInputAvailable=\(session.isInputAvailable)
        """)
    }
    
    // MARK: - Speech Recognition (STT)
    public func startListening() throws {
        print("[VOICE][STT] startListening() initiated")
        
        // 1. Interrupt active TTS immediately
        stopSpeakingInternal()
        
        // 2. Clean up existing STT session
        if isListening || recognitionTask != nil || audioEngine.isRunning {
            stopListeningInternal()
        }
        
        errorMessage = nil
        lastSTTError = nil
        recognizedText = ""
        bestRecognizedText = ""
        bufferCount = 0
        audioBufferCount = 0
        
        // 3. Verify Authorization
        updatePermissionStatuses()
        print("""
        [VOICE][STT][AUTH]
        speech=\(speechPermission.rawValue)
        microphone=\(micPermission.rawValue)
        """)
        
        guard micPermission == .authorized && speechPermission == .authorized else {
            errorMessage = "Microphone & Speech access are required for voice practice."
            print("[VOICE][STT] Authorization missing (mic: \(micPermission), speech: \(speechPermission))")
            currentState = .idle
            throw NSError(domain: "VoiceFoundation", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMessage!])
        }
        
        guard let recognizer = speechRecognizer else {
            errorMessage = "Speech recognizer uninitialized."
            print("[VOICE][STT] speechRecognizer is nil")
            currentState = .idle
            throw NSError(domain: "VoiceFoundation", code: 2, userInfo: [NSLocalizedDescriptionKey: errorMessage!])
        }
        
        print("""
        [VOICE][STT][RECOGNIZER]
        available=\(recognizer.isAvailable)
        locale=\(recognizer.locale.identifier)
        supportsOnDeviceRecognition=\(recognizer.supportsOnDeviceRecognition)
        """)
        
        guard recognizer.isAvailable else {
            errorMessage = "Speech recognizer is currently unavailable."
            print("[VOICE][STT] SFSpeechRecognizer is not available")
            currentState = .idle
            throw NSError(domain: "VoiceFoundation", code: 2, userInfo: [NSLocalizedDescriptionKey: errorMessage!])
        }
        
        // 4. Configure Audio Session FIRST
        try configureAudioSession(for: .listening)
        let session = AVAudioSession.sharedInstance()
        
        let inputs = session.currentRoute.inputs
        let inputPort = inputs.first?.portName ?? "Microphone"
        let outputs = session.currentRoute.outputs
        let outputPort = outputs.first?.portName ?? "Speaker"
        
        print("""
        [VOICE][STT][SESSION]
        category=\(session.category.rawValue)
        mode=\(session.mode.rawValue)
        sampleRate=\(session.sampleRate)
        inputNumberOfChannels=\(session.inputNumberOfChannels)
        inputAvailable=\(session.isInputAvailable)
        currentRoute=\(session.currentRoute.description)
        inputPort=\(inputPort)
        outputPort=\(outputPort)
        """)
        
#if targetEnvironment(simulator)
        print("""
        [VOICE][STT][SIMULATOR_MIC]
        target=iOS_Simulator
        inputAvailable=\(session.isInputAvailable)
        inputPort=\(inputPort)
        outputPort=\(outputPort)
        engineRunning=\(audioEngine.isRunning)
        """)
#else
        print("""
        [VOICE][STT][PHYSICAL_MIC]
        target=Physical_iPhone
        inputAvailable=\(session.isInputAvailable)
        inputPort=\(inputPort)
        outputPort=\(outputPort)
        engineRunning=\(audioEngine.isRunning)
        """)
#endif
        
        guard session.isInputAvailable else {
            errorMessage = "Microphone input hardware is unavailable."
            print("[VOICE][STT][SESSION] ERROR: session.isInputAvailable is false")
            currentState = .idle
            throw NSError(domain: "VoiceFoundation", code: 4, userInfo: [NSLocalizedDescriptionKey: errorMessage!])
        }
        
        // 5. Create Recognition Request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            errorMessage = "Unable to create speech recognition request."
            currentState = .idle
            throw NSError(domain: "VoiceFoundation", code: 3, userInfo: [NSLocalizedDescriptionKey: errorMessage!])
        }
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        
        // 6. Setup Audio Engine & Resolve Hardware Format
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        let inputNode = audioEngine.inputNode
        let nativeInputFormat = inputNode.inputFormat(forBus: 0)
        let nativeOutputFormat = inputNode.outputFormat(forBus: 0)
        
        print("""
        [VOICE][STT][FORMAT]
        inputFormat=\(nativeInputFormat)
        outputFormat=\(nativeOutputFormat)
        inputSampleRate=\(nativeInputFormat.sampleRate)
        outputSampleRate=\(nativeOutputFormat.sampleRate)
        inputChannels=\(nativeInputFormat.channelCount)
        outputChannels=\(nativeOutputFormat.channelCount)
        """)
        
        let recordingFormat: AVAudioFormat
        if nativeOutputFormat.sampleRate > 0 && nativeOutputFormat.channelCount > 0 {
            recordingFormat = nativeOutputFormat
        } else if nativeInputFormat.sampleRate > 0 && nativeInputFormat.channelCount > 0 {
            recordingFormat = nativeInputFormat
        } else {
            recordingFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        }
        
        self.detectedSampleRate = recordingFormat.sampleRate
        self.detectedChannelCount = Int(recordingFormat.channelCount)
        
        // 7. Start Speech Recognition Task BEFORE Installing Tap & Starting Audio Engine
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let result = result {
                    self.hasReceivedSTTResult = true
                    let text = result.bestTranscription.formattedString
                    let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let lengthChanged = (cleanText.count != self.lastRecognizedLength)
                    self.recognizedText = cleanText
                    self.lastRecognizedLength = cleanText.count
                    
                    if cleanText.count >= self.bestRecognizedText.count || result.isFinal {
                        self.bestRecognizedText = cleanText
                    }
                    
                    print("""
                    [VOICE][STT][RESULT]
                    isFinal=\(result.isFinal)
                    text="\(cleanText)"
                    best="\(self.bestRecognizedText)"
                    """)
                    
                    print("""
                    [VOICE][STT][SEGMENTS]
                    count=\(result.bestTranscription.segments.count)
                    """)
                    
                    if !cleanText.isEmpty && (lengthChanged || result.isFinal) {
                        self.sttStatusText = "Listening…"
                        self.restartSilenceTimer()
                    }
                }
                if let error = error {
                    let nsError = error as NSError
                    let underlyingErr = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
                    let underlyingDesc = underlyingErr != nil ? "\(underlyingErr!.domain) (\(underlyingErr!.code)): \(underlyingErr!.localizedDescription)" : "none"
                    
                    print("""
                    [VOICE][STT][ERROR]
                    domain=\(nsError.domain)
                    code=\(nsError.code)
                    description=\(nsError.localizedDescription)
                    underlying=\(underlyingDesc)
                    """)
                    
                    self.lastSTTError = "\(nsError.domain) (\(nsError.code)): \(nsError.localizedDescription)"
                }
            }
        }
        
        print("[VOICE][STT][RECOGNITION] taskCreated=true")
        
        // 8. Install Exactly ONE Input Tap
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, when in
            guard let self = self else { return }
            self.recognitionRequest?.append(buffer)
            self.bufferCount += 1
            
            let count = self.bufferCount
            let frameLength = buffer.frameLength
            let sRate = buffer.format.sampleRate
            let chans = buffer.format.channelCount
            
            if count <= 5 || count % 20 == 0 {
                print("""
                [VOICE][STT][BUFFER]
                count=\(count)
                frameLength=\(frameLength)
                sampleRate=\(sRate)
                channels=\(chans)
                """)
            }
            
            if count >= 60 && !self.hasReceivedSTTResult && self.recognizedText.isEmpty && count % 30 == 0 {
                let isRecAvail = self.speechRecognizer?.isAvailable ?? false
                let isTaskActive = (self.recognitionTask != nil)
                print("""
                [VOICE][STT][NO_RESULT]
                buffers=\(count)
                recognizerAvailable=\(isRecAvail)
                taskActive=\(isTaskActive)
                transcriptLength=\(self.recognizedText.count)
                """)
            }
            
            if count == 1 || count % 40 == 0 {
                let isRecAvail = self.speechRecognizer?.isAvailable ?? false
                let isTaskActive = (self.recognitionTask != nil)
                print("""
                [VOICE][STT][HEALTH]
                state=\(self.currentState.rawValue)
                engineRunning=\(self.audioEngine.isRunning)
                bufferCount=\(count)
                recognizerAvailable=\(isRecAvail)
                recognitionTaskActive=\(isTaskActive)
                recognizedTextLength=\(self.recognizedText.count)
                """)
            }
            
            if count == 1 || count % 10 == 0 {
                Task { @MainActor [weak self] in
                    self?.audioBufferCount = count
                }
            }
        }
        self.isTapInstalled = true
        
        // 9. Prepare & Start Audio Engine
        audioEngine.prepare()
        try audioEngine.start()
        self.isEngineRunning = audioEngine.isRunning
        currentState = .listening
        sttStatusText = "Listening…"
        lastRecognizedLength = 0
        cancelSilenceTimer()
        
        print("""
        [VOICE][STT][RUNTIME]
        state=\(currentState.rawValue)
        micPermission=\(micPermission.rawValue)
        speechPermission=\(speechPermission.rawValue)
        recognizerAvailable=\(recognizer.isAvailable)
        audioSessionActive=\(isAudioSessionActive)
        inputAvailable=\(isInputAvailable)
        inputNumberOfChannels=\(session.inputNumberOfChannels)
        sampleRate=\(session.sampleRate)
        routeInputs=\(inputRoutePortName)
        routeOutputs=\(outputRoutePortName)
        engineRunning=\(isEngineRunning)
        tapInstalled=\(isTapInstalled)
        """)
    }
    
    // MARK: - Silence & Debounce Detection Logic
    private func restartSilenceTimer() {
        silenceTask?.cancel()
        silenceCountdown = nil
        isSilenceTimerRunning = true
        
        silenceTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            // Allow 1.8 seconds of natural thinking pause before starting auto-submit countdown
            do {
                try await Task.sleep(nanoseconds: 1_800_000_000)
            } catch {
                return
            }
            
            guard self.currentState == .listening else { return }
            let textSnapshot = self.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !textSnapshot.isEmpty else { return }
            
            // 3-second visible countdown (3... 2... 1...)
            for remaining in (1...3).reversed() {
                self.silenceCountdown = remaining
                self.sttStatusText = "Auto-submitting in \(remaining)s…"
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
                guard self.currentState == .listening else { return }
            }
            
            self.silenceCountdown = nil
            let finalText = self.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !finalText.isEmpty else { return }
            
            print("""
            [VOICE][STT][AUTO_SUBMIT]
            transcript="\(finalText)"
            reason=natural_silence
            """)
            
            self.sttStatusText = "Submitting answer…"
            self.onSilenceDetected?(finalText)
        }
    }
    
    private func cancelSilenceTimer() {
        silenceTask?.cancel()
        silenceTask = nil
        silenceCountdown = nil
        isSilenceTimerRunning = false
    }
    
    @discardableResult
    public func stopListening() -> String {
        cancelSilenceTimer()
        let text = stopListeningInternal()
        currentState = .idle
        try? configureAudioSession(for: .idle)
        return text
    }
    
    @discardableResult
    public func stopListeningAndProcess() -> String {
        cancelSilenceTimer()
        let text = stopListeningInternal()
        currentState = .processing
        try? configureAudioSession(for: .processing)
        return text
    }
    
    @discardableResult
    private func stopListeningInternal() -> String {
        cancelSilenceTimer()
        
        // 1. Signal end of audio to flush SFSpeechRecognizer buffers
        recognitionRequest?.endAudio()
        
        // 2. Resolve best transcript (prefer accumulated bestRecognizedText over partial)
        let candidate = bestRecognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTranscript = candidate.isEmpty ? fallback : candidate
        
        // 3. Stop audio engine and remove tap safely
        audioEngine.stop()
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        
        recognitionRequest = nil
        recognitionTask?.finish()
        recognitionTask = nil
        
        self.isEngineRunning = false
        
        print("[VOICE][STT] stopped final transcript: \"\(finalTranscript)\"")
        return finalTranscript
    }
    
    // MARK: - Barge-in & Interruption
    public func interruptAndListen() {
        print("[VOICE][BARGE-IN] Interrupting AI speech directly to listening")
        stopSpeakingInternal()
        do {
            try startListening()
        } catch {
            print("[VOICE][BARGE-IN] Failed to start listening on interrupt: \(error)")
            currentState = .idle
        }
    }
    
    public func setProcessing() {
        if isListening {
            stopListeningInternal()
        }
        stopSpeakingInternal()
        currentState = .processing
        try? configureAudioSession(for: .processing)
    }
    
    public func resetToIdle() {
        if isListening {
            stopListeningInternal()
        }
        stopSpeakingInternal()
        currentState = .idle
        try? configureAudioSession(for: .idle)
    }
    
    // MARK: - Text To Speech (TTS) Text Preprocessing
    public static func sanitizeTextForTTS(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        var cleaned = text
        // Remove markdown headers
        cleaned = cleaned.replacingOccurrences(of: #"#+\s*"#, with: "", options: .regularExpression)
        // Remove markdown bold/italic (**text** or *text*)
        cleaned = cleaned.replacingOccurrences(of: #"\*+([^*]+)\*+"#, with: "$1", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"_+([^_]+)_+"#, with: "$1", options: .regularExpression)
        // Remove bullets and list numbers
        cleaned = cleaned.replacingOccurrences(of: #"^\s*[-•*]\s+"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"^\s*\d+\.\s+"#, with: "", options: .regularExpression)
        // Normalize line breaks to sentence pauses
        cleaned = cleaned.replacingOccurrences(of: #"\n+"#, with: ". ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\.{2,}"#, with: ".", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func speak(text: String, speakerName: String = "Dr. Maya Shah", autoListenOnFinish: Bool = true) {
        let cleanText = VoiceFoundation.sanitizeTextForTTS(text)
        guard !cleanText.isEmpty else { return }
        
        // 1. Interrupt listening or previous speech
        if isListening {
            stopListeningInternal()
        }
        stopSpeakingInternal()
        
        // 2. Configure Audio Session for Speaking
        do {
            try configureAudioSession(for: .speaking)
        } catch {
            print("[VOICE] Audio session config error for TTS: \(error)")
        }
        
        currentState = .speaking
        ttsProvider.speak(text: cleanText, speakerName: speakerName) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                if self.currentState == .speaking {
                    if autoListenOnFinish {
                        print("[VOICE] TTS finished, auto-activating microphone...")
                        do {
                            try self.startListening()
                        } catch {
                            print("[VOICE] Auto-listen failed: \(error)")
                            self.currentState = .idle
                        }
                    } else {
                        self.currentState = .idle
                    }
                }
            }
        }
    }
    
    public func stopSpeaking() {
        stopSpeakingInternal()
        if currentState == .speaking {
            currentState = .idle
        }
    }
    
    private func stopSpeakingInternal() {
        ttsProvider.stopSpeaking()
    }
}
