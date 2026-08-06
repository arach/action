import SwiftUI

/// Scenarios workspace: list + plan / last take.
/// Start → Edit → Review is inherent — not labeled wizard chrome.
struct ActionWorkspaceView: View {
    @ObservedObject var model: ActionLauncherViewModel
    var onOpenLibrary: () -> Void

    var body: some View {
        Group {
            if model.scenarios.isEmpty {
                emptyState
            } else {
                HStack(alignment: .top, spacing: 16) {
                    scenarioList
                        .frame(width: 240)

                    detail
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    // MARK: - List

    private var scenarioList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scenarios")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(StageHUDTheme.textMuted)
                .textCase(.uppercase)

            VStack(spacing: 4) {
                ForEach(model.scenarios) { scenario in
                    scenarioRow(scenario)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func scenarioRow(_ scenario: ActionScenarioDocument) -> some View {
        let selected = model.selectedScenarioID == scenario.id
        return Button {
            model.selectScenario(scenario)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(scenario.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StageHUDTheme.textPrimary)
                    .lineLimit(1)
                Text(scenario.goal)
                    .font(.system(size: 11))
                    .foregroundStyle(StageHUDTheme.textMuted)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text("\(scenario.steps.count) steps")
                    if scenario.latestSessionId != nil {
                        Text("·")
                        Text("Has take")
                    }
                    if scenario.feedbackCount > 0 {
                        Text("·")
                        Text("\(scenario.feedbackCount) notes")
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(StageHUDTheme.textMuted)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? StageHUDTheme.buttonSecondaryHover : StageHUDTheme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? StageHUDTheme.reviewAccent.opacity(0.4) : StageHUDTheme.cardBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let scenario = model.selectedScenario {
            VStack(alignment: .leading, spacing: 14) {
                detailHeader(for: scenario)

                if hasTake(scenario), scenario.phase == .review {
                    takeDetail(for: scenario)
                } else {
                    planDetail(for: scenario)
                }
            }
        } else if let session = model.selectedSession {
            orphanTakeReview(session)
        } else {
            emptyState
        }
    }

    private func detailHeader(for scenario: ActionScenarioDocument) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scenario.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(StageHUDTheme.textPrimary)
                    Text(scenario.goal)
                        .font(.system(size: 13))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    Button {
                        model.approveAndRunSelectedScenario()
                    } label: {
                        Text(model.isRunningGuidedDemo ? "Running…" : "Run")
                    }
                    .buttonStyle(ActionSettingsPillButtonStyle(primary: true))
                    .disabled(model.isRunningGuidedDemo)

                    if hasTake(scenario) {
                        Button(scenario.phase == .review ? "Plan" : "Last take") {
                            model.setFlowPhase(scenario.phase == .review ? .edit : .review)
                        }
                        .buttonStyle(ActionSettingsPillButtonStyle())
                    }
                }
            }

            HStack(spacing: 8) {
                metaChip(scenario.targetAppName)
                metaChip("\(scenario.steps.count) steps")
                if let status = scenario.lastRunStatus {
                    metaChip(status.capitalized)
                }
                Spacer()
                Text(model.guidedDemoStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(StageHUDTheme.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: - Plan

    private func planDetail(for scenario: ActionScenarioDocument) -> some View {
        HStack(alignment: .top, spacing: 14) {
            card {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Plan")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StageHUDTheme.textMuted)
                        .padding(.bottom, 8)

                    ForEach(scenario.steps) { step in
                        stepRow(step, selected: model.selectedScenarioStepID == step.id)
                        if step.id != scenario.steps.last?.id {
                            Rectangle()
                                .fill(StageHUDTheme.cardBorder)
                                .frame(height: 1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            stepDetailRail
                .frame(width: 280)
        }
    }

    private func stepRow(_ step: ActionScenarioStep, selected: Bool) -> some View {
        Button {
            model.selectScenarioStep(step)
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

    private var stepDetailRail: some View {
        let step = model.selectedScenarioStep

        return card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Step notes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StageHUDTheme.textMuted)

                if let step {
                    Text(step.description)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(StageHUDTheme.textPrimary)
                    Text("Feedback on the plan — not on the video.")
                        .font(.system(size: 12))
                        .foregroundStyle(StageHUDTheme.textSecondary)

                    TextField("e.g. Wait for Calculator to finish opening", text: $model.scenarioStepFeedbackDraft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(3...5)
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
                        Button("Add note") {
                            model.addFeedbackToSelectedScenarioStep()
                        }
                        .buttonStyle(ActionSettingsPillButtonStyle(primary: true))
                        .disabled(model.scenarioStepFeedbackDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button(step.isSkipped ? "Include" : "Skip") {
                            model.toggleSkipScenarioStep(step.id)
                        }
                        .buttonStyle(ActionSettingsPillButtonStyle())
                    }

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
                } else {
                    Text("Select a step.")
                        .font(.system(size: 12))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Take

    private func takeDetail(for scenario: ActionScenarioDocument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let session = sessionForScenario(scenario) {
                ActionSessionPreviewView(session: session, model: model)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
                    )
            } else {
                card {
                    Text("No take on disk for this scenario yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                    Button("Run") {
                        model.approveAndRunSelectedScenario()
                    }
                    .buttonStyle(ActionSettingsPillButtonStyle(primary: true))
                }
            }
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text("No scenarios yet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(StageHUDTheme.textPrimary)

                Text("A scenario is the plan. Run it to get a take. Leave notes on steps before the next run, or on the video after.")
                    .font(.system(size: 13))
                    .foregroundStyle(StageHUDTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                goalField

                Button {
                    model.startCalculatorScenario()
                } label: {
                    Text("New Calculator scenario")
                }
                .buttonStyle(ActionSettingsPillButtonStyle(primary: true))
                .disabled(model.isRunningGuidedDemo)

                Text(model.guidedDemoStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(StageHUDTheme.textMuted)
            }
        }
    }

    private var goalField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Goal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(StageHUDTheme.textMuted)
            TextField("What should this demo show?", text: $model.scenarioDraftGoal, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...3)
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

    private func orphanTakeReview(_ session: ActionSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            card {
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.displayTitle)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    Text("This take isn’t attached to a scenario.")
                        .font(.system(size: 12))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                    Button("New Calculator scenario") {
                        model.startCalculatorScenario()
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

    // MARK: - Helpers

    private func hasTake(_ scenario: ActionScenarioDocument) -> Bool {
        scenario.latestSessionId != nil || !scenario.sessionIds.isEmpty
    }

    private func sessionForScenario(_ scenario: ActionScenarioDocument) -> ActionSessionSummary? {
        if let latest = scenario.latestSessionId,
           let session = model.recentSessions.first(where: { $0.sessionId == latest || $0.id == latest }) {
            return session
        }
        for id in scenario.sessionIds {
            if let session = model.recentSessions.first(where: { $0.sessionId == id || $0.id == id }) {
                return session
            }
        }
        return model.selectedSession
    }

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

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(StageHUDTheme.cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
            )
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
    }
}
