import KioskLocalization
import SwiftUI

struct PointerSetupHelpView: View {
  let instructions: String
  @Environment(\.locale) private var locale

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label(L10n.string("マウスを固定できません", locale: locale), systemImage: "cursorarrow.rays")
        .font(.title2)
      Text(L10n.string(instructions, locale: locale))
        .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(.white)
    .padding(24)
    .frame(maxWidth: 480)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("pointer-setup-help")
  }
}
