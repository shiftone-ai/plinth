import Foundation
import KioskCore
import KioskMacApp
import KioskRuntime
import Testing

struct ProfileRepositoryTests {
  @Test func maximumCommittedRevisionRemainsReadableButCannotWrapAround() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-revision-limit-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("profile.json")
    let maximum = try profile(revision: UInt64.max)
    try JSONEncoder().encode(maximum).write(to: url)
    let repository = ProfileRepository(fileURL: url)
    #expect(try await repository.load() == maximum)
    let candidate = try profile()
    await #expect(throws: ProfileRepository.Failure.self) { try await repository.save(candidate) }
    #expect(try await repository.load() == maximum)
  }
  private func profile(revision: UInt64 = 1) throws -> KioskProfile {
    let origin = try #require(Origin(urlString: "https://example.com"))
    return KioskProfile(
      revision: revision, startURL: "https://example.com/home",
      navigation: .init(rules: [.init(id: 1, origin: origin)]))
  }

  @Test func atomicRoundTripAndStaleRevisionPreserveCommittedFile() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-repository-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = ProfileRepository(fileURL: directory.appendingPathComponent("profile.json"))
    #expect(try await repository.load() == nil)
    let first = try profile()
    try await repository.save(first)
    #expect(try await repository.load() == first)
    await #expect(throws: ProfileRepository.Failure.self) { try await repository.save(first) }
    #expect(try await repository.load() == first)
    let second = try profile(revision: 2)
    try await repository.save(second)
    #expect(try await repository.load() == second)
    await #expect(throws: ProfileRepository.Failure.self) { try await repository.recover(first) }
    #expect(try await repository.load() == second)
    let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    #expect(files == ["profile.json"])
  }

  @Test func corruptOrUnsupportedProfileIsNotReplacedBySave() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-corrupt-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("profile.json")
    let bytes = Data("{broken".utf8)
    try bytes.write(to: url)
    let repository = ProfileRepository(fileURL: url)
    await #expect(throws: ProfileRepository.Failure.self) { try await repository.load() }
    let candidate = try profile()
    await #expect(throws: ProfileRepository.Failure.self) { try await repository.save(candidate) }
    #expect(try Data(contentsOf: url) == bytes)
  }
}
