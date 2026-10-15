import KioskCore
import KioskMacApp
import KioskRuntime
import Testing

@MainActor
struct DiagnosticRecordTests {
  @Test func sensitivePayloadsAndVisitorInputDoNotEnterDiagnosticRecords() {
    let fixture = RuntimeFixture()
    for event in [Event.nativeInput(.cursorMoved, .web), .passcodeEdited("secret")] {
      let report = fixture.runtime.send(event, from: .platform)
      #expect(
        DiagnosticRecord(event: event, report: report, snapshot: fixture.runtime.snapshot) == nil)
    }
    let event = Event.passcodeSubmitted
    let report = fixture.runtime.send(event, from: .unlock)
    let record = DiagnosticRecord(event: event, report: report, snapshot: fixture.runtime.snapshot)
    #expect(record?.kind == .authentication)
    #expect(record?.rejection == .invalidState)
    #expect(String(describing: record).contains("secret") == false)
  }
}
