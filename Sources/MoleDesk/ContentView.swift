import SwiftUI

struct ContentView: View {
    @State private var molePath: String?
    @State private var isRunning = false
    @State private var selectedAction: MoleAction = .status
    @State private var output = "Welcome to SweepDock.\n\nClick Refresh to detect Mole CLI, then run a safe preview."
    @State private var lastCommand = ""
    @State private var exitCode: Int32?
    @State private var showingCleanConfirmation = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .task {
            refreshMole()
        }
        .confirmationDialog(
            "Run real cleanup?",
            isPresented: $showingCleanConfirmation,
            titleVisibility: .visible
        ) {
            Button("Run mo clean", role: .destructive) {
                run(.cleanNow)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Preview first with Dry Run. Real cleanup may permanently delete caches, logs, and generated files.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SweepDock")
                    .font(.largeTitle.bold())
                Text("A small native wrapper for Mole CLI.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            statusCard

            Divider()

            VStack(spacing: 10) {
                ForEach(MoleAction.primaryActions) { action in
                    actionButton(action)
                }
            }

            Spacer()

            Button {
                refreshMole()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(isRunning)
        }
        .padding(22)
        .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 360)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: molePath == nil ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .foregroundStyle(molePath == nil ? .orange : .green)
                Text(molePath == nil ? "Mole CLI missing" : "Mole CLI ready")
                    .font(.headline)
            }

            Text(molePath ?? "Install with: brew install mole")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    private var detail: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                Text(output)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(22)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedAction.title)
                    .font(.title2.bold())
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            Spacer()

            if isRunning {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                if selectedAction == .cleanNow {
                    showingCleanConfirmation = true
                } else {
                    run(selectedAction)
                }
            } label: {
                Label(selectedAction.runLabel, systemImage: selectedAction.icon)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRunning)
        }
        .padding(18)
    }

    private var statusLine: String {
        if isRunning {
            return "Running \(selectedAction.commandPreview)"
        }
        if let exitCode {
            return "\(lastCommand) exited with code \(exitCode)"
        }
        return "No command has run yet."
    }

    private func actionButton(_ action: MoleAction) -> some View {
        Button {
            selectedAction = action
            if action == .cleanNow {
                showingCleanConfirmation = true
            } else {
                run(action)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: action.icon)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.headline)
                    Text(action.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .padding(10)
        .background(selectedAction == action ? .selection.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .disabled(isRunning)
    }

    private func refreshMole() {
        molePath = MoleRunner.locateMole()
        exitCode = nil
        lastCommand = ""
        if molePath == nil {
            output = """
            Mole CLI was not detected.

            Install it with Homebrew:
              brew install mole

            SweepDock intentionally calls the official CLI instead of reimplementing cleanup logic.
            """
        }
    }

    private func run(_ action: MoleAction) {
        selectedAction = action
        isRunning = true
        output = "Running \(action.commandPreview)..."
        exitCode = nil

        Task {
            let result = await MoleRunner.runMole(arguments: action.arguments)
            await MainActor.run {
                lastCommand = result.command
                exitCode = result.exitCode
                output = """
                $ \(result.command)

                \(result.output)
                """
                molePath = MoleRunner.locateMole()
                isRunning = false
            }
        }
    }
}

enum MoleAction: String, CaseIterable, Identifiable {
    case status
    case analyze
    case cleanPreview
    case cleanNow
    case help

    var id: String { rawValue }

    static let primaryActions: [MoleAction] = [.status, .analyze, .cleanPreview, .cleanNow, .help]

    var title: String {
        switch self {
        case .status: "System Status"
        case .analyze: "Disk Analyze"
        case .cleanPreview: "Cleanup Preview"
        case .cleanNow: "Run Cleanup"
        case .help: "Mole Help"
        }
    }

    var subtitle: String {
        switch self {
        case .status: "Show machine and storage overview"
        case .analyze: "Find large folders and files"
        case .cleanPreview: "Dry-run only, no deletion"
        case .cleanNow: "Requires confirmation"
        case .help: "Show available CLI commands"
        }
    }

    var icon: String {
        switch self {
        case .status: "gauge.with.dots.needle.50percent"
        case .analyze: "chart.bar.xaxis"
        case .cleanPreview: "eye"
        case .cleanNow: "trash"
        case .help: "questionmark.circle"
        }
    }

    var runLabel: String {
        switch self {
        case .cleanNow: "Confirm"
        default: "Run"
        }
    }

    var arguments: [String] {
        switch self {
        case .status: ["status"]
        case .analyze: ["analyze"]
        case .cleanPreview: ["clean", "--dry-run"]
        case .cleanNow: ["clean"]
        case .help: ["--help"]
        }
    }

    var commandPreview: String {
        "mo \(arguments.joined(separator: " "))"
    }
}
