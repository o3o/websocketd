# Websocket Server

This is a _dubization_ of  [George Zakhour web socket server](https://github.com/geezee/websocket-d-server)


# Usage

To start, every connected peer receives an ID whose type is `PeerID`.

To implement a protocol, you start by creating a subclass of `WebSocketServer`.

And you will have to implement four methods:
* `override void onOpen(PeerID id, string path)` which is executed every time a client connects to
  the websocket server. The `id` argument is the generated ID of the newly connected client, the
  `path` argument is the path the client connects to.
* `override void onClose(PeerID id)` which is executed everytime a client disconnects.
* `override void onTextMessage(PeerID id, string msg)` which is executed every time a TEXT message
  from a client `id` is received.
* `override void onBinaryMessage(PeerID id, ubyte[] msg)` which is executed every time a BINARY message
  from a client `id` is received.

To run the server you need to execute the `run(ushort port, size_t maxConnections)()` method on the
server instance. The `port` template argument is the port the server needs to run, and the
`maxConnections` template argument is the maximum number of allowed connections. When the maximum
number of connections is reached every new connection will be denied.

To send a message to a peer whose id is `id`, you can use `sendText(PeerID id, string msg)` or the
`sendBinary(PeerID id, ubyte[] msg)` methods.


# Examples
Some examples can be found in `test_server.d` which are recreated here.

## Echo server

```
class EchoWebsocketServer : WebSocketServer {

    override void onOpen(PeerID s, string path) {}
    override void onClose(PeerID s) {}

    override void onBinaryMessage(PeerID id, ubyte[] msg) {
        sendBinary(id, msg);
    }

    override void onTextMessage(PeerID id, string msg) {
        sendText(id, msg);
    }
}
```
To run `echo` version:
```
$ cd examples
$ dub run -cecho
```
## Broadcasting server based on the connected path

Clients can subscribe to the channel `xyz` by connecting to `ws://example.com/xyz`. Clients connected
to another channel (eg. `abc`) will not receive messages from other channels (eg. `xyz`).

```
class BroadcastServer : WebSocketServer {

    private string[PeerID] peers;

    override void onOpen(PeerID s, string path) {
        peers[s] = path;
    }

    override void onClose(PeerID s) {
        peers.remove(s);
    }

    override void onTextMessage(PeerID src, string msg) {
        send!(sendText, typeof(msg))(src, msg);
    }

    override void onBinaryMessage(PeerID src, ubyte[] msg) {
        send!(sendBinary, typeof(msg))(src, msg);
    }

    private void send(alias sender, T)(PeerID src, T msg) {
        string srcPath = peers[src];
        foreach (id, path; peers)
            if (id != src && path == srcPath)
                sender(id, msg);
    }

}
```

To run `broadcast` version:
```
$ cd examples
$ dub run -cbroadcat
```

# Running the server with TLS

The server natively does not support TLS. However if you use nginx you can create a proxy and use
nginx for TLS. Here's an example of an nginx configuration.

```
upstream websocketservers {
    server localhost:10301; # 10301 being the port websocket-d-server runs on
}

server {
    server_name example.com;
    # ...

    location /<path> {
        proxy_pass http://websocketservers;
    }

    listen 443 ssl;
    # ...
}
```

Then a client can connect via `wss://example.com/`
