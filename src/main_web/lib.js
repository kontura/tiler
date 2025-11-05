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
                    //Module.ccall('load_save', null, [], []);
                }
        });
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
                _pass_msg_to_odin(arrayBuffer);
            });
        });
    },

    send_binary_to_peer: function(peer_ptr, peer_len, data_ptr, data_len) {
        const peer_array = new Uint8Array(Module.HEAPU8.buffer, peer_ptr, peer_len);
        const decoder = new TextDecoder();
        const peer = decoder.decode(peer_array);

        const msg = new Uint8Array(Module.HEAPU8.buffer, data_ptr, data_len);
        if (Module[peer] && Module[peer].rtc && Module[peer].rtc.connectionState === 'connected' &&
        Module[peer].channel && Module[peer].channel.readyState === 'open') {
            Module[peer].channel.send(msg)
        } else {
            Module.signalingSocket.send(msg)
        }
    },

    send_to_peer_signaling: function(peer_ptr, peer_len, msg) {
        const encoder = new TextEncoder();
        const view = encoder.encode(msg)
        const arrayBuffer = view.buffer;

        const ptr = Module._malloc(arrayBuffer.byteLength);
        const wasmMemory = new Uint8Array(Module.HEAPU8.buffer, ptr, arrayBuffer.byteLength);
        wasmMemory.set(new Uint8Array(arrayBuffer));

        const data_len = Module._malloc(4);
        const data = Module._malloc(4);
        Module.ccall('build_binary_msg_c', null,
                     ['number', 'number', 'number', 'number', 'number', 'number'],
                     [peer_len, peer_ptr, arrayBuffer.byteLength, ptr, data_len, data]);
        const d_len = Module.HEAP32[data_len >> 2];
        const d_ptr = Module.HEAP32[data >> 2];
        _send_binary_to_peer(peer_ptr, peer_len, d_ptr, d_len);
    },

    pass_msg_to_odin: function(arrayBuffer) {
        const ptr = Module._malloc(arrayBuffer.byteLength);
        const wasmMemory = new Uint8Array(Module.HEAPU8.buffer, ptr, arrayBuffer.byteLength);
        wasmMemory.set(new Uint8Array(arrayBuffer));
        Module.ccall('process_binary_msg', null, ['number', 'number'], [arrayBuffer.byteLength, ptr]);
    },

    make_webrtc_offer: function(peer_ptr, peer_len) {
        console.log("sending webrtc offer")
        const peer_array = new Uint8Array(Module.HEAPU8.buffer, peer_ptr, peer_len);
        const decoder = new TextDecoder();
        const peer = decoder.decode(peer_array);

        const configuration = {'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]};
        Module[peer] = {rtc: new RTCPeerConnection(configuration)};
        console.log("adding channel")
        Module[peer].channel = Module[peer].rtc.createDataChannel("my-channel");
        Module[peer].channel.binaryType = 'arraybuffer';
        Module[peer].channel.addEventListener('message', event => {
            _pass_msg_to_odin(event.data);
        });

        Module[peer].rtc.createOffer().then((offer) => {
                Module[peer].rtc.setLocalDescription(offer).then(() => {
                    _send_to_peer_signaling(peer_ptr, peer_len, JSON.stringify(offer))
                });
        });

        Module[peer].rtc.addEventListener('connectionstatechange', event => {
            if (Module[peer].rtc.connectionState === 'connected') {
                Module.ccall('set_peer_rtc_connected', null, ['number', 'number'], [peer_len, peer_ptr]);
            }
        });

        // Listen for local ICE candidates on the local RTCPeerConnection
        Module[peer].rtc.addEventListener('icecandidate', event => {
            if (event.candidate) {
                _send_to_peer_signaling(peer_ptr, peer_len, JSON.stringify(event.candidate))
            }
        });
    },

    accept_webrtc_answer: function(peer_ptr, peer_len, answer_data, answer_len) {
        const peer_array = new Uint8Array(Module.HEAPU8.buffer, peer_ptr, peer_len);
        const decoder = new TextDecoder();
        const peer = decoder.decode(peer_array);

        const answer_array = new Uint8Array(Module.HEAPU8.buffer, answer_data, answer_len);
        const answer_string = decoder.decode(answer_array);
        const answer = JSON.parse(answer_string);
        console.log("ANSWER: ", answer)
        const remoteDesc = new RTCSessionDescription(answer);
        Module[peer].rtc.setRemoteDescription(remoteDesc)
    },

    accept_webrtc_offer: function(peer_ptr, peer_len, sdp_data, sdp_len) {
        const peer_array = new Uint8Array(Module.HEAPU8.buffer, peer_ptr, peer_len);
        const decoder = new TextDecoder();
        const peer = decoder.decode(peer_array);

        const sdp_array = new Uint8Array(Module.HEAPU8.buffer, sdp_data, sdp_len);
        const sdpString = decoder.decode(sdp_array);
        const offer = JSON.parse(sdpString);
        const configuration = {'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]}
        Module[peer] = {rtc: new RTCPeerConnection(configuration)};

        Module[peer].rtc.addEventListener('datachannel', event => {
            console.log("added channel")
            Module[peer].channel = event.channel;
            Module[peer].channel.binaryType = 'arraybuffer';
            Module[peer].channel.addEventListener('message', event => {
                _pass_msg_to_odin(event.data);
            });
        });

        Module[peer].rtc.addEventListener('connectionstatechange', event => {
            if (Module[peer].rtc.connectionState === 'connected') {
                Module.ccall('set_peer_rtc_connected', null, ['number', 'number'], [peer_len, peer_ptr]);
            }
        });

        Module[peer].rtc.setRemoteDescription(new RTCSessionDescription(offer));
        Module[peer].rtc.createAnswer().then((answer) => {
            Module[peer].rtc.setLocalDescription(answer).then(() => {
                _send_to_peer_signaling(peer_ptr, peer_len, JSON.stringify(answer))
            });
        });

        // Listen for local ICE candidates on the local RTCPeerConnection
        Module[peer].rtc.addEventListener('icecandidate', event => {
            if (event.candidate) {
                _send_to_peer_signaling(peer_ptr, peer_len, JSON.stringify(event.candidate))
            }
        });
    },

    add_peer_ice: function(peer_ptr, peer_len, msg_data, msg_len) {
        const peer_array = new Uint8Array(Module.HEAPU8.buffer, peer_ptr, peer_len);
        const decoder = new TextDecoder();
        const peer = decoder.decode(peer_array);

        const msg_array = new Uint8Array(Module.HEAPU8.buffer, msg_data, msg_len);
        const msgString = decoder.decode(msg_array);
        const ice = JSON.parse(msgString);
        Module[peer].rtc.addIceCandidate(ice).then(() => {});
    },
});


