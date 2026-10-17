import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
  nonisolated static let plinthSettings = UTType(
    exportedAs: "ai.shiftone.plinth.settings", conformingTo: .data)
}

struct CatalogEncryptedDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.plinthSettings] }
  static var writableContentTypes: [UTType] { [.plinthSettings] }

  let data: Data

  init(data: Data) { self.data = data }

  init(configuration: ReadConfiguration) throws {
    guard let contents = configuration.file.regularFileContents else {
      throw CocoaError(.fileReadCorruptFile)
    }
    data = contents
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}
