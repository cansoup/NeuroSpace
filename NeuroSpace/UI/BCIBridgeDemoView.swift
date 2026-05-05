import SwiftUI

struct BCIBridgeDemoView: View {
    @State private var client = BCIWebSocketClient()
    @State private var host: String = Bundle.main.object(forInfoDictionaryKey: "BCI_DEFAULT_HOST") as? String ?? "192.168.1.10"
    @State private var port: String = Bundle.main.object(forInfoDictionaryKey: "BCI_DEFAULT_PORT") as? String ?? "8765"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("BCI Bridge Demo")
                .font(.largeTitle)

            HStack {
                TextField("Python host", text: $host)
                    .textFieldStyle(.roundedBorder)
                TextField("Port", text: $port)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .keyboardType(.numberPad)
            }

            HStack {
                Button("Connect") {
                    client.connect(host: host, port: Int(port) ?? 8765)
                }
                Button("Ping") {
                    client.sendPing()
                }
                Button("Disconnect") {
                    client.disconnect()
                }
                Button("Clear Log") {
                    client.clearLog()
                }
            }

            Text("State: \(String(describing: client.state))")
            Text("Last intent: \(client.lastIntent)")
            Text("Confidence: \(client.lastConfidence.formatted(.number.precision(.fractionLength(2))))")

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(client.logLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 700, minHeight: 500)
    }
}

#Preview {
    BCIBridgeDemoView()
}
