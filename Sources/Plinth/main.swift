import AppKit
import KioskMacApp
import KioskRuntime

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--help") {
  print(
    """
    Usage: Plinth [--preview]
      --preview  Run without changing Dock, menu bar, or process switching.
      --help     Show this help.
    """)
  exit(EXIT_SUCCESS)
}
if arguments.contains(where: { $0 != "--preview" }) {
  FileHandle.standardError.write(Data("Unknown option. Use Plinth --help.\n".utf8))
  exit(EXIT_FAILURE)
}
let application = NSApplication.shared
let preview = arguments.contains("--preview")
let environment = ProcessInfo.processInfo.environment
// Release fixtures are limited to preview; Debug also supports explicitly enabled dedicated OS tests.
let testService = environment["PLINTH_TEST_CREDENTIAL_SERVICE"]
let testDirectory = environment["PLINTH_TEST_PROFILE_DIRECTORY"]
#if DEBUG
  let dedicatedOSTest =
    environment["PLINTH_DEDICATED_MAC"] == "1"
    && environment["PLINTH_TEST_OS_PRESENTATION"] == "1"
#else
  let dedicatedOSTest = false
#endif
let usesFixture =
  (preview || dedicatedOSTest) && testService?.hasPrefix("ai.shiftone.plinth.tests.") == true
  && testDirectory?.hasPrefix("/") == true
let storeBundle = Bundle.main.bundleIdentifier == "ai.shiftone.plinth.mobile"
#if DEBUG
  let fixtureInset =
    usesFixture && dedicatedOSTest && environment["PLINTH_TEST_POINTER_REGION"] == "1" ? 150.0 : 0
#else
  let fixtureInset = 0.0
#endif
let migrationFixture = usesFixture && environment["PLINTH_TEST_KEYCHAIN_MIGRATION"] == "1"
let delegate = MacApplication(
  preview: preview, exhibitionInset: fixtureInset,
  credentialService: usesFixture
    ? (testService ?? "ai.shiftone.plinth") + (migrationFixture ? ".current" : "")
    : Bundle.main.bundleIdentifier ?? "ai.shiftone.plinth",
  storageNamespace: usesFixture ? testService ?? "Plinth" : "Plinth",
  credentialKeychain: migrationFixture || (storeBundle && !usesFixture)
    ? .dataProtection : .platformDefault,
  legacyCredentialService: migrationFixture
    ? testService : (storeBundle && !usesFixture ? "ai.shiftone.plinth" : nil))
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
