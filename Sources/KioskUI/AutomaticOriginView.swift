import SwiftUI

struct AutomaticOriginView: View {
  let address: String

  var body: some View {
    HStack {
      Text("開始URL")
      Spacer(minLength: 16)
      Label(address, systemImage: "lock.fill")
        .foregroundStyle(.secondary)
    }
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("開始URLの許可先")
    .accessibilityValue(address)
    .accessibilityIdentifier("automatic-origin")
  }
}
