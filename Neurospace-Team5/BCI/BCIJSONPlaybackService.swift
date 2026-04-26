import Foundation

@MainActor
final class BCIJSONPlaybackService {

    private let controller: BubbleGameController

    private var timer: Timer?
    private var messages: [BCIPredictionMessage] = []
    private var currentIndex = 0

    private let confidenceThreshold: Double = 0.75

    init(controller: BubbleGameController) {
        self.controller = controller
    }

    func loadJSON(named resourceName: String) {
        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: "json"
        ) else {
            print("Could not find \(resourceName).json")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            messages = try JSONDecoder().decode(
                [BCIPredictionMessage].self,
                from: data
            )

            currentIndex = 0
            print("Loaded \(messages.count) BCI prediction messages")
        } catch {
            print("JSON decode failed: \(error)")
            messages = []
        }
    }

    func startPlayback(interval: TimeInterval = 0.25) {
        stopPlayback()

        if messages.isEmpty {
            loadJSON(named: "bci_test_data")
        }

        guard !messages.isEmpty else {
            print("No BCI prediction messages available")
            return
        }

        timer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }

            Task { @MainActor in
                self.playNext()
            }
        }
    }

    func stopPlayback() {
        timer?.invalidate()
        timer = nil
        controller.stopMotion()
    }

    private func playNext() {
        guard !messages.isEmpty else { return }

        if currentIndex >= messages.count {
            currentIndex = 0
        }

        let message = messages[currentIndex]
        currentIndex += 1

        route(message)
    }

    private func route(_ message: BCIPredictionMessage) {
        guard message.type == "prediction" else {
            print("Ignored non-prediction message")
            return
        }

        guard message.aboveThreshold else {
            print("Prediction below threshold")
            controller.stopMotion()
            return
        }

        guard message.confidence >= confidenceThreshold else {
            print("Prediction confidence too low: \(message.confidence)")
            controller.stopMotion()
            return
        }

        print("Applying prediction: \(message.predictedClass.rawValue)")
        controller.applyPredictionClass(message.predictedClass)
    }
}
