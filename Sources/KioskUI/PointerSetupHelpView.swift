import SwiftUI

struct PointerSetupHelpView: View {
  let instructions: String

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("マウスを固定できません", systemImage: "cursorarrow.rays")
        .font(.title2)
      Text(instructions)
        .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(.white)
    .padding(24)
    .frame(maxWidth: 480)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("pointer-setup-help")
  }
}
