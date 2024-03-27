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
                        .foregroundColor(item.isError ? .red : .black)
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
            }
    }
}

#Preview {
    LogView(logItems: {
        let testLog = LogItems()
        testLog.log("Test message")
        testLog.log("Test error", isError: true)
        return testLog
    }())
}
