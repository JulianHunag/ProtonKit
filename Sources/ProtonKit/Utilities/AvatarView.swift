import SwiftUI

struct AvatarView: View {
    let name: String
    let size: CGFloat

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first {
            return String(first).uppercased()
        }
        return "?"
    }

    private static let palette: [Color] = [
        .blue, .purple, .pink, .orange, .teal,
        .cyan, .indigo, .mint, .brown, .green,
    ]

    private var color: Color {
        let hash = name.lowercased().unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return Self.palette[abs(hash) % Self.palette.count]
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.gradient)
                .frame(width: size, height: size)
            Text(initial)
                .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}
