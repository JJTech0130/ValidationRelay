//
//  ContentView.swift
//  ValidationRelay
//
//  Created by James Gill on 3/24/24.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                //.foregroundStyle(.tint)
            Text("Hello, world!")
        }
        .padding()
        .onAppear {
            test()
        }
    }
}

#Preview {
    ContentView()
}
