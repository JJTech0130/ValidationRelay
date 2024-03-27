//
//  LogView.swift
//  ValidationRelay
//
//  Created by James Gill on 3/26/24.
//

import SwiftUI

struct LogItem: Identifiable, Hashable {
    var id = UUID()
    var message: String
    var isError: Bool
    var date: Date
}

class LogItems: ObservableObject {
    @Published var items: [LogItem] = []
    
    func log(_ message: String, isError: Bool = false) {
        let item = LogItem(message: message, isError: isError, date: Date())
        items.append(item)
    }
}

struct LogView: View {
    @ObservedObject var logItems: LogItems
    
    var body: some View {
        List {
            ForEach(logItems.items, id: \.self) { item in
                HStack {
                    Text(item.message)
                        .foregroundColor(item.isError ? .red : .primary)
                        .lineLimit(4)
                    Spacer()
                    Text(item.date, style: .time)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }.listStyle(.grouped)
            .navigationTitle("Event Log")
            // Clear log button
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") {
                        logItems.items = []
                    }
                }
                // Export log button
                ToolbarItem(placement: .navigationBarTrailing) {
                    // Pop up a share sheet, use share sheet icon for button
                    Button(action: {
                        // Create a string of the log items
                        let logString = logItems.items.map { item in
                            "\(item.date): \(item.message)"
                        }.joined(separator: "\n")
                        let av = UIActivityViewController(activityItems: [logString], applicationActivities: nil)
                        UIApplication.shared.windows.first?.rootViewController?.present(av, animated: true, completion: nil)
                    }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
    }
}

#Preview {
    NavigationView {
        LogView(logItems: {
            let testLog = LogItems()
            testLog.log("Test message")
            testLog.log("Test error", isError: true)
            return testLog
        }())
    }
}
