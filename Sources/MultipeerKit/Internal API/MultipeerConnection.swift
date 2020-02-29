import Foundation
import MultipeerConnectivity
import os.log

final class MultipeerConnection: NSObject, MultipeerProtocol {

    enum Mode: Int, CaseIterable {
        case receiver
        case transmitter
    }

    private let log = MultipeerKit.log(for: MultipeerConnection.self)

    let modes: [Mode]
    let configuration: MultipeerConfiguration
    let me: MCPeerID

    init(modes: [Mode] = Mode.allCases, configuration: MultipeerConfiguration = .default) {
        self.modes = modes
        self.configuration = configuration
        self.me = MCPeerID.fetchOrCreate(with: configuration)
    }

    var didReceiveData: ((Data, PeerName) -> Void)?
    var didFindPeer: ((Peer) -> Void)?
    var didLosePeer: ((Peer) -> Void)?

    private var discoveredPeers: [MCPeerID: Peer] = [:]

    func resume() {
        os_log("%{public}@", log: log, type: .debug, #function)

        if modes.contains(.receiver) {
            advertiser.startAdvertisingPeer()
        }
        if modes.contains(.transmitter) {
            browser.startBrowsingForPeers()
        }
    }

    func stop() {
        os_log("%{public}@", log: log, type: .debug, #function)

        if modes.contains(.receiver) {
            advertiser.stopAdvertisingPeer()
        }
        if modes.contains(.transmitter) {
            browser.stopBrowsingForPeers()
        }
    }

    private lazy var session: MCSession = {
        let s = MCSession(
            peer: me,
            securityIdentity: configuration.security.identity,
            encryptionPreference: configuration.security.encryptionPreference
        )

        s.delegate = self

        return s
    }()

    private lazy var browser: MCNearbyServiceBrowser = {
        let b = MCNearbyServiceBrowser(peer: me, serviceType: configuration.serviceType)

        b.delegate = self

        return b
    }()

    private lazy var advertiser: MCNearbyServiceAdvertiser = {
        let a = MCNearbyServiceAdvertiser(peer: me, discoveryInfo: nil, serviceType: configuration.serviceType)

        a.delegate = self

        return a
    }()

    func broadcast(_ data: Data) throws {
        guard !session.connectedPeers.isEmpty else {
            os_log("Not broadcasting message: no connected peers", log: self.log, type: .error)
            return
        }

        try session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    func send(_ data: Data, to peers: [Peer]) throws {
        let ids = peers.map { $0.underlyingPeer }
        try session.send(data, toPeers: ids, with: .reliable)
    }

}

// MARK: - Session delegate

extension MultipeerConnection: MCSessionDelegate {

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        os_log("%{public}@", log: log, type: .debug, #function)
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        os_log("%{public}@", log: log, type: .debug, #function)

        didReceiveData?(data, peerID.displayName)
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        os_log("%{public}@", log: log, type: .debug, #function)
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        os_log("%{public}@", log: log, type: .debug, #function)
    }

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        os_log("%{public}@", log: log, type: .debug, #function)
    }

}

// MARK: - Browser delegate

extension MultipeerConnection: MCNearbyServiceBrowserDelegate {

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        os_log("%{public}@", log: log, type: .debug, #function)

        do {
            let peer = try Peer(peer: peerID, discoveryInfo: info)

            discoveredPeers[peerID] = peer

            didFindPeer?(peer)
        } catch {
            os_log("Failed to initialize peer based on peer ID %@: %{public}@", log: self.log, type: .error, String(describing: peerID), String(describing: error))
        }

        #warning("TODO: Add public API to customize invitation")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10.0)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        os_log("%{public}@", log: log, type: .debug, #function)

        guard let peer = discoveredPeers[peerID] else { return }

        didLosePeer?(peer)

        discoveredPeers[peerID] = nil
    }

}

// MARK: - Advertiser delegate

extension MultipeerConnection: MCNearbyServiceAdvertiserDelegate {

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        os_log("%{public}@", log: log, type: .debug, #function)

        guard let peer = discoveredPeers[peerID] else { return }

        configuration.security.invitationHandler(peer, context, { decision in
            invitationHandler(decision, decision ? session : nil)
        })
    }

}