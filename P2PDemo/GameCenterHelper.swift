//
//  GameCenterHelper.swift
//  P2PDemo
//
//  Created by Bruce Brown on 5/15/20.
//  Copyright © 2020 Bruce Brown. All rights reserved.
//

import Foundation
import GameKit

protocol MessageDelegate: class {
    func didReceive(_ peerInfo: PeerInfo, fromRemotePlayer player: GKPlayer)
    func didReceive(_ beginHandshake: BeginHandshake)
    func didReceive(_ endHandshake: EndHandshake, fromRemotePlayer player: GKPlayer)
}

class GameCenterHelper: NSObject {
    
    typealias MatchmakingClosure = (GKMatch?, Error?) -> Void
    typealias AuthenticationClosure = (Bool) -> Void
    
    weak var controller: UIViewController?

    var currentMatchmakerVC: GKMatchmakerViewController?
    var currentMatch: GKMatch?

    var matchmakingClosure: MatchmakingClosure?
    var authenticationClosure: AuthenticationClosure?
    weak var messageDelegate: MessageDelegate?
    
    init(controller: UIViewController) {
        self.controller = controller
        super.init()
        
        GKLocalPlayer.local.authenticateHandler = { gcAuthVC, error in
            NotificationCenter.default
                .post(name: .authenticationChanged, object: GKLocalPlayer.local.isAuthenticated)
            if GKLocalPlayer.local.isAuthenticated {
                GKLocalPlayer.local.register(self)
                self.authenticationClosure?(true)
            } else if let vc = gcAuthVC {
                self.controller?.present(vc, animated: true)
            } else {
                self.authenticationClosure?(false)
            }
        }
    }
    
    deinit {
        GKLocalPlayer.local.unregisterListener(self)
    }

    func invitePeers() {
        // need to present the matchmaking stuff
        guard GKLocalPlayer.local.isAuthenticated else { return }
        
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 4
        request.defaultNumberOfPlayers = 2
        request.inviteMessage = "Would you like to connect?"
        guard let vc = GKMatchmakerViewController(matchRequest: request) else { return }
        currentMatchmakerVC = vc
        vc.matchmakerDelegate = self
        controller?.present(vc, animated: true)
    }
}

extension GameCenterHelper: GKLocalPlayerListener {
    
    func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        print("\(player.alias) did accept invite")
        guard let vc = GKMatchmakerViewController(invite: invite) else { return }
        currentMatchmakerVC = vc
        vc.matchmakerDelegate = self
        controller?.present(vc, animated: true)
    }
    
    func player(_ player: GKPlayer, didRequestMatchWithRecipients recipientPlayers: [GKPlayer]) {
        print("\(player.alias) did request match with recipients")
        recipientPlayers.forEach {
            print("   recipient: \($0.alias)")
        }
    }
}

extension GameCenterHelper: GKMatchDelegate {
    func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        switch state {
        case .connected:
            print("\(player.alias) state changed to connected")
        case .disconnected:
            print("\(player.alias) state changed to disconnected")
        case .unknown:
            print("\(player.alias) state changed to unknown")
        }
    }
    
    func match(_ match: GKMatch, didFailWithError error: Error?) {
        print("match error \(String(describing: error?.localizedDescription))")
        match.delegate = nil
        match.disconnect()
        if self.currentMatch == match {
            self.currentMatch = nil
        }
    }
    
    func match(_ match: GKMatch, shouldReinviteDisconnectedPlayer player: GKPlayer) -> Bool {
        print("\(player.alias) diconnected from match, re-inviting")
        return true
    }
}

extension GameCenterHelper: GKMatchmakerViewControllerDelegate {
    func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
        print("presenting matchmaker view controller was cancelled")
        dismisViewController(viewController)
        matchmakingClosure?(nil, nil)
    }
    
    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
        print("presenting matchmaker view controller failed with error: \(error.localizedDescription).")
        dismisViewController(viewController)
        matchmakingClosure?(nil, error)
    }

    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
        print("presenting matchmaker view controller found a match")
        if currentMatch != nil {
            print("already have a match, cleaning it up")
            currentMatch?.delegate = nil
            currentMatch?.disconnect()
        }
        self.currentMatch = match
        match.delegate = self
        dismisViewController(viewController)
        matchmakingClosure?(match, nil)
    }
    
    func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        decode(data, fromRemotePlayer: player)
    }
    
    func match(_ match: GKMatch, didReceive data: Data, forRecipient recipient: GKPlayer, fromRemotePlayer player: GKPlayer) {
        decode(data, fromRemotePlayer: player)
    }

    func decode(_ data: Data, fromRemotePlayer player: GKPlayer) {
        let decoder = JSONDecoder()
        if let peerInfo = try? decoder.decode(PeerInfo.self, from: data) {
            messageDelegate?.didReceive(peerInfo, fromRemotePlayer: player)
        } else if let endHandshake = try? decoder.decode(EndHandshake.self, from: data) {
            print ("handshake completed")
            messageDelegate?.didReceive(endHandshake, fromRemotePlayer: player)
        }
    }
    
    private func dismisViewController(_ viewController: GKMatchmakerViewController) {
        viewController.delegate = nil
        viewController.dismiss(animated: true)
        currentMatchmakerVC = nil
    }
}

extension Notification.Name {
  static let presentGame = Notification.Name(rawValue: "presentGame")
  static let authenticationChanged = Notification.Name(rawValue: "authenticationChanged")
}
