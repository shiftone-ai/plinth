import KioskLocalization
import SwiftUI

struct AutomaticOriginView: View {
  let address: String
  @Environment(\.locale) private var locale

  var body: some View {
    HStack {
      Text(L10n.string("ドメイン", locale: locale))
      Spacer(minLength: 16)
      Label(address, systemImage: "lock.fill")
        .foregroundStyle(.secondary)
    }
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(L10n.string("開始URLの許可先", locale: locale))
    .accessibilityValue(address)
    .accessibilityIdentifier("automatic-origin")
  }
}
