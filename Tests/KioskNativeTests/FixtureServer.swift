import Foundation
import Network

@MainActor
final class FixtureServer {
  private let listener: NWListener
  private var connections: [NWConnection] = []
  private(set) var origin = ""
  var blockedURL: String {
    origin.replacingOccurrences(of: "127.0.0.1", with: "localhost") + "/blocked"
  }
  init() throws {
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    listener = try NWListener(using: parameters)
  }

  func start() async throws {
    listener.newConnectionHandler = { [weak self] connection in
      MainActor.assumeIsolated { self?.accept(connection) }
    }
    try await withCheckedThrowingContinuation {
      (completion: CheckedContinuation<Void, any Error>) in
      listener.stateUpdateHandler = { [weak self] state in
        MainActor.assumeIsolated {
          guard let self else { return }
          switch state {
          case .ready:
            self.listener.stateUpdateHandler = nil
            self.origin = "http://127.0.0.1:\(self.listener.port!.rawValue)"
            completion.resume()
          case .failed(let error):
            self.listener.stateUpdateHandler = nil
            completion.resume(throwing: error)
          default: break
          }
        }
      }
      listener.start(queue: .main)
    }
  }

  private func accept(_ connection: NWConnection) {
    connections.append(connection)
    connection.start(queue: .main)
    receive(connection, buffer: Data())
  }

  private func receive(_ connection: NWConnection, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
      [weak self] data, _, complete, error in
      MainActor.assumeIsolated {
        guard let self else { return }
        var bytes = buffer
        if let data { bytes.append(data) }
        if let request = String(data: bytes, encoding: .utf8), request.contains("\r\n\r\n") {
          self.reply(connection, request: request)
        } else if complete || error != nil {
          connection.cancel()
        } else {
          self.receive(connection, buffer: bytes)
        }
      }
    }
  }

  private func reply(_ connection: NWConnection, request: String) {
    let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
    if path == "/video.mp4" {
      replyVideo(connection, request: request)
      return
    }
    if path == "/network-failure" {
      connection.cancel()
      return
    }
    let body: String
    let header: String
    if path == "/surface" || path == "/rotation" {
      let rotationContent = path == "/rotation" ? Self.rotationControls : ""
      body = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;width:100%;height:100%;background:white}
        .corner{position:fixed;width:64px;height:64px;color:white}
        #tl{top:0;left:0;background:red}#tr{top:0;right:0;background:green}
        #bl{bottom:0;left:0;background:blue}#br{bottom:0;right:0;background:purple}
        </style></head><body><div class="corner" id="tl">Top left</div>
        <div class="corner" id="tr">Top right</div><div class="corner" id="bl">Bottom left</div>
        <div class="corner" id="br">Bottom right</div><p style="position:fixed;top:40%;left:40%">Full display</p>
        \(rotationContent)
        </body></html>
        """
      header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n"
    } else if path == "/redirect" || path == "/deny-redirect" {
      let destination = path == "/redirect" ? origin + "/allowed" : blockedURL
      body = ""
      header = "HTTP/1.1 302 Found\r\nLocation: \(destination)\r\n"
    } else if path == "/binary" {
      body = "fixture-download"
      header =
        "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Disposition: attachment; filename=fixture.txt\r\n"
    } else {
      let scrollContent =
        path == "/scroll" || path == "/allowed"
        ? """
        <p id="scroll-result" style="position:fixed;right:0;top:0">At top</p>
        <p id="bottom-state" style="position:fixed;right:0;top:24px">Not at bottom</p>
        <div style="height:1600px"></div><p id="scroll-bottom">Scroll bottom</p><div style="height:300px"></div>
        <script>addEventListener('scroll', () => {
          document.getElementById('scroll-result').textContent = scrollY > 100 ? 'Scrolled' : 'At top';
          document.getElementById('bottom-state').textContent = document.getElementById('scroll-bottom').getBoundingClientRect().bottom < innerHeight ? 'At bottom' : 'Not at bottom';
        });</script>
        """
        : ""
      let videoContent =
        path == "/video"
        ? """
        <video id="video" src="/video.mp4" autoplay muted playsinline loop width="640" height="360" style="max-width:100%;height:auto"></video>
        <p id="video-result">Video loading</p>
        <script>
        const video = document.getElementById('video');
        video.addEventListener('timeupdate', () => {
          if (!video.paused && video.currentTime > 0.5 && video.videoWidth > 0) {
            document.getElementById('video-result').textContent = 'Video playing';
          }
        });
        video.addEventListener('error', () => {
          document.getElementById('video-result').textContent = 'Video failed';
        });
        </script>
        """
        : ""
      let inputContent =
        path == "/input"
        ? """
        <style>#hover {background:rgb(0,0,0);width:160px;height:80px} #hover:hover {background:rgb(255,0,0)}</style>
        <div id="hover">Hover target</div>
        <canvas id="canvas" width="220" height="80" style="background:#cdf"></canvas>
        <p id="pointer-result">Pointer idle</p>
        <div id="drag-source" draggable="true" style="width:160px;height:70px;background:#fc8">Drag source</div>
        <div id="drop-target" style="position:absolute;left:360px;top:240px;width:160px;height:100px;background:#8cf">Drop target</div>
        <p id="drop-result">Drop idle</p>
        <button id="audio-button">Play audio</button><p id="audio-result">Audio idle</p>
        <script>
        const canvas = document.getElementById('canvas'), pointerResult = document.getElementById('pointer-result');
        canvas.addEventListener('pointerdown', e => { canvas.setPointerCapture(e.pointerId); pointerResult.textContent = 'Pointer pressed'; });
        canvas.addEventListener('pointermove', e => { if(e.buttons === 1 && canvas.hasPointerCapture(e.pointerId)) pointerResult.textContent = 'Pointer dragged'; });
        canvas.addEventListener('pointercancel', () => { pointerResult.textContent = 'Pointer cancelled'; });
        canvas.addEventListener('pointerup', e => { pointerResult.textContent = canvas.hasPointerCapture(e.pointerId) ? 'Pointer released' : 'Pointer capture lost'; });
        const drop = document.getElementById('drop-target');
        document.getElementById('drag-source').addEventListener('dragstart', e => e.dataTransfer.setData('text/plain','fixture-drag'));
        drop.addEventListener('dragover', e => e.preventDefault());
        drop.addEventListener('drop', e => { e.preventDefault(); document.getElementById('drop-result').textContent = e.dataTransfer.getData('text/plain') === 'fixture-drag' ? 'Drop accepted' : 'Drop failed'; });
        document.getElementById('audio-button').onclick = async () => {
          window.activationAtClick = navigator.userActivation.isActive;
          const audio = new AudioContext(), oscillator = audio.createOscillator(), gain = audio.createGain();
          gain.gain.value = 0; oscillator.connect(gain); gain.connect(audio.destination); oscillator.start();
          window.fixtureAudio = audio;
          await audio.resume();
          document.getElementById('audio-result').textContent = audio.state === 'running' ? 'Audio playing' : 'Audio blocked';
          oscillator.stop(audio.currentTime + 0.1);
        };
        </script>
        """ : ""
      body = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>\(path)</title></head><body>
        <h1>\(path)</h1>
        <a id="allowed" href="/allowed">Allowed</a>
        <a id="blocked" href="\(blockedURL)">Blocked</a>
        <a id="popup" href="/popup" target="_blank">Popup</a>
        <a id="redirect" href="/redirect">Redirect</a>
        <a id="deny-redirect" href="/deny-redirect">Blocked redirect</a>
        <button id="dialogs" onclick="alert('a');document.body.dataset.result=confirm('c')+'-'+prompt('p')">Dialogs</button>
        \(scrollContent)
        \(videoContent)
        \(inputContent)
        </body></html>
        """
      header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n"
    }
    let response = Data(
      (header + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body).utf8)
    connection.send(
      content: response,
      completion: .contentProcessed { [weak self] _ in
        MainActor.assumeIsolated { self?.connections.removeAll { $0 === connection } }
        connection.cancel()
      })
  }

  private func replyVideo(_ connection: NWConnection, request: String) {
    #if SWIFT_PACKAGE
      let bundle = Bundle.module
    #else
      let bundle = Bundle(for: FixtureServer.self)
    #endif
    guard let url = bundle.url(forResource: "video", withExtension: "mp4"),
      let video = try? Data(contentsOf: url)
    else {
      connection.cancel()
      return
    }
    var body = video
    var header = "HTTP/1.1 200 OK\r\n"
    // WebKit probes MP4 metadata with byte ranges before decoding the inline video.
    if let line = request.components(separatedBy: "\r\n").first(where: {
      $0.lowercased().hasPrefix("range: bytes=")
    }) {
      let bounds = line.dropFirst("Range: bytes=".count).split(
        separator: "-", omittingEmptySubsequences: false)
      guard bounds.count == 2, let lower = Int(bounds[0]), lower >= 0, lower < video.count,
        bounds[1].isEmpty || Int(bounds[1]) != nil
      else {
        let response = Data(
          "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */\(video.count)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            .utf8)
        connection.send(
          content: response, completion: .contentProcessed { _ in connection.cancel() })
        return
      }
      let upper = min(Int(bounds[1]) ?? video.count - 1, video.count - 1)
      guard upper >= lower else {
        connection.cancel()
        return
      }
      body = video.subdata(in: lower..<upper + 1)
      header =
        "HTTP/1.1 206 Partial Content\r\nContent-Range: bytes \(lower)-\(upper)/\(video.count)\r\n"
    }
    header +=
      "Content-Type: video/mp4\r\nAccept-Ranges: bytes\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
    var response = Data(header.utf8)
    if !request.hasPrefix("HEAD ") { response.append(body) }
    connection.send(
      content: response,
      completion: .contentProcessed { [weak self] _ in
        MainActor.assumeIsolated { self?.connections.removeAll { $0 === connection } }
        connection.cancel()
      })
  }

  func stop() {
    listener.cancel()
    for connection in connections { connection.cancel() }
    connections.removeAll()
  }
}

extension FixtureServer {
  fileprivate static let rotationControls = """
    <style>#target:hover{outline:3px solid red}</style>
    <p id="viewport" style="position:fixed;top:30%;left:20%"></p>
    <button style="position:fixed;top:10%;left:10%;width:20%;height:20%"
    onclick="document.getElementById('clicked').textContent='Corner activated'">Activate corner</button>
    <p id="clicked" style="position:fixed;top:45%;left:20%">Waiting</p>
    <div id="source" draggable="true" style="position:fixed;top:60%;left:10%;width:20%;height:10%;background:orange">Drag source</div>
    <div id="target" style="position:fixed;top:60%;left:60%;width:20%;height:10%;background:cyan">Drop target</div>
    <p id="dropped" style="position:fixed;top:75%;left:20%">Drop idle</p>
    <p id="hovered" style="position:fixed;top:80%;left:20%">Hover idle</p>
    <p id="scrolled" style="position:fixed;top:85%;left:20%">At top</p>
    <div style="height:200vh"></div>
    <script>
    function viewport(){document.getElementById('viewport').textContent='Viewport '+innerWidth+' × '+innerHeight}
    viewport();addEventListener('resize',viewport);
    document.getElementById('source').ondragstart=e=>e.dataTransfer.setData('text/plain','rotation');
    const target=document.getElementById('target');target.ondragover=e=>e.preventDefault();
    target.ondrop=e=>{e.preventDefault();document.getElementById('dropped').textContent=e.dataTransfer.getData('text/plain')==='rotation'?'Drop accepted':'Drop failed';document.getElementById('hovered').textContent=getComputedStyle(target).outlineStyle==='solid'?'Hover active':'Hover missing'};
    addEventListener('scroll',()=>document.getElementById('scrolled').textContent=scrollY>30?'Scrolled':'At top');
    </script>
    """
}
