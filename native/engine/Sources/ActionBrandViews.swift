import AppKit
import SwiftUI

struct ActionLatticeLogoMark: View {
    var size: CGFloat = 36
    var accent: Color = StageHUDTheme.reviewAccent

    var body: some View {
        Canvas { context, canvasSize in
            let minSide = min(canvasSize.width, canvasSize.height)
            let inset = minSide * 0.22
            let nodeRadius = minSide * 0.035
            let points = [
                CGPoint(x: inset, y: inset),
                CGPoint(x: canvasSize.width * 0.50, y: inset),
                CGPoint(x: canvasSize.width - inset, y: inset),
                CGPoint(x: inset, y: canvasSize.height * 0.50),
                CGPoint(x: canvasSize.width * 0.50, y: canvasSize.height * 0.50),
                CGPoint(x: canvasSize.width - inset, y: canvasSize.height * 0.50),
                CGPoint(x: inset, y: canvasSize.height - inset),
                CGPoint(x: canvasSize.width * 0.50, y: canvasSize.height - inset),
                CGPoint(x: canvasSize.width - inset, y: canvasSize.height - inset),
            ]

            var lattice = Path()
            let edges = [
                (0, 1), (1, 2), (3, 4), (4, 5), (6, 7), (7, 8),
                (0, 3), (3, 6), (1, 4), (4, 7), (2, 5), (5, 8),
                (0, 4), (4, 8), (2, 4), (4, 6),
            ]
            for edge in edges {
                lattice.move(to: points[edge.0])
                lattice.addLine(to: points[edge.1])
            }
            context.stroke(lattice, with: .color(accent.opacity(0.24)), lineWidth: max(1, minSide * 0.018))

            var route = Path()
            route.move(to: points[6])
            route.addLine(to: points[4])
            route.addLine(to: points[2])
            route.move(to: points[3])
            route.addLine(to: points[4])
            route.addLine(to: points[5])
            context.stroke(
                route,
                with: .color(StageHUDTheme.textPrimary.opacity(0.92)),
                style: StrokeStyle(lineWidth: max(2, minSide * 0.07), lineCap: .round, lineJoin: .round)
            )

            for (index, point) in points.enumerated() {
                let isRouteNode = [2, 3, 4, 5, 6].contains(index)
                let rect = CGRect(
                    x: point.x - nodeRadius,
                    y: point.y - nodeRadius,
                    width: nodeRadius * 2,
                    height: nodeRadius * 2
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(isRouteNode ? accent : StageHUDTheme.textMuted.opacity(0.34))
                )
            }
        }
        .frame(width: size, height: size)
        .background(
            ActionChamferedShape(cornerCut: max(4, size * 0.14))
                .fill(StageHUDTheme.reviewAccentMuted.opacity(0.58))
        )
        .overlay(
            ActionChamferedShape(cornerCut: max(4, size * 0.14))
                .stroke(StageHUDTheme.reviewAccent.opacity(0.34), lineWidth: 1)
        )
    }
}

struct ActionBrandLockup: View {
    var body: some View {
        HStack(spacing: 10) {
            ActionLatticeLogoMark(size: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text("Action")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(StageHUDTheme.textPrimary)
                Text("Capture workstation")
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(StageHUDTheme.textMuted)
            }
        }
    }
}

struct MiraSpriteView: View {
    var state: String = "idle"
    var width: CGFloat = 58
    var height: CGFloat = 64

    var body: some View {
        ActionCharacterSpriteView(treatmentID: "mira", state: state, width: width, height: height)
    }
}

struct ActionCharacterSpriteView: View {
    var treatmentID: String = "mira"
    var state: String = "idle"
    var width: CGFloat = 58
    var height: CGFloat = 64

    private var petID: String {
        ActionCharacterTreatmentRegistry.shared.petID(for: treatmentID) ?? treatmentID
    }

    private var sheetState: String {
        ActionCharacterTreatmentRegistry.shared.sheetState(for: treatmentID, logicalState: state)
    }

    private var scale: CGFloat {
        ActionCharacterTreatmentRegistry.shared.scale(for: treatmentID)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            ActionPetSpriteFrameView(petID: petID, state: sheetState, date: timeline.date)
        }
        .scaleEffect(scale)
        .frame(width: width, height: height)
        .accessibilityLabel(ActionCharacterTreatmentRegistry.shared.displayName(for: treatmentID))
    }
}

struct MiraCompanionBadge: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                ActionLatticeLogoMark(size: 46)
                    .opacity(0.58)
                MiraSpriteView(state: "idle", width: 44, height: 48)
                    .offset(y: 3)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 3) {
                Text("Mira")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(StageHUDTheme.textPrimary)
                Text("Lattice guide")
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(StageHUDTheme.textMuted)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            ActionChamferedShape(cornerCut: 6)
                .fill(StageHUDTheme.cardFill.opacity(0.76))
        )
        .overlay(
            ActionChamferedShape(cornerCut: 6)
                .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
        )
    }
}

private struct ActionPetSpriteFrameView: NSViewRepresentable {
    let petID: String
    let state: String
    let date: Date

    func makeNSView(context: Context) -> ActionPetSpriteNSView {
        let view = ActionPetSpriteNSView()
        view.petID = petID
        view.state = state
        view.frameDate = date
        return view
    }

    func updateNSView(_ nsView: ActionPetSpriteNSView, context: Context) {
        nsView.petID = petID
        nsView.state = state
        nsView.frameDate = date
        nsView.needsDisplay = true
    }
}

private final class ActionPetSpriteNSView: NSView {
    var petID: String = "mira"
    var state: String = "idle"
    var frameDate: Date = Date()

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        guard let frame = ActionPetAssetCache.shared.frame(for: petID, state: state, date: frameDate) else {
            drawFallback()
            return
        }

        frame.image.draw(
            in: bounds,
            from: frame.sourceRect,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    private func drawFallback() {
        let symbol = NSImage(systemSymbolName: "sparkle.magnifyingglass", accessibilityDescription: "Mira")
        symbol?.draw(in: bounds.insetBy(dx: bounds.width * 0.16, dy: bounds.height * 0.16))
    }
}

@MainActor
private final class ActionPetAssetCache {
    static let shared = ActionPetAssetCache()

    struct Frame {
        let image: NSImage
        let sourceRect: CGRect
    }

    private struct Metadata: Decodable {
        struct State: Decodable {
            let row: Int
            let frames: Int
            let frameWidth: CGFloat
            let frameHeight: CGFloat
            let fps: Double?
        }

        let inherits: String?
        let spritesheetPath: String?
        let states: [String: State]?
    }

    private struct LoadedPet {
        let root: URL
        let image: NSImage
        let pixelSize: CGSize
        let metadata: Metadata?
    }

    private var cache: [String: LoadedPet] = [:]

    private init() {}

    func frame(for petID: String, state requestedState: String?, date: Date) -> Frame? {
        guard let asset = load(petID: petID) else {
            return nil
        }

        let state = requestedState.flatMap { asset.metadata?.states?[$0] }
            ?? asset.metadata?.states?["idle"]
            ?? Metadata.State(row: 0, frames: 1, frameWidth: 192, frameHeight: 208, fps: 8)
        let frameWidth = max(1, state.frameWidth)
        let frameHeight = max(1, state.frameHeight)
        let frameCount = max(1, state.frames)
        let frameRate = max(1, state.fps ?? 8)
        let frameIndex = Int(date.timeIntervalSinceReferenceDate * frameRate) % frameCount
        let row = max(0, state.row)
        let maxX = max(0, asset.pixelSize.width - frameWidth)
        let y = max(0, asset.pixelSize.height - CGFloat(row + 1) * frameHeight)

        return Frame(
            image: asset.image,
            sourceRect: CGRect(
                x: min(CGFloat(frameIndex) * frameWidth, maxX),
                y: y,
                width: frameWidth,
                height: frameHeight
            )
        )
    }

    private func load(petID: String) -> LoadedPet? {
        if let cached = cache[petID] {
            return cached
        }

        guard petID.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil,
              let root = petRoot(petID: petID) else {
            return nil
        }

        let metadataURL = root.appendingPathComponent("pet.json")
        let metadata = try? JSONDecoder().decode(Metadata.self, from: Data(contentsOf: metadataURL))
        let spritesheetURL = resolveSpritesheetURL(
            root: root,
            petID: petID,
            inherits: metadata?.inherits,
            spritesheetPath: metadata?.spritesheetPath ?? "spritesheet.webp"
        )
        guard let image = NSImage(contentsOf: spritesheetURL),
              let representation = image.representations.first else {
            return nil
        }

        let loaded = LoadedPet(
            root: root,
            image: image,
            pixelSize: CGSize(width: representation.pixelsWide, height: representation.pixelsHigh),
            metadata: metadata
        )
        cache[petID] = loaded
        return loaded
    }

    private func petRoot(petID: String) -> URL? {
        for petsRoot in petRoots() {
            let root = petsRoot.appendingPathComponent(petID)
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("pet.json").path) {
                return root
            }
        }
        return nil
    }

    private func petRoots() -> [URL] {
        var roots = [
            Bundle.main.resourceURL?.appendingPathComponent("Pets"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Pets"),
            sourcePackageRoot()?.appendingPathComponent("Resources/Pets"),
            sourceRepoRoot()?.appendingPathComponent("assets/pets"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("native/engine/Resources/Pets"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("assets/pets"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/pets"),
        ].compactMap { $0 }

        var seen = Set<String>()
        roots.removeAll { root in
            let path = root.standardizedFileURL.path
            if seen.contains(path) {
                return true
            }
            seen.insert(path)
            return false
        }
        return roots
    }

    private func resolveSpritesheetURL(
        root: URL,
        petID: String,
        inherits: String?,
        spritesheetPath: String
    ) -> URL {
        let bundledURL = root.appendingPathComponent(spritesheetPath)
        if FileManager.default.fileExists(atPath: bundledURL.path) {
            return bundledURL
        }

        if let inherits,
           let inheritedRoot = petRoot(petID: inherits) {
            let inheritedURL = inheritedRoot.appendingPathComponent(spritesheetPath)
            if FileManager.default.fileExists(atPath: inheritedURL.path) {
                return inheritedURL
            }
            return resolveSpritesheetURL(
                root: inheritedRoot,
                petID: inherits,
                inherits: nil,
                spritesheetPath: spritesheetPath
            )
        }

        if petID == "mira" || inherits == "mira",
           let repoRoot = sourceRepoRoot() {
            let sourceURL = repoRoot
                .appendingPathComponent("assets/pets/explorer-cat/sprites/explorer-cat.sheet.webp")
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                return sourceURL
            }
        }

        return bundledURL
    }

    private func sourcePackageRoot() -> URL? {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        return url
    }

    private func sourceRepoRoot() -> URL? {
        guard var url = sourcePackageRoot() else {
            return nil
        }
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        return url
    }
}

@MainActor
final class ActionCharacterTreatmentRegistry {
    static let shared = ActionCharacterTreatmentRegistry()

    private struct Treatment {
        let displayName: String
        let petID: String?
        let scale: CGFloat
        let stateAliases: [String: String]
    }

    private let treatments: [String: Treatment] = [
        "mira": Treatment(displayName: "Mira", petID: "mira", scale: 1, stateAliases: [:]),
        "director": Treatment(
            displayName: "Director",
            petID: "director",
            scale: 1,
            stateAliases: [
                "countdown": "countdown",
                "recording": "recording",
                "interrupt": "interrupt",
                "wrap": "wrap",
            ]
        ),
        "scout": Treatment(
            displayName: "Scout",
            petID: "scout",
            scale: 1,
            stateAliases: [
                "observe": "observe",
                "analyze": "analyze",
                "finding": "finding",
                "await-decision": "await-decision",
            ]
        ),
        "relay": Treatment(
            displayName: "Relay",
            petID: "relay",
            scale: 0.85,
            stateAliases: [
                "bridge": "bridge",
                "navigate": "navigate",
                "act": "act",
                "offline": "offline",
            ]
        ),
        "compositor": Treatment(
            displayName: "Compositor",
            petID: "compositor",
            scale: 1,
            stateAliases: [
                "timeline": "timeline",
                "render": "render",
                "done": "done",
            ]
        ),
        "dock": Treatment(displayName: "Dock", petID: "mira", scale: 1, stateAliases: [:]),
    ]

    private let applicationTreatments: [String: String] = [
        "Action.app": "mira",
        "recording-probe": "director",
        "chrome-companion": "relay",
        "action-cli": "terminal",
        "action-mcp": "terminal",
        "composer": "compositor",
        "desktop-pet": "dock",
    ]

    private let phaseTreatments: [String: (treatment: String, state: String)] = [
        "session.staging": ("mira", "idle"),
        "session.countdown": ("director", "countdown"),
        "session.recording": ("director", "recording"),
        "session.observing": ("scout", "observe"),
        "session.analyzing": ("scout", "analyze"),
        "session.awaiting-decision": ("scout", "await-decision"),
        "session.acting": ("relay", "act"),
        "session.composing": ("compositor", "timeline"),
        "session.completed": ("mira", "success"),
        "session.failed": ("mira", "error"),
    ]

    private init() {}

    func displayName(for treatmentID: String) -> String {
        treatments[treatmentID]?.displayName ?? treatmentID
    }

    func petID(for treatmentID: String) -> String? {
        treatments[treatmentID]?.petID ?? treatmentID
    }

    func scale(for treatmentID: String) -> CGFloat {
        treatments[treatmentID]?.scale ?? 1
    }

    func sheetState(for treatmentID: String, logicalState: String) -> String {
        treatments[treatmentID]?.stateAliases[logicalState] ?? logicalState
    }

    func treatment(forApplication application: String) -> String? {
        applicationTreatments[application]
    }

    func binding(forPhase phase: String) -> (treatment: String, state: String)? {
        phaseTreatments[phase]
    }
}
