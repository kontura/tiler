addToLibrary({
    mount_idbfs: function() {
        console.log("mounting idbfs");
        if (typeof FS === 'undefined' || typeof IDBFS === 'undefined') {
            console.error("FS or IDBFS is not available");
            return;
        }
        FS.mkdir('/persist');
        FS.mount(IDBFS, {autoPersist: true}, '/persist');
        FS.syncfs(true, function(err) {
                if (err) {
                    console.error("error syncing", err);
                } else {
                    console.log("fs sync to great succ.");
                        Module.ccall('load_save', null, [], []);
                }
        });
    },

    test_webrtc: function() {
        const configuration = {'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]};
        const peerConnection = new RTCPeerConnection(configuration);
        peerConnection.createOffer().then((offer) => {
                console.log(offer);
                peerConnection.setLocalDescription(offer)});
    },


    send_binary_to_signaling_websocket: function(data_ptr, data_len) {
        const msg = new Uint8Array(Module.HEAPU8.buffer, data_ptr, data_len);
        Module.signalingSocket.send(msg)
    },

    connect_signaling_websocket: function() {
        console.log("Setting up signaling websocket")
        Module.signalingSocket = new WebSocket("wss://tiler.kontura.cc/ws/");

        // Connection opened
        Module.signalingSocket.addEventListener("open", (event) => {
            console.log("connected to signaling server");
            const data_len = Module._malloc(4);
            const data = Module._malloc(4);
            Module.ccall('build_register_msg_c', null, ['number', 'number'], [data_len, data]);
            const d_len = Module.HEAP32[data_len >> 2];
            const d_ptr = Module.HEAP32[data >> 2];
            const msg = new Uint8Array(Module.HEAPU8.buffer, d_ptr, d_len);
            Module.signalingSocket.send(msg)
            Module.ccall('set_socket_ready', null, [], []);
        });

        Module.signalingSocket.addEventListener("close", (event) => {
            console.log("signaling connection closed: ", event.data)
        });

        Module.signalingSocket.addEventListener("error", (event) => {
            console.error("signaling connection error: ", event.data)
        });

        Module.signalingSocket.addEventListener("message", (event) => {
            event.data.arrayBuffer().then(arrayBuffer => {
                console.log("received: ", arrayBuffer.byteLength)
                const ptr = Module._malloc(arrayBuffer.byteLength);
                const wasmMemory = new Uint8Array(Module.HEAPU8.buffer, ptr, arrayBuffer.byteLength);
                wasmMemory.set(new Uint8Array(arrayBuffer));

                Module.ccall('process_binary_msg', null, ['number', 'number'], [arrayBuffer.byteLength, ptr]);
            });
        });
    },

});


