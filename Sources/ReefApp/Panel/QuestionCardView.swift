import ReefCore
import SwiftUI

/// An `AskUserQuestion` card: pick options (or type an answer) and submit back to the agent.
struct QuestionCardView: View {
    @Environment(AppState.self) private var app
    let session: Session
    let request: PendingRequest

    private var questions: [Question] { QuestionAnswer.parse(toolInput: request.event.toolInput ?? [:]) }
    private var selection: QuestionSelection { app.selection(for: request.requestID, questions: questions) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(session: session, badge: "Question", badgeTint: Theme.accent, subtitle: "is asking")
            ForEach(questions, id: \.question) { question in
                VStack(alignment: .leading, spacing: 6) {
                    if !question.header.isEmpty {
                        Text(question.header.uppercased())
                            .font(.system(size: 10, weight: .bold)).tracking(0.8)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(question.question).font(Theme.body.weight(.medium)).foregroundStyle(Theme.textPrimary)
                    FlowOptions(question: question, selection: selection) { label in
                        app.updateSelection(for: request.requestID, questions: questions) {
                            $0.toggle(question: question.question, label: label, multiSelect: question.multiSelect)
                        }
                    }
                    TextField("Or type your own answer", text: Binding(
                        get: { selection.customText(question: question.question) },
                        set: { text in app.updateSelection(for: request.requestID, questions: questions) { $0.setCustom(question: question.question, text: text) } }
                    ))
                    .textFieldStyle(.plain)
                    .font(Theme.body)
                    .padding(8)
                    .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            if request.isLive {
                HStack {
                    Spacer()
                    Button("Submit") { app.answerQuestion(requestID: request.requestID) }
                        .buttonStyle(PanelButtonStyle(role: .primary))
                        .disabled(!selection.canSubmit)
                        .opacity(selection.canSubmit ? 1 : 0.5)
                        .help("⌃↩")
                }
            } else {
                HStack {
                    Label("Waiting in terminal", systemImage: "terminal").font(Theme.small).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button("Jump") { app.jump(session: session) }.buttonStyle(PanelButtonStyle(role: .secondary))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).stroke(Theme.accent.opacity(request.isLive ? 0.5 : 0)))
    }
}

struct FlowOptions: View {
    let question: Question
    let selection: QuestionSelection
    let toggle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(question.options, id: \.label) { option in
                let on = selection.isChosen(question: question.question, label: option.label)
                Button { toggle(option.label) } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: on ? (question.multiSelect ? "checkmark.square.fill" : "largecircle.fill.circle")
                                              : (question.multiSelect ? "square" : "circle"))
                            .foregroundStyle(on ? Theme.accent : Theme.textSecondary)
                            .font(.system(size: 13))
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.label).font(Theme.body.weight(.medium)).foregroundStyle(Theme.textPrimary)
                            if !option.description.isEmpty {
                                Text(option.description).font(Theme.small).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(on ? Theme.accent.opacity(0.15) : Color.black.opacity(0.35),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
