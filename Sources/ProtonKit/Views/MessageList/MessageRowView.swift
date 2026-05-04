import SwiftUI
import ProtonCore

struct MessageRowView: View {
    let message: MessageMetadata

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.unread == 1 {
                Circle()
                    .fill(.purple)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            } else {
                Circle()
                    .fill(.clear)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.senderName.isEmpty ? message.senderAddress : message.senderName)
                        .font(message.unread == 1 ? .body.bold() : .body)
                        .lineLimit(1)

                    Spacer()

                    Text(formatDate(message.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(message.subject)
                    .font(.subheadline)
                    .foregroundStyle(message.unread == 1 ? .primary : .secondary)
                    .lineLimit(1)

                if message.numAttachments > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                        Text("\(message.numAttachments)")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
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
