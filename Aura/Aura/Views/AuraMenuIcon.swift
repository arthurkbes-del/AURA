// SPDX-License-Identifier: GPL-3.0-or-later
import AuraCore
import SwiftUI

private struct AuraWave: Shape {
    func path(in rect: CGRect) -> Path { Path(AuraSymbol.path(in: rect)) }
}

struct AuraBrandMark: View {
    var body: some View {
        AuraWave().stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .frame(width: 25, height: 20).accessibilityHidden(true)
    }
}

extension AppState {
    var menuIconAssetName: String {
        if activeError != nil { return "AuraStatusError" }
        if !saved.configuration.processingEnabled { return "AuraStatusBypassed" }
        return engineRunning ? "AuraStatusProcessing" : "AuraStatusStopped"
    }
}
