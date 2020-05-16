#  Demo P2P Setup Using Game Center as a Rendezvous Server
This is a litle something I threw together becaus I needed a P2P communication in my game and GameCenter wasn't able to keep up. There are 3 peice to this solution:
* Getting the IP address on the other side of my router, thanks for the public stun server Google
* Getting the IP addresses on the device side of my router -- this version grabs IPv4, including VPN
* Creating a match, which provides a mens of exchanging peer address and port information
Once you've got those things in place:
* Broadcast via GameCenter your addreses and port, via PeerInfo
* Upon receiving the broadcast, send a BeginHandshake message to each address and port via upd Socket
* Upon receiving the BeginHandshake, send an EndHandshake to the peer via GameCenter, completing the P2P setup

A couple of additional notes.
This utilizes CocoaAsyncSocket, thank you.
This has a very trivial stun client, its not very robust.
This has a trivial Game Center helper, which is good enough


