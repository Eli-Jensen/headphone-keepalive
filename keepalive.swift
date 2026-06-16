// keepalive — keeps a continuous, inaudible audio stream flowing to the default
// output device so Bluetooth headphones (e.g. Bose QC) never idle their amp/DAC
// and therefore never produce the start/stop crackle.
//
// Idle-aware: pauses the stream after a period of user inactivity so the Mac can
// idle-sleep on its normal schedule, and resumes the instant you're active again.
// It only holds an audio stream (which is what makes macOS prevent idle sleep)
// while you're actually using the machine — and an active user already prevents
// idle sleep anyway. Manual sleep / closing the lid is never affected.
//
// Usage:
//   keepalive                      pure digital silence; pause after 120s idle
//   keepalive --idle-stop 90       pause after 90s of inactivity
//   keepalive --idle-stop 0        never pause (always on; this WILL block idle sleep)
//   keepalive --db -90 --freq 20   sub-audible tone fallback instead of pure silence
//   keepalive --quiet              suppress the periodic heartbeat log

import AVFoundation
import Foundation
import IOKit
import AppKit

// ---- Parse args ----
var dbfs: Double? = nil       // nil => pure digital silence
var freq: Double = 20.0       // Hz; sub-bass, where the ear is least sensitive
var quiet = false             // suppress the periodic heartbeat
var idleStop: Double = 120    // seconds of inactivity before pausing (0 = never)

var args = Array(CommandLine.arguments.dropFirst())
var i = 0
while i < args.count {
    switch args[i] {
    case "--db":
        i += 1
        if i < args.count, let v = Double(args[i]) { dbfs = v }
    case "--freq":
        i += 1
        if i < args.count, let v = Double(args[i]) { freq = v }
    case "--idle-stop":
        i += 1
        if i < args.count, let v = Double(args[i]) { idleStop = v }
    case "--silence":
        dbfs = nil
    case "--quiet":
        quiet = true
    default:
        FileHandle.standardError.write("keepalive: ignoring unknown arg \(args[i])\n".data(using: .utf8)!)
    }
    i += 1
}

let amplitude: Double = dbfs.map { pow(10.0, $0 / 20.0) } ?? 0.0

// ---- System idle time: nanoseconds since last HID (keyboard/mouse) event ----
func systemIdleSeconds() -> Double {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
    if service == 0 { return 0 }
    defer { IOObjectRelease(service) }
    guard let cf = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString,
                                                   kCFAllocatorDefault, 0)?.takeRetainedValue(),
          let num = cf as? NSNumber else { return 0 }
    return num.doubleValue / 1_000_000_000.0
}

// ---- Signal generator (state lives on the audio render thread) ----
final class Generator {
    let amplitude: Double
    let phaseInc: Double
    var phase: Double = 0
    var renderedFrames: Int = 0   // diagnostic counter (benign cross-thread read)

    init(amplitude: Double, freq: Double, sampleRate: Double) {
        self.amplitude = amplitude
        self.phaseInc = 2.0 * Double.pi * freq / sampleRate
    }

    func render(_ frameCount: AVAudioFrameCount, _ abl: UnsafeMutableAudioBufferListPointer) {
        if amplitude == 0.0 {
            for buf in abl { memset(buf.mData, 0, Int(buf.mDataByteSize)) }
        } else {
            let twoPi = 2.0 * Double.pi
            for frame in 0..<Int(frameCount) {
                let sample = Float(amplitude * sin(phase))
                phase += phaseInc
                if phase >= twoPi { phase -= twoPi }
                for buf in abl {
                    buf.mData!.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }
        }
        renderedFrames += Int(frameCount)
    }
}

// ---- Engine setup ----
let engine = AVAudioEngine()
let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
let gen = Generator(amplitude: amplitude, freq: freq, sampleRate: format.sampleRate)

let srcNode = AVAudioSourceNode(format: format) { _, _, frameCount, ablPointer -> OSStatus in
    gen.render(frameCount, UnsafeMutableAudioBufferListPointer(ablPointer))
    return noErr
}

engine.attach(srcNode)
engine.connect(srcNode, to: engine.mainMixerNode, format: format)

func startEngineIfNeeded(_ reason: String) {
    guard !engine.isRunning else { return }
    do {
        try engine.start()
        print("[keepalive] stream ON  (\(reason))")
    } catch {
        FileHandle.standardError.write("keepalive: failed to start engine: \(error)\n".data(using: .utf8)!)
    }
}

func stopEngineIfNeeded(_ reason: String) {
    guard engine.isRunning else { return }
    engine.stop()
    print("[keepalive] stream OFF (\(reason))")
}

// Re-engage on audio config change (output device switch / wake) — but only if the
// user is active, so a device change while idle doesn't defeat idle-sleep.
NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                       object: engine, queue: .main) { _ in
    if idleStop <= 0 || systemIdleSeconds() < idleStop {
        startEngineIfNeeded("audio config changed")
    }
}

// ---- Sleep / wake (covers manual sleep & lid close) ----
let wsnc = NSWorkspace.shared.notificationCenter
wsnc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
    stopEngineIfNeeded("system sleeping")
}
wsnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
    startEngineIfNeeded("system woke")
}

setbuf(stdout, nil)  // unbuffered so log lines flush immediately

let mode = amplitude == 0.0
    ? "PURE DIGITAL SILENCE (zeros)"
    : String(format: "%.0f Hz tone @ %.1f dBFS (amplitude %.6g)", freq, dbfs ?? 0, amplitude)
let idleDesc = idleStop <= 0 ? "never (always on)" : String(format: "%.0fs inactivity", idleStop)
print("[keepalive] starting — mode: \(mode); pause after: \(idleDesc)")
startEngineIfNeeded("startup")

// ---- Idle poll: pause when inactive (lets the Mac idle-sleep), resume on activity ----
if idleStop > 0 {
    Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
        if systemIdleSeconds() >= idleStop {
            stopEngineIfNeeded("idle \(Int(idleStop))s+")
        } else {
            startEngineIfNeeded("active")
        }
    }
}

// Heartbeat: proves the stream is live while running.
var lastFrames = 0
func heartbeat() {
    let now = gen.renderedFrames
    let delta = now - lastFrames
    lastFrames = now
    print("[keepalive] alive — running=\(engine.isRunning) totalFrames=\(now) (+\(delta) since last check)")
}
Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in heartbeat() }
if !quiet {
    Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in heartbeat() }
}

RunLoop.main.run()
