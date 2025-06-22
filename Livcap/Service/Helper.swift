//
//  Helper.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/9/25.
//

import Foundation
import SwiftUI

func debugLog(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    #if DEBUG
    let fileName = (file as NSString).lastPathComponent
    print("[\(fileName):\(line)] \(function) - \(message)")
    #endif
}


func isRunningInPreview() -> Bool {
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}


extension Color{
    static let backgroundColor=Color("BackgroundColor")
}
