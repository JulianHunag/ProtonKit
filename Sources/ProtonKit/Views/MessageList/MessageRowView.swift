import SwiftUI
import ProtonCore

struct MessageRowView: View {
    let message: MessageMetadata
    var isMultiSelected = false
    var onTrash: (() -> Void)?
    var onTrashSelected: (() -> Void)?
    var onToggleUnread: (() -> Void)?
    var onToggleUnreadSelected: (() -> Void)?
    var onReply: (() -> Void)?
    var onReplyAll: (() -> Void)?
    var onForward: (() -> Void)?

    private var senderDisplay: String {
        message.senderName.isEmpty ? message.senderAddress : message.senderName
    }

    private var isUnread: Bool { message.unread == 1 }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AvatarView(name: senderDisplay, size: 32)
                .overlay(alignment: .topLeading) {
                    if isUnread {
                        Circle()
                            .fill(.blue)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle().stroke(.background, lineWidth: 2)
                            )
                            .offset(x: -2, y: -2)
                    }
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(senderDisplay)
                        .font(isUnread ? .body.bold() : .body)
                        .foregroundStyle(isUnread ? .primary : .secondary)
                        .lineLimit(1)

                    Spacer()

                    if message.numAttachments > 0 {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Text(formatDate(message.date))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Text(message.subject)
                    .font(.subheadline)
                    .foregroundStyle(isUnread ? .primary : .tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if !isMultiSelected {
                Button(action: { onReply?() }) {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
                Button(action: { onReplyAll?() }) {
                    Label("Reply All", systemImage: "arrowshape.turn.up.left.2")
                }
                Button(action: { onForward?() }) {
                    Label("Forward", systemImage: "arrowshape.turn.up.right")
                }
                Divider()
            }
            Button(action: {
                if isMultiSelected { onToggleUnreadSelected?() } else { onToggleUnread?() }
            }) {
                Label(
                    message.unread == 1 ? "Mark as Read" : "Mark as Unread",
                    systemImage: message.unread == 1 ? "envelope.open" : "envelope.badge"
                )
            }
            Divider()
            Button(role: .destructive, action: {
                if isMultiSelected { onTrashSelected?() } else { onTrash?() }
            }) {
                Label("Move to Trash", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: { onTrash?() }) {
                Label("Trash", systemImage: "trash")
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        } else {
            return date.formatted(.dateTime.year().month(.abbreviated).day())
        }
    }
}
