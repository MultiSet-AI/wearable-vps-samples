/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation
import MultipeerConnectivity

/// Multipeer Connectivity manager for multiplayer pose sharing.
/// This app acts as a **client** that browses for and connects to a host device
/// running the MultiSet iOS SDK multiplayer host.
class MultipeerManager: NSObject, ObservableObject {

    private let serviceType = "multiset-sdk" // Must match iOS SDK host

    private let myPeerID: MCPeerID
    private var session: MCSession
    private var browser: MCNearbyServiceBrowser?

    @Published var connectedPeers: [MCPeerID] = []
    @Published var isBrowsing = false
    @Published var isConnected = false
    @Published var connectionStatus: String = "Not connected"

    var onMessageReceived: ((String, Data) -> Void)?

    /// Player color generated once at init
    let playerColor: (Float, Float, Float)

    init(displayName: String) {
        myPeerID = MCPeerID(displayName: displayName)
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .none)
        playerColor = Self.randomVibrantColor()

        super.init()
        session.delegate = self
    }

    var localPeerIDString: String {
        myPeerID.displayName
    }

    // MARK: - Client (Browser)

    func startBrowsing() {
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        isBrowsing = true
        connectionStatus = "Searching for host..."
        print("MultipeerManager >> Started browsing for peers")
    }

    // MARK: - Send Data

    func send(data: Data, reliable: Bool = true) {
        guard !session.connectedPeers.isEmpty else { return }

        let mode: MCSessionSendDataMode = reliable ? .reliable : .unreliable
        do {
            try session.send(data, toPeers: session.connectedPeers, with: mode)
        } catch {
            print("MultipeerManager >> Send error: \(error.localizedDescription)")
        }
    }

    func sendPoseUpdate(_ pose: PoseUpdate) {
        guard let payload = try? JSONEncoder().encode(pose),
              let message = try? JSONEncoder().encode(
                NetworkMessage(type: .poseUpdate, senderID: myPeerID.displayName, payload: payload)
              ) else { return }

        send(data: message, reliable: false)
    }

    func sendPlayerInfo(_ info: PlayerInfo) {
        guard let payload = try? JSONEncoder().encode(info),
              let message = try? JSONEncoder().encode(
                NetworkMessage(type: .playerInfo, senderID: myPeerID.displayName, payload: payload)
              ) else { return }

        send(data: message, reliable: true)
    }

    // MARK: - Disconnect

    func disconnect() {
        browser?.stopBrowsingForPeers()
        session.disconnect()
        isBrowsing = false
        isConnected = false
        connectedPeers = []
        connectionStatus = "Disconnected"
        print("MultipeerManager >> Disconnected")
    }

    // MARK: - Random Color

    static func randomVibrantColor() -> (Float, Float, Float) {
        let hue = Float.random(in: 0...1)
        let saturation = Float.random(in: 0.6...1.0)
        let brightness = Float.random(in: 0.7...1.0)

        let c = brightness * saturation
        let x = c * (1 - abs(fmod(hue * 6, 2) - 1))
        let m = brightness - c

        var r: Float = 0, g: Float = 0, b: Float = 0
        let segment = Int(hue * 6) % 6
        switch segment {
        case 0: r = c; g = x; b = 0
        case 1: r = x; g = c; b = 0
        case 2: r = 0; g = c; b = x
        case 3: r = 0; g = x; b = c
        case 4: r = x; g = 0; b = c
        case 5: r = c; g = 0; b = x
        default: break
        }

        return (r + m, g + m, b + m)
    }
}

// MARK: - MCSessionDelegate

extension MultipeerManager: MCSessionDelegate {

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
            self.isConnected = !session.connectedPeers.isEmpty

            switch state {
            case .connected:
                print("MultipeerManager >> Connected to: \(peerID.displayName)")
                let names = session.connectedPeers.map { $0.displayName }.joined(separator: ", ")
                self.connectionStatus = "Connected to: \(names)"
            case .notConnected:
                print("MultipeerManager >> Disconnected from: \(peerID.displayName)")
                if session.connectedPeers.isEmpty {
                    self.connectionStatus = self.isBrowsing ? "Searching for host..." : "Disconnected"
                }
            case .connecting:
                print("MultipeerManager >> Connecting to: \(peerID.displayName)")
                self.connectionStatus = "Connecting to \(peerID.displayName)..."
            @unknown default:
                break
            }
        }

        // Send player info immediately upon connection
        if state == .connected {
            let info = PlayerInfo(
                playerName: myPeerID.displayName,
                colorR: playerColor.0, colorG: playerColor.1, colorB: playerColor.2
            )
            sendPlayerInfo(info)
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        onMessageReceived?(peerID.displayName, data)
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        print("MultipeerManager >> Found peer: \(peerID.displayName)")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("MultipeerManager >> Lost peer: \(peerID.displayName)")
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("MultipeerManager >> Failed to start browsing: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.connectionStatus = "Browse failed: \(error.localizedDescription)"
        }
    }
}
