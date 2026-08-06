import SwiftUI

/// Start → Edit → Review workspace for one agentic loop.
struct ActionLoopWorkspaceView: View {
    @ObservedObject var model: ActionLauncherViewModel
    var onOpenLibrary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            phasePicker

            if let loop = model.selectedLoop {
                switch loop.phase {
                case .start:
                    startPhase(for: loop)
                case .edit:
                    editPhase(for: loop)
                case .review:
                    reviewPhase(for: loop)
                }
            } else if let session = model.selectedSession {
                orphanTakeReview(session)
            } else {
                startEmptyState
            }
        }
    }

    // MARK: - Phase chrome

    private var phasePicker: some View {
        HStack(spacing: 8) {
            ForEach(ActionLoopPhase.allCases) { phase in
                phaseTab(phase)
            }
            Spacer(minLength: 0)
            if let loop = model.selectedLoop {
                Text(loop.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(StageHUDTheme.textMuted)
                    .lineLimit(1)
            }
        }
    }

    private func phaseTab(_ phase: ActionLoopPhase) -> some View {
        let selected = model.selectedLoop?.phase == phase
        let enabled = phaseIsEnabled(phase)

        return Button {
            guard enabled else { return }
            model.setLoopPhase(phase)
        } label: {
            HStack(spacing: 6) {
                Text(phaseNumber(phase))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(selected ? StageHUDTheme.buttonPrimaryText : StageHUDTheme.textMuted)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(selected ? StageHUDTheme.reviewAccent : StageHUDTheme.buttonSecondaryHover)
                    )
                Text(phase.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
            }
            .foregroundStyle(enabled ? (selected ? StageHUDTheme.textPrimary : StageHUDTheme.textSecondary) : StageHUDTheme.textMuted.opacity(0.55))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? StageHUDTheme.buttonSecondaryHover : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected ? StageHUDTheme.reviewAccent.opacity(0.35) : StageHUDTheme.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(phase.subtitle)
    }

    private func phaseNumber(_ phase: ActionLoopPhase) -> String {
        switch phase {
        case .start: return "1"
        case .edit: return "2"
        case .review: return "3"
        }
    }

    private func phaseIsEnabled(_ phase: ActionLoopPhase) -> Bool {
        guard let loop = model.selectedLoop else {
            return phase == .start
        }
        switch phase {
        case .start:
            return true
        case .edit:
            return !loop.steps.isEmpty
        case .review:
            return loop.latestSessionId != nil || !loop.sessionIds.isEmpty
        }
    }

    // MARK: - Start

    private var startEmptyState: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Start a loop")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(StageHUDTheme.textPrimary)

                Text("Draft a scenario, leave plan-level feedback, run it, then review the take. The first closed circuit is Calculator.")
                    .font(.system(size: 13))
                    .foregroundStyle(StageHUDTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                goalField

                HStack(spacing: 10) {
                    Button {
                        model.startCalculatorLoop()
                    } label: {
                        Text("Draft Calculator scenario")
                    }
                    .buttonStyle(ActionSettingsPillButtonStyle(primary: true))
                    .disabled(model.isRunningGuidedDemo)

                    if !model.loops.isEmpty {
                        Menu("Open recent") {
                            ForEach(model.loops) { loop in
                                Button(loop.title) {
                                    model.selectLoop(loop)
                                    model.setLoopPhase(loop.phase == .start ? .edit : loop.phase)
                                }
                            }
                        }
                        .font(.system(size: 12, weight: .medium))
                    }
                }

                Text(model.guidedDemoStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(StageHUDTheme.textMuted)
            }
        }
    }

    private func startPhase(for loop: ActionLoopDocument) -> some View {
        // If a loop already exists, Start still lets you spin another or jump to Edit.
        VStack(alignment: .leading, spacing: 14) {
            card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Active loop")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StageHUDTheme.textMuted)
                    Text(loop.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(StageHUDTheme.textPrimary)
                    Text(loop.goal)
                        .font(.system(size: 13))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                    HStack(spacing: 8) {
                        Button("Continue to Edit") {
                            model.setLoopPhase(.edit)
                        }
                        .buttonStyle(ActionSettingsPillButtonStyle(primary: true))
                        if phaseIsEnabled(.review) {
                            Button("Jump to Review") {
                                model.setLoopPhase(.review)
                            }
                            .buttonStyle(ActionSettingsPillButtonStyle())
                        }
                    }
                }
            }

            card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Start another")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(StageHUDTheme.textPrimary)
                    goalField
                    Button {
                        model.startCalculatorLoop()
                    } label: {
                        Text("Draft new Calculator scenario")
                    }
                    .buttonStyle(ActionSettingsPillButtonStyle(primary: true))
                    .disabled(model.isRunningGuidedDemo)
                }
            }
        }
    }

    private var goalField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Goal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(StageHUDTheme.textMuted)
            TextField("What should this demo show?", text: $model.loopDraftGoal, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...4)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(StageHUDTheme.buttonSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
                )
        }
    }

    // MARK: - Edit

    private func editPhase(for loop: ActionLoopDocument) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Scenario")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(StageHUDTheme.textMuted)
                        Text(loop.goal)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(StageHUDTheme.textPrimary)
                        HStack(spacing: 8) {
                            metaChip(loop.targetAppName)
                            metaChip("\(loop.steps.count) steps")
                            if loop.feedbackCount > 0 {
                                metaChip("\(loop.feedbackCount) notes")
                            }
                        }
                    }
                }

                card {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Steps")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(StageHUDTheme.textMuted)
                            Spacer()
                            Text("Plan-level feedback, not media notes")
                                .font(.system(size: 11))
                                .foregroundStyle(StageHUDTheme.textMuted)
                        }
                        .padding(.bottom, 8)

                        ForEach(loop.steps) { step in
                            stepRow(step, selected: model.selectedLoopStepID == step.id)
                            if step.id != loop.steps.last?.id {
                                Rectangle()
                                    .fill(StageHUDTheme.cardBorder)
                                    .frame(height: 1)
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        model.approveAndRunSelectedLoop()
                    } label: {
                        Text(model.isRunningGuidedDemo ? "Running…" : "Approve & run")
                    }
                    .buttonStyle(ActionSettingsPillButtonStyle(primary: true))
                    .disabled(model.isRunningGuidedDemo)

                    Button("Back to Start") {
                        model.setLoopPhase(.start)
                    }
                    .buttonStyle(ActionSettingsPillButtonStyle())

                    Spacer()

                    Text(model.guidedDemoStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(StageHUDTheme.textMuted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            stepDetailRail(for: loop)
                .frame(width: 300)
        }
    }

    private func stepRow(_ step: ActionLoopScenarioStep, selected: Bool) -> some View {
        Button {
            model.selectLoopStep(step)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text("\(step.index)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(StageHUDTheme.textMuted)
                    .frame(width: 20, alignment: .trailing)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(step.description)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(step.isSkipped ? StageHUDTheme.textMuted : StageHUDTheme.textPrimary)
                            .strikethrough(step.isSkipped)
                        if step.isFlagged {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Color(nsColor: .systemOrange))
                        }
                        if step.isSkipped {
                            Text("Skipped")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(StageHUDTheme.textMuted)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(step.action)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(StageHUDTheme.textMuted)
                        if let target = step.targetSummary {
                            Text("· \(target)")
                                .font(.system(size: 11))
                                .foregroundStyle(StageHUDTheme.textMuted)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? StageHUDTheme.buttonSecondaryHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func stepDetailRail(for loop: ActionLoopDocument) -> some View {
        let step = model.selectedLoopStep

        return card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Step feedback")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StageHUDTheme.textMuted)

                if let step {
                    Text(step.description)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(StageHUDTheme.textPrimary)
                    Text("Tell the agent what to change about this step before the next run.")
                        .font(.system(size: 12))
                        .foregroundStyle(StageHUDTheme.textSecondary)

                    TextField("e.g. Wait for Calculator to finish opening", text: $model.loopStepFeedbackDraft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(3...6)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(StageHUDTheme.buttonSecondary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
                        )

                    HStack(spacing: 8) {
                        Button("Add feedback") {
                            model.addFeedbackToSelectedLoopStep()
                        }
                        .buttonStyle(ActionSettingsPillButtonStyle(primary: true))
                        .disabled(model.loopStepFeedbackDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button(step.isSkipped ? "Include step" : "Skip step") {
                            model.toggleSkipLoopStep(step.id)
                        }
                        .buttonStyle(ActionSettingsPillButtonStyle())
                    }

                    if !step.feedback.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes on this step")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(StageHUDTheme.textMuted)
                            ForEach(step.feedback) { item in
                                Text(item.instruction)
                                    .font(.system(size: 12))
                                    .foregroundStyle(StageHUDTheme.textPrimary)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(StageHUDTheme.reviewAccentMuted.opacity(0.55))
                                    )
                            }
                        }
                    }
                } else {
                    Text("Select a step to leave plan feedback.")
                        .font(.system(size: 12))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Review

    private func reviewPhase(for loop: ActionLoopDocument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            card {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Take from this loop")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(StageHUDTheme.textMuted)
                        if let session = sessionForLoop(loop) {
                            Text(session.displayTitle)
                                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                                .foregroundStyle(StageHUDTheme.textPrimary)
                            Text("= \(session.actualResult)  ·  \(session.feedbackCount) media notes")
                                .font(.system(size: 12))
                                .foregroundStyle(StageHUDTheme.textSecondary)
                        } else {
                            Text("No take linked yet — run the scenario from Edit.")
                                .font(.system(size: 13))
                                .foregroundStyle(StageHUDTheme.textSecondary)
                        }
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button("Edit scenario") {
                            model.setLoopPhase(.edit)
                        }
                        .buttonStyle(ActionSettingsPillButtonStyle())
                        Button {
                            model.approveAndRunSelectedLoop()
                        } label: {
                            Text(model.isRunningGuidedDemo ? "Running…" : "Run again")
                        }
                        .buttonStyle(ActionSettingsPillButtonStyle(primary: true))
                        .disabled(model.isRunningGuidedDemo)
                        Button("Library") {
                            onOpenLibrary()
                        }
                        .buttonStyle(ActionSettingsPillButtonStyle())
                    }
                }
            }

            if let session = sessionForLoop(loop) {
                ActionSessionPreviewView(session: session, model: model)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
                    )
            } else {
                card {
                    Text("Approve & run from Edit to produce a reviewable take.")
                        .font(.system(size: 13))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                }
            }
        }
    }

    private func sessionForLoop(_ loop: ActionLoopDocument) -> ActionSessionSummary? {
        if let latest = loop.latestSessionId,
           let session = model.recentSessions.first(where: { $0.sessionId == latest || $0.id == latest }) {
            return session
        }
        for id in loop.sessionIds {
            if let session = model.recentSessions.first(where: { $0.sessionId == id || $0.id == id }) {
                return session
            }
        }
        return model.selectedSession
    }

    private func orphanTakeReview(_ session: ActionSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Take without a loop")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StageHUDTheme.textMuted)
                    Text(session.displayTitle)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    Text("Start a Calculator loop to get Start → Edit → Review. This take is still reviewable.")
                        .font(.system(size: 12))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                    Button("New Calculator loop") {
                        model.startCalculatorLoop()
                    }
                    .buttonStyle(ActionSettingsPillButtonStyle(primary: true))
                }
            }
            ActionSessionPreviewView(session: session, model: model)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
                )
        }
    }

    // MARK: - Shared chrome

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(StageHUDTheme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(StageHUDTheme.buttonSecondaryHover)
            )
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(StageHUDTheme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
            )
    }
}
