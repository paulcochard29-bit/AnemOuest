import SwiftUI

struct SettingsView: View {

    @Binding var refreshInterval: TimeInterval

    let intervals: [(String, TimeInterval)] = [
        ("5 secondes", 5),
        ("10 secondes", 10),
        ("20 secondes", 20),
        ("30 secondes", 30),
        ("1 minute", 60),
        ("2 minutes", 120),
        ("5 minutes", 300)
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Actualisation des capteurs") {
                    ForEach(intervals, id: \.1) { label, value in
                        HStack {
                            Text(label)
                            Spacer()
                            if refreshInterval == value {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            refreshInterval = value
                        }
                    }
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
