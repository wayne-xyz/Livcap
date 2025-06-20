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
        VStack{
            Text(caption.statusText)
                .frame(minWidth: 600, minHeight: 180)
                
            Text(caption.captionText)
                .frame(minWidth: 600, minHeight:180)
        }
        .onAppear {
            setupCaption()
        }
        
            
    }
            
    
    func setupCaption() {

        if isRunningInPreview()==true{
            debugLog("Caption off when Preview")
            
        }else{
            debugLog("Caption toggle On")
            caption.toggleRecording()
        }
               
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
