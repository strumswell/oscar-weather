// Records a USB-connected iPhone's screen (the QuickTime route) until SIGINT.
// Usage: swift iphone-record.swift <out.mov> <device name or udid>
import AVFoundation
import CoreMediaIO

var allow: UInt32 = 1
var address = CMIOObjectPropertyAddress(
    mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &allow)

let args = CommandLine.arguments
let out = URL(fileURLWithPath: args[1])
let wanted = args.count > 2 ? args[2] : ""
func find() -> AVCaptureDevice? {
    AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .muxed, position: .unspecified)
        .devices.first { wanted.isEmpty || $0.localizedName == wanted || $0.uniqueID.replacingOccurrences(of: "-", with: "") == wanted.replacingOccurrences(of: "-", with: "") }
        ?? AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .muxed, position: .unspecified).devices.first
}
// The device shows up a moment after screen capture devices are allowed.
var device: AVCaptureDevice?
for _ in 0..<50 where device == nil {
    device = find()
    if device == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
}
guard let device else { FileHandle.standardError.write("no iPhone screen found (USB cable, unlocked, trusted?)\n".data(using: .utf8)!); exit(1) }

final class Delegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo url: URL, from connections: [AVCaptureConnection]) {
        FileHandle.standardError.write("Recording started\n".data(using: .utf8)!)
    }
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error, (error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool != true {
            FileHandle.standardError.write("\(error.localizedDescription)\n".data(using: .utf8)!)
            exit(1)
        }
        exit(0)
    }
}

let session = AVCaptureSession()
let output = AVCaptureMovieFileOutput()
let delegate = Delegate()
do { session.addInput(try AVCaptureDeviceInput(device: device)) } catch { FileHandle.standardError.write("\(error.localizedDescription)\n".data(using: .utf8)!); exit(1) }
session.addOutput(output)
session.startRunning()
output.startRecording(to: out, recordingDelegate: delegate)

signal(SIGINT, SIG_IGN)
let stop = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
stop.setEventHandler { output.stopRecording() }
stop.resume()
dispatchMain()
