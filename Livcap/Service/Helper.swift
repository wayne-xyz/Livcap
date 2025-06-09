//
//  Helper.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/9/25.
//

import Foundation

func debugLog(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    #if DEBUG
    let fileName = (file as NSString).lastPathComponent
    print("[\(fileName):\(line)] \(function) - \(message)")
    #endif
}
