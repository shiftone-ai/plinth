import Darwin
import Foundation
import KioskCore
import Network

struct NetworkAddressCatalog {
  private struct AddressEntry {
    let name: String
    let address: String
    let ipv6: Bool
  }

  let addresses: [String]

  init(addresses: [String]) { self.addresses = addresses }

  init(path: NWPath?) {
    let selectedInterfaces = path?.availableInterfaces.filter {
      path?.usesInterfaceType($0.type) == true
    }
    let selectedNames = selectedInterfaces.map { Set($0.map(\.name)) }
    var entries: [AddressEntry] = []
    var first: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&first) == 0 else {
      addresses = ["127.0.0.1", "::1"]
      return
    }
    defer { freeifaddrs(first) }
    var current = first
    while let entry = current?.pointee {
      defer { current = entry.ifa_next }
      guard let socketAddress = entry.ifa_addr,
        entry.ifa_flags & UInt32(IFF_UP) != 0,
        socketAddress.pointee.sa_family == AF_INET || socketAddress.pointee.sa_family == AF_INET6
      else { continue }
      let name = String(cString: entry.ifa_name)
      if let selectedNames, !selectedNames.contains(name) { continue }
      var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      guard
        getnameinfo(
          socketAddress, socklen_t(socketAddress.pointee.sa_len), &buffer,
          socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0
      else { continue }
      guard
        let address = String(
          bytes: buffer.prefix(while: { $0 != 0 }).map(UInt8.init), encoding: .utf8)
      else { continue }
      guard !address.contains("%"), address != "127.0.0.1", address != "::1" else {
        continue
      }
      entries.append(
        AddressEntry(
          name: name, address: address, ipv6: socketAddress.pointee.sa_family == AF_INET6))
    }
    // Prefer IPv4 when both families are usable. IPv6-only networks retain their IPv6 URL.
    entries.sort {
      if $0.ipv6 != $1.ipv6 { return !$0.ipv6 }
      return $0.name == $1.name ? $0.address < $1.address : $0.name < $1.name
    }
    addresses =
      Array(Set(entries.map(\.address))).sorted { left, right in
        let leftIndex = entries.firstIndex { $0.address == left } ?? .max
        let rightIndex = entries.firstIndex { $0.address == right } ?? .max
        return leftIndex < rightIndex
      } + ["127.0.0.1", "::1"]
  }

  func hosts(port: UInt16) -> Set<String> {
    Set(
      addresses.map { address in
        address.contains(":") ? "[\(address)]:\(port)" : "\(address):\(port)"
      })
  }

  func preferredURL(port: UInt16) -> String? {
    guard let address = addresses.first(where: { $0 != "127.0.0.1" && $0 != "::1" })
    else { return nil }
    let host = address.contains(":") ? "[\(address)]" : address
    return "http://\(host):\(port)/"
  }

  func endpoint(port: UInt16) -> WebServerEndpoint {
    WebServerEndpoint(
      url: preferredURL(port: port),
      origins: addresses.compactMap { address in
        let host = address.contains(":") ? "[\(address)]" : address
        return Origin(urlString: "http://\(host):\(port)/")
      })
  }
}
