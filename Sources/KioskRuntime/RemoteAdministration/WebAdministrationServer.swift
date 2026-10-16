import Foundation
import KioskCore
import Network

@MainActor
public final class WebAdministrationServer: WebAdministrationServerPort {
  public static let standardPort: UInt16 = 47623

  private let configuredPort: UInt16
  private var generation: UUID?
  private var cancellationPending: UUID?
  private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []
  private var listener: NWListener?
  private var monitor: NWPathMonitor?
  private var clients: [UUID: WebAdministrationClient] = [:]
  private var startContinuations:
    [CheckedContinuation<Result<WebServerEndpoint, WebServerFailure>, Never>] = []
  private var catalog = NetworkAddressCatalog(path: nil)
  public private(set) var listeningPort: UInt16?
  public private(set) var url: String?
  public var addressChanged: ((WebServerEndpoint) -> Void)?
  var respond: ((HTTPRequest, Set<String>) -> HTTPResponse)?

  public init(port: UInt16 = standardPort) { configuredPort = port }

  public func attach(runtime: RootRuntime, locale: @escaping @MainActor () -> Locale) {
    let endpoint = WebAdministrationHTTPHandler(runtime: runtime, locale: locale)
    respond = { request, hosts in endpoint.handle(request, validHosts: hosts) }
  }

  public func start() async -> Result<WebServerEndpoint, WebServerFailure> {
    if cancellationPending != nil {
      await withCheckedContinuation { cancellationWaiters.append($0) }
      return await start()
    }
    if listener != nil {
      if let listeningPort { return .success(catalog.endpoint(port: listeningPort)) }
      return await withCheckedContinuation { startContinuations.append($0) }
    }
    let newListener: NWListener
    do {
      let port =
        configuredPort == 0
        ? NWEndpoint.Port.any
        : NWEndpoint.Port(rawValue: configuredPort)!
      newListener = try NWListener(using: .tcp, on: port)
    } catch { return .failure(.unavailable) }
    let newGeneration = UUID()
    generation = newGeneration
    listener = newListener
    let newMonitor = NWPathMonitor()
    monitor = newMonitor
    newMonitor.pathUpdateHandler = { [weak self] path in
      Task { @MainActor [weak self] in self?.pathChanged(path, generation: newGeneration) }
    }
    newMonitor.start(queue: .main)
    newListener.newConnectionHandler = { [weak self] connection in
      Task { @MainActor [weak self] in self?.accept(connection) }
    }
    newListener.stateUpdateHandler = { [weak self] state in
      Task { @MainActor [weak self] in self?.stateChanged(state, generation: newGeneration) }
    }
    return await withCheckedContinuation { continuation in
      startContinuations.append(continuation)
      newListener.start(queue: .main)
    }
  }

  public func stop() {
    if let listener, let generation {
      cancellationPending = generation
      listener.cancel()
    }
    generation = nil
    completeStart(.failure(.unavailable))
    for client in clients.values { client.stop() }
    clients.removeAll()
    listener = nil
    monitor?.cancel()
    monitor = nil
    listeningPort = nil
    url = nil
  }

  private func stateChanged(_ state: NWListener.State, generation source: UUID) {
    if case .cancelled = state, cancellationPending == source {
      cancellationPending = nil
      let waiters = cancellationWaiters
      cancellationWaiters.removeAll()
      for waiter in waiters { waiter.resume() }
      return
    }
    guard generation == source else { return }
    switch state {
    case .ready:
      listeningPort = listener?.port?.rawValue
      if let listeningPort {
        catalog = NetworkAddressCatalog(path: monitor?.currentPath)
        url = catalog.preferredURL(port: listeningPort)
      }
      let endpoint = catalog.endpoint(port: listeningPort ?? configuredPort)
      completeStart(.success(endpoint))
    case .failed(let error):
      let failure: WebServerFailure
      if case .posix(.EADDRINUSE) = error { failure = .portInUse } else { failure = .unavailable }
      completeStart(.failure(failure))
      stop()
    default: break
    }
  }

  private func pathChanged(_ path: NWPath, generation source: UUID) {
    guard generation == source else { return }
    updateAddressCatalog(NetworkAddressCatalog(path: path))
  }

  func updateAddressCatalog(_ newCatalog: NetworkAddressCatalog) {
    let previous = listeningPort.map { catalog.endpoint(port: $0) }
    catalog = newCatalog
    guard let listeningPort else { return }
    let updated = newCatalog.endpoint(port: listeningPort)
    guard updated != previous else { return }
    url = updated.url
    addressChanged?(updated)
  }

  private func completeStart(_ result: Result<WebServerEndpoint, WebServerFailure>) {
    let continuations = startContinuations
    startContinuations.removeAll()
    for continuation in continuations { continuation.resume(returning: result) }
  }

  private func accept(_ connection: NWConnection) {
    guard let listeningPort, clients.count < 32 else {
      connection.cancel()
      return
    }
    let id = UUID()
    let client = WebAdministrationClient(connection: connection) { [weak self] request in
      guard let self else { return HTTPResponse(500) }
      return self.respond?(request, self.catalog.hosts(port: listeningPort))
        ?? HTTPResponse(503)
    } onClose: { [weak self] in
      self?.clients.removeValue(forKey: id)
    }
    clients[id] = client
    client.start()
  }
}

@MainActor
private final class WebAdministrationClient {
  private let connection: NWConnection
  private let respond: (HTTPRequest) -> HTTPResponse
  private let onClose: () -> Void
  private var received = Data()
  private var closed = false
  private var timeout: Timer?

  init(
    connection: NWConnection, respond: @escaping (HTTPRequest) -> HTTPResponse,
    onClose: @escaping () -> Void
  ) {
    self.connection = connection
    self.respond = respond
    self.onClose = onClose
  }

  func start() {
    connection.start(queue: .main)
    timeout = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated { self?.stop() }
    }
    receive()
  }

  private func receive() {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) {
      [weak self] data, _, complete, error in
      Task { @MainActor [weak self] in self?.receivedChunk(data, closed: complete || error != nil) }
    }
  }

  private func receivedChunk(_ chunk: Data?, closed byPeer: Bool) {
    guard !closed else { return }
    if let chunk { received.append(chunk) }
    switch HTTPRequest.parse(received) {
    case .incomplete:
      if byPeer { stop() } else { receive() }
    case .invalid: send(HTTPResponse(400))
    case .complete(let request): send(respond(request))
    }
  }

  private func send(_ response: HTTPResponse) {
    connection.send(
      content: response.data,
      completion: .contentProcessed { [weak self] _ in
        Task { @MainActor [weak self] in self?.stop() }
      })
  }

  func stop() {
    guard !closed else { return }
    closed = true
    timeout?.invalidate()
    timeout = nil
    connection.cancel()
    onClose()
  }
}
