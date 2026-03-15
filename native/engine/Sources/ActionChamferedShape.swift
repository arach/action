import SwiftUI

struct ActionChamferedShape: InsettableShape {
    var cornerCut: CGFloat = 6
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let cut = max(0, min(cornerCut, min(insetRect.width, insetRect.height) / 2))
        var path = Path()

        path.move(to: CGPoint(x: insetRect.minX + cut, y: insetRect.minY))
        path.addLine(to: CGPoint(x: insetRect.maxX - cut, y: insetRect.minY))
        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.minY + cut))
        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.maxY - cut))
        path.addLine(to: CGPoint(x: insetRect.maxX - cut, y: insetRect.maxY))
        path.addLine(to: CGPoint(x: insetRect.minX + cut, y: insetRect.maxY))
        path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.maxY - cut))
        path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.minY + cut))
        path.closeSubpath()

        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}
