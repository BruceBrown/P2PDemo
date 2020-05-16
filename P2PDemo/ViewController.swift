//
//  ViewController.swift
//  P2PDemo
//
//  Created by Bruce Brown on 5/15/20.
//  Copyright © 2020 Bruce Brown. All rights reserved.
//

import UIKit
import GameKit
import CocoaAsyncSocket

// this currently handles a single peer, it can be enhanced to handle multiple peers
class ViewController: UIViewController {

    let identifier = UUID()
    let encoder = JSONEncoder()
    let stunClient = StunClient()
    var waitingOnEndHandshake = true
    var peers = [UUID: GKPlayer]()
    
    var addresses = Interface.allInterfaces().filter({ $0.isRunning && !$0.isLoopback && $0.isUp && $0.family == .ipv4 && $0.address != nil }).map { $0.address! }
    var port: UInt16?
    var udpSocket: GCDAsyncUdpSocket?

    lazy var helper: GameCenterHelper = GameCenterHelper(controller: self)
    var match: GKMatch?

    @IBOutlet weak var connectionAddressAndPort: UILabel!
    
    @IBAction func onInvitePeers(_ sender: UIButton) {
        helper.invitePeers()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        helper.matchmakingClosure = self.matchmakingCompleted
        helper.authenticationClosure = self.authenticationCompleted
        helper.messageDelegate = self
        stunClient.messageDelegate = self
        stun()
    }

    func stun() {
        // we could add some timing to retry if we done't get a response...
        try? stunClient.getMyInfo() {[weak self] (address, port, udpSocket, error) in
            guard let self = self, let address = address else { return }
            self.addresses.append(address)
            self.port = port
            self.udpSocket = udpSocket
        }
    }
    
    func authenticationCompleted(_ authenticated: Bool) {
        guard authenticated == true else { return }
    }
    
    func matchmakingCompleted(_ match: GKMatch?, error: Error?) {
        // handle cancel
        if match == nil && error == nil {
            self.dismiss(animated: true)
            return
        }

        if error != nil {
            print("matchmaking failed error: \(error!.localizedDescription)")
        }
        guard let match = match else { return }
        print("made a match, sending info to peers")
        // we could reasign the delegate, but the timing is a bit tricky, so piggyback on the helper
        self.match = match
        // by now, the stun should have completed, broadcast our network info
        let peerInfo = PeerInfo(identifier, addresses: self.addresses, port: self.port!)
        guard let data = try? JSONEncoder().encode(peerInfo) else { return }
        try? match.sendData(toAllPlayers: data, with: .reliable)
    }
}

extension ViewController: MessageDelegate {
    
    func didReceive(_ peerInfo: PeerInfo, fromRemotePlayer player: GKPlayer) {
        print("recieved peer info, starting handshake")
        peers[peerInfo.identifier] = player
        beginHandshakeWithPeer(peerInfo)
    }
    
    func didReceive(_ beginHandshake: BeginHandshake) {
        // this arrives via the udp socket
        print("recieved handshake from peer")
        let handshake = EndHandshake(beginHandshake, identifier: identifier)
        guard let data = try? JSONEncoder().encode(handshake) else { return }
        guard let player = peers[beginHandshake.identifier] else { return }
        try? match?.send(data, to: [player], dataMode: .reliable)
    }
    
    func didReceive(_ endHandshake: EndHandshake, fromRemotePlayer player: GKPlayer) {
        waitingOnEndHandshake = false
        print("connected to \(player.alias) via: \(endHandshake.address):\(endHandshake.port)")
        self.connectionAddressAndPort.text = "connected to \(player.alias) via: \(endHandshake.address):\(endHandshake.port)"
    }

    func helper(_ helper: GameCenterHelper, didRecieve peerInfo: PeerInfo, fromRemotePlayer player: GKPlayer) {
        print("received peer info for \(player.alias)")
        beginHandshakeWithPeer(peerInfo)
    }
    
    func beginHandshakeWithPeer(_ peerInfo: PeerInfo) {
        guard waitingOnEndHandshake else { return }
        peerInfo.addresses.forEach {
            let handshake = BeginHandshake(identifier, address: $0, port: peerInfo.port)
            guard let data = try? encoder.encode(handshake) else { return }
            stunClient.sendData(data, toHost: $0, port: peerInfo.port)
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+2) {[weak self] in
            self?.beginHandshakeWithPeer(peerInfo)
        }
    }

}
