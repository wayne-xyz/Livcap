//
//  CaptionEntry.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/24/25.
//
import Foundation

/// Simplified caption entry for clean display
struct CaptionEntry: Identifiable {
    let id: UUID
    let text: String
    let confidence: Float? // Optional confidence score
    
    init(id: UUID, text: String, confidence: Float? = nil) {
        self.id = id
        self.text = text
        self.confidence = confidence
    }
}
