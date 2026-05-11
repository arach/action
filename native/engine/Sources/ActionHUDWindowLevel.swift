import AppKit

func actionStageMaskWindowLevel() -> NSWindow.Level {
    NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) - 4)
}

func actionHUDPanelLevel() -> NSWindow.Level {
    NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) - 1)
}
