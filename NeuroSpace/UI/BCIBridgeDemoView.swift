import SwiftUI

struct BCIBridgeDemoView: View {
    @State private var client = BCIWebSocketClient()

    private static let defaultHost: String =
        Bundle.main.object(forInfoDictionaryKey: "BCI_DEFAULT_HOST") as? String
        ?? "192.168.1.10"
    private static let defaultPort: String =
        Bundle.main.object(forInfoDictionaryKey: "BCI_DEFAULT_PORT") as? String
        ?? "8765"

    @AppStorage("bci.host") private var host: String = Self.defaultHost
    @AppStorage("bci.port") private var port: String = Self.defaultPort
    @AppStorage("bci.autoConnect") private var autoConnect: Bool = true

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
                Button("Use Default") {
                    host = Self.defaultHost
                    port = Self.defaultPort
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

            Toggle("Auto-connect on launch", isOn: $autoConnect)
                .toggleStyle(.switch)

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
        .onAppear {
            guard autoConnect else { return }
            client.connect(host: host, port: Int(port) ?? 8765)
        }
    }
}

#Preview {
    BCIBridgeDemoView()
}
