//
//  CoreAUdioTapEngineError.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/28/25.
//

import Foundation




enum CoreAudioTapEngineError: Error, LocalizedError {
    case noTargetProcesses
    case tapCreationFailed(OSStatus)
    case aggregateCreationFailed(OSStatus)
    case formatCreationFailed
    case invalidTapStreamDescription
    case invalidStreamDescription
    case ioProcCreationFailed(OSStatus)
    case deviceStartFailed(OSStatus)
    case tapNotInstalled
    case unsupportedMacOSVersion
    case processNotFound(String)

    var errorDescription: String? {
        switch self {
        case .noTargetProcesses:
            return "No target audio processes were specified for the tap."
        case .tapCreationFailed(let status):
            return "Failed to create the system audio tap. Error code: \(status)"
        case .aggregateCreationFailed(let status):
            return "Failed to create the aggregate audio device. Error code: \(status)"
        case .formatCreationFailed:
            return "Unable to create AVAudioFormat from tap stream description."
        case .invalidTapStreamDescription:
            return "Invalid or missing stream description from the audio tap."
        case .invalidStreamDescription:
            return "Invalid audio stream description."
        case .ioProcCreationFailed(let status):
            return "Failed to create I/O proc for audio processing. Error code: \(status)"
        case .deviceStartFailed(let status):
            return "Failed to start audio device for capture. Error code: \(status)"
        case .tapNotInstalled:
            return "Tap must be installed before starting the engine."
        case .unsupportedMacOSVersion:
            return "System audio capture requires macOS 14.4 or later."
        case .processNotFound(let processName):
            return "Process not found: \(processName). Please ensure it is running."
        }
    }
}
