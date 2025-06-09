//
//  CaptionView.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/8/25.
//
import SwiftUI


struct CaptionView: View {
    
    @StateObject private var caption = CaptionViewModel()
    
    var body: some View {
        
        Text("Caption View")
            .frame(minWidth: 600, minHeight: 180)
            
    }
        
}


#Preview("Dark Mode") {
    CaptionView()
        .preferredColorScheme(.dark)
}


#Preview("Light Mode") {
    CaptionView()
        .preferredColorScheme(.light)
}
