// keepalive — keeps inaudible audio flowing to the default output so Bluetooth
// headphones (e.g. Bose QC) never idle their amp/DAC and pop when audio starts/stops.
//
// Plays a looping file through AVAudioPlayer — the high-level media-player API that
// music/podcast apps use — rather than a hand-managed AVAudioEngine graph, so it rides
// through audio-device / Bluetooth reconfigurations the way a browser media element does.
//
// Only runs when the active output is a Bluetooth device (that's the only case the
// crackle affects); goes dormant on built-in speakers, wired output, etc.
//
// Sleep-friendly: pauses a grace window after the display sleeps; resumes on wake.
//
// Usage:
//   keepalive                      pure silence; pause 5 min after display sleep
//   keepalive --grace 60           pause 60s after the display sleeps (0 = at once)
//   keepalive --db -50 --freq 20   sub-audible tone instead of silence
//   keepalive --quiet              suppress the periodic heartbeat log

import AVFoundation
import Foundation
import AppKit
import CoreGraphics
import CoreAudio

// ---- Args ----
var dbfs: Double? = nil
var freq: Double = 20.0
var quiet = false
var grace: Double = 300

var args = Array(CommandLine.arguments.dropFirst())
var i = 0
while i < args.count {
    switch args[i] {
    case "--db":    i += 1; if i < args.count, let v = Double(args[i]) { dbfs = v }
    case "--freq":  i += 1; if i < args.count, let v = Double(args[i]) { freq = v }
    case "--grace": i += 1; if i < args.count, let v = Double(args[i]) { grace = v }
    case "--silence": dbfs = nil
    case "--quiet":   quiet = true
    default: FileHandle.standardError.write("keepalive: ignoring unknown arg \(args[i])\n".data(using: .utf8)!)
    }
    i += 1
}
let amplitude: Double = dbfs.map { pow(10.0, $0 / 20.0) } ?? 0.0

// ---- Timestamped logging ----
let logTimeFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()
func log(_ s: String) { print("\(logTimeFmt.string(from: Date())) \(s)") }
setbuf(stdout, nil)

// ---- CoreAudio: is the current default output a Bluetooth device? ----
func defaultOutputDevice() -> AudioDeviceID {
    var dev = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev)
    return dev
}
func deviceTransport(_ dev: AudioDeviceID) -> UInt32 {
    var t = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &t)
    return t
}
func deviceName(_ dev: AudioDeviceID) -> String {
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    if AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &name) == noErr,
       let n = name?.takeRetainedValue() { return n as String }
    return "output \(dev)"
}
func outputIsBluetooth() -> Bool {
    let dev = defaultOutputDevice()
    if dev == 0 { return false }
    let t = deviceTransport(dev)
    return t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
}

// ---- Build a short loop file: silence, or an integer number of tone cycles (seamless) ----
func makeLoopURL() throws -> URL {
    let sr = 44100.0
    let target = 10.0
    let frames: Int
    if amplitude == 0.0 || freq <= 0 {
        frames = Int(sr * target)
    } else {
        let cycles = max(1.0, (target * freq).rounded())
        frames = Int((cycles * sr / freq).rounded())
    }
    let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sr, channels: 2, interleaved: false)!
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(frames))!
    buf.frameLength = AVAudioFrameCount(frames)
    let c0 = buf.floatChannelData![0]
    let c1 = buf.floatChannelData![1]
    if amplitude == 0.0 {
        for n in 0..<frames { c0[n] = 0; c1[n] = 0 }
    } else {
        let twoPi = 2.0 * Double.pi
        let inc = twoPi * freq / sr
        var ph = 0.0
        for n in 0..<frames {
            let s = Float(amplitude * sin(ph))
            c0[n] = s; c1[n] = s
            ph += inc; if ph >= twoPi { ph -= twoPi }
        }
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("keepalive-loop.wav")
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sr, AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings)
    try file.write(from: buf)
    return url
}

// ---- Player ----
let player: AVAudioPlayer
do {
    player = try AVAudioPlayer(contentsOf: try makeLoopURL())
} catch {
    FileHandle.standardError.write("keepalive: setup failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}
player.numberOfLoops = -1
player.volume = 1.0
player.prepareToPlay()

// Play only when present (display awake / grace) AND the output is Bluetooth.
var awake = true
func shouldPlay() -> Bool { awake && outputIsBluetooth() }
func reconcile(_ reason: String) {
    if shouldPlay() {
        if !player.isPlaying { player.play(); log("[keepalive] play ON  (\(reason))") }
    } else {
        if player.isPlaying { player.pause(); log("[keepalive] play OFF (\(reason))") }
    }
}

// ---- React to output-device changes (connect/disconnect/switch) ----
var outAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                         mScope: kAudioObjectPropertyScopeGlobal,
                                         mElement: kAudioObjectPropertyElementMain)
AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &outAddr, DispatchQueue.main) { _, _ in
    let dev = defaultOutputDevice()
    log("[keepalive] output → \(deviceName(dev)) (\(outputIsBluetooth() ? "Bluetooth" : "not Bluetooth"))")
    reconcile("output changed")
}

// ---- Grace timer: pause only after the display has been off `grace` seconds ----
var graceTimer: Timer?
func armGrace() {
    graceTimer?.invalidate()
    if grace <= 0 { awake = false; reconcile("display off"); return }
    graceTimer = Timer.scheduledTimer(withTimeInterval: grace, repeats: false) { _ in
        awake = false; reconcile("display off \(Int(grace))s+")
    }
}
func cancelGrace() { graceTimer?.invalidate(); graceTimer = nil }

let wsnc = NSWorkspace.shared.notificationCenter
wsnc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in
    if grace > 0 { log("[keepalive] display slept — holding \(Int(grace))s before pausing") }
    armGrace()
}
wsnc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in
    cancelGrace(); awake = true; reconcile("display woke")
}
wsnc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
    cancelGrace(); awake = false; reconcile("system sleeping")
}
wsnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
    cancelGrace(); awake = true; reconcile("system woke")
}

// ---- Banner + start ----
let mode = amplitude == 0.0
    ? "PURE DIGITAL SILENCE (zeros)"
    : String(format: "%.0f Hz tone @ %.1f dBFS", freq, dbfs ?? 0)
let graceDesc = grace <= 0 ? "on display sleep"
    : (grace.truncatingRemainder(dividingBy: 60) == 0 ? "\(Int(grace / 60)) min after display sleep"
                                                       : "\(Int(grace))s after display sleep")
log("[keepalive] starting — AVAudioPlayer; \(mode); Bluetooth-output only; pauses: \(graceDesc)")

awake = true
if CGDisplayIsAsleep(CGMainDisplayID()) != 0 { armGrace() }
let dev0 = defaultOutputDevice()
log("[keepalive] output is \(deviceName(dev0)) (\(outputIsBluetooth() ? "Bluetooth" : "not Bluetooth"))")
reconcile("startup")

// ---- Heartbeat ----
func heartbeat() {
    log("[keepalive] alive — playing=\(player.isPlaying) t=\(String(format: "%.1f", player.currentTime))s output=\(outputIsBluetooth() ? "BT" : "non-BT")")
}
Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in heartbeat() }
if !quiet {
    Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in heartbeat() }
}

RunLoop.main.run()
