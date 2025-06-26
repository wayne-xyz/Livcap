import SwiftUI

enum ButtonImage {
    case custom(String)
    case system(String)
}

struct CircularControlButton: View {
    let image: ButtonImage
    let helpText: String
    let isActive: Bool
    let action: () -> Void

    @State private var isButtonHovering = false

    var body: some View {
        Button(action: action) {
            Group {
                switch image {
                case .custom(let name):
                    Image(name)
                case .system(let name):
                    Image(systemName: name)
                }
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(isActive ? .primary : .secondary)
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .opacity(isButtonHovering ? 1 : 0.5)
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .help(helpText)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isButtonHovering = hovering
            }
        }
    }
}

#Preview("Light Mode") {
    HStack(spacing: 20) {
        CircularControlButton(
            image: .system("mic.fill"),
            helpText: "Microphone Active",
            isActive: true,
            action: {}
        )
        
        CircularControlButton(
            image: .custom("laptop.wave"), // Example of a custom image
            helpText: "Custom Image",
            isActive: true,
            action: {}
        )
    }
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    HStack(spacing: 20) {
        CircularControlButton(
            image: .system("mic.slash.fill"),
            helpText: "Microphone Inactive",
            isActive: false,
            action: {}
        )
        
        CircularControlButton(
            image: .system("pin.fill"),
            helpText: "Pinned",
            isActive: true,
            action: {}
        )
    }
    .padding()
    .preferredColorScheme(.dark)
}
