import Foundation
import KioskCore
import Testing

struct RemoteAuthorizationTests {
  @Test func olderInstallationWithoutMutationRevisionStillLoads() throws {
    let original = RemoteInstallation(id: UUID())
    let encoded = try JSONEncoder().encode(original)
    var fields = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    fields.removeValue(forKey: "mutationRevision")
    let legacy = try JSONSerialization.data(withJSONObject: fields)
    let loaded = try JSONDecoder().decode(RemoteInstallation.self, from: legacy)
    #expect(loaded == original)
  }

  @Test func changingAppleAccountRevokesOldPermissionEvenAfterReturning() {
    let controllerID = UUID()
    let grant = RemotePeerGrant(
      id: controllerID, name: "Controller", accountIdentifier: "account-a",
      signingPublicKey: Data(repeating: 1, count: 32),
      agreementPublicKey: Data(repeating: 2, count: 32), approvedAt: .now)
    var installation = RemoteInstallation(
      id: UUID(), enabledAccountIdentifier: "account-a",
      lastAccountIdentifier: "account-a", approvedControllers: [controllerID: grant])

    installation.reconcileAccount(.transient)
    #expect(installation.enabledAccountIdentifier == "account-a")
    #expect(installation.approvedControllers[controllerID] == grant)

    installation.reconcileAccount(.available("account-b"))
    #expect(installation.enabledAccountIdentifier == nil)
    #expect(installation.approvedControllers.isEmpty)
    installation.reconcileAccount(.available("account-a"))
    #expect(installation.approvedControllers.isEmpty)
  }
}
