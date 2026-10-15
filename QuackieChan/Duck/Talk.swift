import Observation
import SwiftUI

/// The little box you talk to the duck in: type, or press the mic and say it.
@MainActor
@Observable
final class Talk {
    var isOpen = false
    var text = ""
    private(set) var listening = false
    var thinking = false
    var problem: String?

    /// Called with what you said when you send it.
    @ObservationIgnored var onSend: ((String) -> Void)?
    /// Called when listening starts or stops, so the duck can look like it's listening.
    @ObservationIgnored var onListening: ((Bool) -> Void)?

    @ObservationIgnored private let ears = Ears()

    init() {
        ears.onText = { [weak self] heard in self?.text = heard }
        ears.onPause = { [weak self] in
            self?.listening = false
            self?.onListening?(false)
            self?.send()
        }
    }

    func open(listening listen: Bool) {
        isOpen = true
        problem = nil
        if listen { startListening() }
    }

    func close() {
        stopListening()
        isOpen = false
        text = ""
    }

    func send() {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        stopListening()
        guard !said.isEmpty else { return }
        text = ""
        onSend?(said)
    }

    func toggleListening() {
        listening ? stopListening() : startListening()
    }

    private func startListening() {
        guard !listening else { return }
        listening = true
        text = ""
        problem = nil
        onListening?(true)
        Task {
            do {
                try await ears.start()
            } catch {
                listening = false
                onListening?(false)
                problem = error.localizedDescription
            }
        }
    }

    private func stopListening() {
        guard listening else { return }
        listening = false
        ears.stop()
        onListening?(false)
    }
}

struct TalkBox: View {
    @Bindable var talk: Talk
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(action: talk.toggleListening) {
                    Image(systemName: talk.listening ? "waveform" : "mic.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(talk.listening ? .red : .white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(BubbleStyle.tag))
                        .symbolEffect(.variableColor.iterative, isActive: talk.listening)
                }
                .buttonStyle(.plain)
                .help(talk.listening ? "Stop listening" : "Say it out loud")

                TextField(talk.listening ? "Listening…" : "Say something to \(Settings.shared.prefs.duckName)…", text: $talk.text)
                    .textFieldStyle(.plain)
                    .font(.custom(Fonts.display, size: 15))
                    .foregroundStyle(.white)
                    .focused($focused)
                    .onSubmit { talk.send() }

                if talk.thinking {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Button { talk.send() } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 20)).foregroundStyle(BubbleStyle.border)
                    }
                    .buttonStyle(.plain)
                    .disabled(talk.text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let problem = talk.problem {
                Text(problem).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 290)
        .background(RoundedRectangle(cornerRadius: 16).fill(BubbleStyle.fill))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(BubbleStyle.border, lineWidth: 2.5))
        .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
        .onAppear { focused = true }
        .onExitCommand { talk.close() }
    }
}
