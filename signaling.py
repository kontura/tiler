import asyncio
import websockets

connected_clients = {}  # {client_id: {"ws": websocket}}
rooms = {}  # {room_id: [client_id1, client_id2,...]}

active_websockets = {} # {websocket.id: (client_id, room_id)

def parse_binary_message(data: bytes):
    if len(data) < 3:
        raise ValueError("Too short to be valid")

    header = data[0]
    sender_len = data[1]
    pos = 2
    sender_id = int.from_bytes(data[pos:pos + sender_len], byteorder='little')
    pos += sender_len

    target_len = data[pos]
    pos += 1
    target_id = int.from_bytes(data[pos:pos + target_len], byteorder='little')
    pos += target_len

    payload = data[pos:]  # Rest of message is raw payload

    return header, sender_id, target_id, payload

async def handler(websocket):
    client_id = None
    try:
        # Wait for initial registration message
        raw = await websocket.recv()
        _, client_id, room_id, _ = parse_binary_message(raw)

        if not room_id in rooms:
            rooms[room_id] = []

        for room_peer_id in rooms[room_id]:
            values = connected_clients[room_peer_id]
            target_ws = values["ws"]
            await target_ws.send(raw)

        connected_clients[client_id] = {"ws": websocket}
        rooms[room_id].append(client_id)
        active_websockets[websocket.id] = (client_id, room_id)
        print(rooms)
        print(connected_clients)

        print(f"Client '{client_id}' connected.", flush=True)

        async for data in websocket:
            _, sender_id, target_id, payload = parse_binary_message(data)
            if target_id not in connected_clients:
                continue

            print(f"Sending from '{sender_id}' to '{target_id}', data len {len(payload)}", flush=True)

            target_ws = connected_clients[target_id]["ws"]

            await target_ws.send(data)

    except websockets.ConnectionClosed:
        print(f"Client '{client_id}' disconnected.", flush=True)
    except Exception as e:
        print(f"Error: {e}", flush=True)
    finally:
        try:
            client_id, room_id = active_websockets[websocket.id]
            del connected_clients[client_id]
            rooms[room_id].remove(client_id)
        except:
            print(f"Error in finally: failed to delete: {websocket.id} - perhaps it was already deleted.")


async def main():
    print("Binary signaling server started on ws://localhost:8765")
    async with websockets.serve(handler, "0.0.0.0", 8765, max_size=2**20):
        await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(main())

