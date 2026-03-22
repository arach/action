import AppKit

func actionHUDPanelLevel() -> NSWindow.Level {
    NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) - 1)
}
