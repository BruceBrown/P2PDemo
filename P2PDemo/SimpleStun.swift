//
//  SimpleStun.swift
//  P2PDemo
//
//  Created by Bruce Brown on 5/15/20.
//  Copyright © 2020 Bruce Brown. All rights reserved.
//
import CocoaAsyncSocket

// We want to use the Stun server to assist in hole punching, by sending to a remote
// host and at the same time learning the IP/Port on the other side of my network. We'd
// use Network framework instead of CocoaAsyncSocket, however the Network framework
// requires a connection. Later, we'll use GameCenter as a rendezvous server

// This is a simplified implementation of STUN. Its enough to make a request and parse a response
class StunClient: NSObject {
    typealias Closure = (String?, UInt16?, GCDAsyncUdpSocket?, Error?) -> Void
    
    weak var messageDelegate: MessageDelegate? = nil
    
    private var results: Closure?
    private var servers = [HostAndPort(host: "stun1.l.google.com", port: 19302),
                           HostAndPort(host: "stun2.l.google.com", port: 19302),
                           HostAndPort(host: "stun3.l.google.com", port: 19302),
                           HostAndPort(host: "stun4.l.google.com", port: 19302)]
    private let networkQueue = DispatchQueue(label: "com.somewhere.network")
    private lazy var udpSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: networkQueue)
    
    private var tag: Int = 0
    private var dataInTransit = [Int: Data]()
    
    func getMyInfo(_ body: @escaping Closure) throws -> Void {
        self.results = body
        // instead of blasting all 4 servers, randomize and pick the first two
        servers.shuffle()
        try udpSocket.bind(toPort: 0)
        try udpSocket.beginReceiving()
        print("bound to port \(udpSocket.localPort())")
        for index in 0..<2 {
            let (_, request) = createRequest()
            let server = servers[index]
            if let host = server.host, let port = server.port {
                sendData(request, toHost: host, port: port)
            }
        }
    }
}

extension StunClient: GCDAsyncUdpSocketDelegate {
    
    func sendData(_ data: Data, toHost host: String, port: UInt16) {
        networkQueue.async { [weak self] in
            guard let self = self else { return }
            let tag = self.tag+1
            self.tag = tag
            self.dataInTransit[tag] = data
            self.udpSocket.send(data, toHost: host, port: port, withTimeout: 2, tag: tag)
        }
    }

    func udpSocket(_ sock: GCDAsyncUdpSocket, didReceive data: Data, fromAddress address: Data, withFilterContext filterContext: Any?) {
        guard let host = GCDAsyncUdpSocket.host(fromAddress: address) else { return }
        print("received data from \(host)")
        if let handshake = try? JSONDecoder().decode(BeginHandshake.self, from: data) {
            print("received BeginHandshake from peer")
            messageDelegate?.didReceive(handshake)
        } else {
            self.receivedStunResponse(data, from: host)
        }
    }
    
    func udpSocket(_ sock: GCDAsyncUdpSocket, didSendDataWithTag tag: Int) {
        print("sent request \(tag)")
        networkQueue.async { [weak self] in
            self?.dataInTransit.removeValue(forKey: tag)
        }
    }
    
    func udpSocket(_ sock: GCDAsyncUdpSocket, didNotSendDataWithTag tag: Int, dueToError error: Error?) {
        print("failed to sent request \(tag), error: \(String(describing: error?.localizedDescription))")
        networkQueue.async { [weak self] in
            self?.dataInTransit.removeValue(forKey: tag)
        }
    }
    
    func udpSocketDidClose(_ sock: GCDAsyncUdpSocket, withError error: Error?) {
        print("closed udp socket")
    }
}

extension StunClient {
    class HostAndPort {
        var host: String?
        var port: UInt16?
        
        init() {
            self.host = nil
            self.port = nil
        }
        
        init(host: String, port: UInt16) {
            self.host = host
            self.port = port
        }
    }
    
    func createTransactionID() -> Data {
        var data = Data()
        for _ in 0 ..< 12 {
            let rand: UInt8 = UInt8.random(in: 0..<255)
            data.append(rand)
        }
        return data
    }
    
    func createRequest() -> (Data, Data) {
        let request: [UInt8] = [0, 1]
        let length: [UInt8] = [0, 0]
        let magicCookie: [UInt8] = [0x21, 0x12, 0xA4, 0x42]
        let transactionID = createTransactionID()
        var data = Data()
        data.append(contentsOf: request)
        data.append(contentsOf: length)
        data.append(contentsOf: magicCookie)
        data.append(transactionID)
        
        return (transactionID,data)
    }
    
    func receivedStunResponse(_ data: Data, from host: String) {
        guard data.count > 20
            else {
                print("bad message returned")
                return
        }
        let (address, port) = data.withUnsafeBytes { (bytes) -> (String?, UInt16?) in
            let uint8Buffer = bytes.bindMemory(to: UInt8.self)
            let uint16Buffer = bytes.bindMemory(to: UInt16.self)
            let code1 = CFSwapInt16(uint16Buffer[0])
            let code2 = CFSwapInt16(uint16Buffer[10])
            
            if code1 != UInt16(0x0101) {
                print("bad result")
                return (nil, nil)
            }
            if code2 != UInt16(0x0020) {
                
                print("bad payload returned")
                return (nil, nil)
            }
            // parse port and IP
            let port = CFSwapInt16(uint16Buffer[13]) ^ 0x2112
            let index = 20 + 2 + 2 + 2 + 2 // code + len + family + port
            let address = "\(uint8Buffer[index+0] ^ 0x21).\(uint8Buffer[index+1] ^ 0x12).\(uint8Buffer[index+2] ^ 0xA4).\(uint8Buffer[index+3] ^ 0x42)"
            print("stun server \(String(describing: host)) gave address \(address):\(port)")
            return (address, port)
        }
        self.results?(address, port, udpSocket, nil)
    }
}
