//
//  Messaging.swift
//  P2PDemo
//
//  Created by Bruce Brown on 5/15/20.
//  Copyright © 2020 Bruce Brown. All rights reserved.
//

import Foundation

// Broadcast to peers providing information about the peer
struct PeerInfo: Codable {
    let identifier: UUID
    let addresses: [String]
    let port: UInt16
    
    init(_ identifier: UUID, addresses: [String], port: UInt16) {
        self.identifier = identifier
        self.addresses = addresses
        self.port = port
    }
}

// Sent over the UDPSocket for hole punching and confirmation
struct BeginHandshake: Codable {
    let identifier: UUID
    let address: String
    let port: UInt16
    
    init(_ identifier: UUID, address: String, port: UInt16) {
        self.identifier = identifier
        self.address = address
        self.port = port
    }
}

// sent back to the originating peer to let it know the hole has been punched
struct EndHandshake: Codable {
    let identifier: UUID
    let peerIdentifier: UUID
    let address: String
    let port: UInt16
    
    init(_ handshake: BeginHandshake, identifier: UUID) {
        self.identifier = handshake.identifier
        self.peerIdentifier = identifier
        self.address = handshake.address
        self.port = handshake.port
    }
}

