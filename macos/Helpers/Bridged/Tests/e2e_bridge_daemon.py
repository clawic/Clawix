#!/usr/bin/env python3
import base64
import json
import os
import random
import socket
import struct
import subprocess
import sys
import tempfile
import textwrap
import threading
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / ".build" / "debug" / "clawix-bridge"


def auth_frame(token: str, device_name: str, client_kind: str, identity: str) -> dict:
    return {
        "schemaVersion": 1,
        "type": "auth",
        "token": token,
        "deviceName": device_name,
        "clientKind": client_kind,
        "clientId": f"clawix.e2e.{identity}",
        "installationId": f"install-{identity}",
        "deviceId": f"device-{identity}",
    }


def build():
    subprocess.run(["swift", "build"], cwd=ROOT, check=True)


def write_fake_backend(tmp: Path) -> Path:
    rollout = tmp / "rollout.jsonl"
    rollout.write_text(
        "\n".join(
            [
                json.dumps({"type": "session_meta", "payload": {"id": "thread-e2e", "cwd": str(tmp)}}),
                json.dumps({"type": "event_msg", "timestamp": "2026-05-05T10:00:00Z", "payload": {"type": "user_message", "message": "existing prompt"}}),
                json.dumps({"type": "event_msg", "timestamp": "2026-05-05T10:00:01Z", "payload": {"type": "agent_message", "message": "existing answer"}}),
                json.dumps({"type": "event_msg", "timestamp": "2026-05-05T10:00:02Z", "payload": {"type": "final_answer"}}),
            ]
        )
        + "\n"
    )
    backend = tmp / "fake-backend.py"
    backend.write_text(
        textwrap.dedent(
            f"""\
            #!/usr/bin/env python3
            import json, os, sys, threading, time
            rollout = {str(rollout)!r}
            cwd = {str(tmp)!r}
            cancelled_turns = set()
            thread_counter = 0

            def send(obj):
                print(json.dumps(obj), flush=True)

            def input_text(msg):
                parts = msg.get("params", {{}}).get("input", [])
                text = []
                for part in parts:
                    if isinstance(part, dict) and isinstance(part.get("text"), str):
                        text.append(part["text"])
                return " ".join(text)

            for line in sys.stdin:
                if not line.strip():
                    continue
                msg = json.loads(line)
                mid = msg.get("id")
                method = msg.get("method")
                if method == "initialize":
                    send({{"jsonrpc":"2.0","id":mid,"result":{{}}}})
                elif method == "initialized":
                    pass
                elif method == "thread/list":
                    if os.environ.get("CLAWIX_E2E_HANG_THREAD_LIST") == "1":
                        continue
                    send({{"jsonrpc":"2.0","id":mid,"result":{{"data":[{{
                        "id":"thread-e2e",
                        "cwd":cwd,
                        "name":"E2E thread",
                        "preview":"existing prompt",
                        "path":rollout,
                        "createdAt":1777975200,
                        "updatedAt":1777975200,
                        "archived":False
                    }}],"nextCursor":None}}}})
                elif method == "thread/start":
                    thread_counter += 1
                    thread_id = "thread-new-" + str(thread_counter)
                    send({{"jsonrpc":"2.0","id":mid,"result":{{"thread":{{"id":thread_id,"cwd":cwd,"createdAt":"2026-05-05T10:00:00Z","cliVersion":"e2e"}},"model":None}}}})
                elif method in ("thread/archive", "thread/unarchive"):
                    send({{"jsonrpc":"2.0","id":mid,"result":{{}}}})
                elif method == "turn/start":
                    thread_id = msg["params"]["threadId"]
                    turn_id = "turn-" + thread_id
                    text = input_text(msg)
                    is_slow_fixture = "slow prompt" in text or thread_id.endswith("-3")
                    is_error_fixture = "fail prompt" in text or thread_id.endswith("-4")
                    if is_error_fixture:
                        send({{"jsonrpc":"2.0","id":mid,"error":{{"code":-32000,"message":"fixture failure"}}}})
                        continue
                    send({{"jsonrpc":"2.0","id":mid,"result":{{"turn":{{"id":turn_id}}}}}})
                    def stream():
                        send({{"jsonrpc":"2.0","method":"turn/started","params":{{"threadId":thread_id,"turn":{{"id":turn_id}}}}}})
                        time.sleep(0.05)
                        delta = "partial slow" if is_slow_fixture else "hello from daemon"
                        send({{"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{{"threadId":thread_id,"turnId":turn_id,"itemId":"assistant-e2e","delta":delta}}}})
                        if is_slow_fixture:
                            for _ in range(40):
                                if turn_id in cancelled_turns:
                                    return
                                time.sleep(0.05)
                        time.sleep(0.05)
                        if turn_id in cancelled_turns:
                            return
                        send({{"jsonrpc":"2.0","method":"item/completed","params":{{"threadId":thread_id,"turnId":turn_id,"item":{{"id":"assistant-e2e","type":"agentMessage","text":"hello from daemon"}}}}}})
                        send({{"jsonrpc":"2.0","method":"turn/completed","params":{{"threadId":thread_id,"turn":{{"id":turn_id}}}}}})
                    threading.Thread(target=stream, daemon=True).start()
                elif method == "turn/interrupt":
                    cancelled_turns.add(msg.get("params", {{}}).get("turnId"))
                    send({{"jsonrpc":"2.0","id":mid,"result":{{}}}})
                else:
                    send({{"jsonrpc":"2.0","id":mid,"result":{{}}}})
            """
        )
    )
    backend.chmod(0o755)
    return backend


class WebSocket:
    def __init__(self, port: int):
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=5)
        key = base64.b64encode(os.urandom(16)).decode()
        request = (
            f"GET / HTTP/1.1\r\n"
            f"Host: 127.0.0.1:{port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n"
        )
        self.sock.sendall(request.encode())
        response = self.sock.recv(4096)
        if b"101 Switching Protocols" not in response:
            raise AssertionError(response.decode(errors="replace"))

    def send_json(self, obj):
        payload = json.dumps(obj, separators=(",", ":")).encode()
        mask = os.urandom(4)
        header = bytearray([0x81])
        if len(payload) < 126:
            header.append(0x80 | len(payload))
        elif len(payload) < 65536:
            header.append(0x80 | 126)
            header.extend(struct.pack("!H", len(payload)))
        else:
            header.append(0x80 | 127)
            header.extend(struct.pack("!Q", len(payload)))
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(bytes(header) + mask + masked)

    def recv_json(self, timeout=8):
        self.sock.settimeout(timeout)
        first = self.sock.recv(2)
        if len(first) < 2:
            raise AssertionError("short websocket header")
        opcode = first[0] & 0x0F
        length = first[1] & 0x7F
        if length == 126:
            length = struct.unpack("!H", self.sock.recv(2))[0]
        elif length == 127:
            length = struct.unpack("!Q", self.sock.recv(8))[0]
        if first[1] & 0x80:
            mask = self.sock.recv(4)
        else:
            mask = None
        payload = b""
        while len(payload) < length:
            payload += self.sock.recv(length - len(payload))
        if mask:
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        if opcode == 8:
            raise AssertionError("websocket closed")
        return json.loads(payload.decode())

    def recv_until(self, predicate, timeout=8):
        deadline = time.time() + timeout
        last = None
        while time.time() < deadline:
            try:
                last = self.recv_json(timeout=max(0.1, deadline - time.time()))
            except TimeoutError as exc:
                raise AssertionError(f"timed out waiting for websocket frame, last={last}") from exc
            if predicate(last):
                return last
        raise AssertionError(f"timed out waiting for frame, last={last}")

    def close(self):
        self.sock.close()


def connect_authenticated(port: int, token: str, device_name: str, client_kind: str, identity: str) -> WebSocket:
    ws = WebSocket(port)
    ws.send_json(auth_frame(token, device_name, client_kind, identity))
    ws.recv_until(lambda f: f["type"] == "authOk")
    return ws


def assert_no_active_generation(ws: WebSocket, session_id: str):
    frame = ws.recv_until(
        lambda f: (
            f["type"] == "sessionUpdated"
            and f["session"]["id"] == session_id
            and f["session"].get("hasActiveTurn") is False
        )
        or (
            f["type"] == "sessionsSnapshot"
            and any(s["id"] == session_id and s.get("hasActiveTurn") is False for s in f["sessions"])
        )
    )
    if frame["type"] == "sessionsSnapshot":
        session = next(s for s in frame["sessions"] if s["id"] == session_id)
        return {"schemaVersion": frame["schemaVersion"], "type": "sessionUpdated", "session": session}
    assert frame["session"].get("hasActiveTurn") is False
    return frame


def main():
    build()
    with tempfile.TemporaryDirectory(prefix="clawix-bridge-e2e-") as raw:
        tmp = Path(raw)
        backend = write_fake_backend(tmp)
        port = random.randint(39000, 49000)
        token = "test-token-" + os.urandom(16).hex()
        env = os.environ.copy()
        env.update(
            {
                "CLAWIX_BRIDGE_BACKEND_PATH": str(backend),
                "CLAWIX_BRIDGE_PORT": str(port),
                "CLAWIX_BRIDGE_BEARER": token,
                "CLAWIX_BRIDGE_DISABLE_BONJOUR": "1",
                "HOME": str(tmp),
            }
        )
        daemon = subprocess.Popen([str(BIN)], cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.time() + 8
            ws = None
            while time.time() < deadline:
                try:
                    ws = WebSocket(port)
                    break
                except OSError:
                    time.sleep(0.05)
            if ws is None:
                _, err = daemon.communicate(timeout=1)
                raise AssertionError(err)

            ws = connect_authenticated(port, token, "E2E iPhone", "companion", "iphone")

            desktop = connect_authenticated(port, token, "E2E Mac", "desktop", "desktop")
            desktop.send_json({"schemaVersion": 1, "type": "pairingStart"})
            pairing = desktop.recv_until(lambda f: f["type"] == "pairingPayload")
            qr = json.loads(pairing["qrJson"])
            assert pairing["token"] == qr["token"]
            assert pairing["shortCode"] == qr["shortCode"]
            assert "bearer" not in pairing
            assert "bearer" not in qr
            assert qr["v"] == 1
            assert qr["port"] == port
            qr_ws = WebSocket(port)
            qr_ws.send_json(auth_frame(qr["token"], "QR iPhone", "companion", "qr-iphone"))
            qr_ws.recv_until(lambda f: f["type"] == "authOk")
            qr_ws.close()

            invalid_ws = WebSocket(port)
            invalid_ws.send_json({"schemaVersion": 1, "type": "listSessions", "sessionId": "extra"})
            invalid = invalid_ws.recv_until(lambda f: f["type"] == "errorEvent")
            assert invalid["code"] == "bridge.decode.unknownField"
            assert "listSessions" in invalid["message"]
            invalid_ws.close()

            mismatch_ws = WebSocket(port)
            mismatch = auth_frame(token, "Mismatch iPhone", "companion", "mismatch-iphone")
            mismatch["schemaVersion"] = 2
            mismatch_ws.send_json(mismatch)
            mismatch_reply = mismatch_ws.recv_until(lambda f: f["type"] == "versionMismatch")
            assert mismatch_reply["serverVersion"] == 1
            mismatch_ws.close()

            desktop_chat_id = "44444444-5555-4666-8777-888888888888"
            desktop.send_json({"schemaVersion": 1, "type": "newSession", "sessionId": desktop_chat_id, "text": "desktop prompt"})
            desktop.recv_until(
                lambda f: (
                    f["type"] == "sessionsSnapshot"
                    and any(c["id"] == desktop_chat_id and c["title"] == "desktop prompt" for c in f["sessions"])
                )
            )
            desktop.recv_until(
                lambda f: (
                    f["type"] == "messageStreaming"
                    and f["sessionId"] == desktop_chat_id
                    and f["content"] == "hello from daemon"
                    and f["finished"] is True
                )
                or (
                    f["type"] == "messageAppended"
                    and f["sessionId"] == desktop_chat_id
                    and f["message"]["role"] == "assistant"
                    and f["message"]["content"] == "hello from daemon"
                )
            )
            assert_no_active_generation(desktop, desktop_chat_id)
            desktop.close()

            ws.recv_until(lambda f: f["type"] == "sessionsSnapshot" and f["sessions"])
            ws.send_json({"schemaVersion": 1, "type": "requestClawJSServiceStatuses"})
            service_statuses = ws.recv_until(lambda f: f["type"] == "clawJSServiceStatusesSnapshot")
            assert isinstance(service_statuses["services"], list)

            new_chat_id = "11111111-2222-4333-8444-555555555555"
            ws.send_json({"schemaVersion": 1, "type": "openSession", "sessionId": new_chat_id})
            ws.send_json({"schemaVersion": 1, "type": "sendMessage", "sessionId": new_chat_id, "text": "brand new prompt"})
            ws.recv_until(
                lambda f: (
                    f["type"] == "sessionsSnapshot"
                    and any(c["id"] == new_chat_id and c["title"] == "brand new prompt" for c in f["sessions"])
                )
            )
            ws.recv_until(
                lambda f: (
                    f["type"] == "messageStreaming"
                    and f["sessionId"] == new_chat_id
                    and f["content"] == "hello from daemon"
                    and f["finished"] is True
                )
                or (
                    f["type"] == "messageAppended"
                    and f["sessionId"] == new_chat_id
                    and f["message"]["role"] == "assistant"
                    and f["message"]["content"] == "hello from daemon"
                )
            )
            assert_no_active_generation(ws, new_chat_id)

            ws.send_json({"schemaVersion": 1, "type": "sendMessage", "sessionId": new_chat_id, "text": "follow-up prompt"})
            ws.recv_until(
                lambda f: (
                    f["type"] == "messageStreaming"
                    and f["sessionId"] == new_chat_id
                    and f["content"] == "hello from daemon"
                    and f["finished"] is True
                )
                or (
                    f["type"] == "messageAppended"
                    and f["sessionId"] == new_chat_id
                    and f["message"]["role"] == "assistant"
                    and f["message"]["content"] == "hello from daemon"
                )
            )
            assert_no_active_generation(ws, new_chat_id)

            cancel_chat_id = "22222222-3333-4444-8555-666666666666"
            ws.send_json({"schemaVersion": 1, "type": "openSession", "sessionId": cancel_chat_id})
            ws.send_json({"schemaVersion": 1, "type": "newSession", "sessionId": cancel_chat_id, "text": "slow prompt"})
            ws.recv_until(
                lambda f: (
                    f["type"] == "messageStreaming"
                    and f["sessionId"] == cancel_chat_id
                    and f["content"] == "partial slow"
                    and f["finished"] is False
                )
                or (
                    f["type"] == "messageAppended"
                    and f["sessionId"] == cancel_chat_id
                    and f["message"]["role"] == "assistant"
                    and f["message"]["content"] == "partial slow"
                    and f["message"]["streamingFinished"] is False
                )
                or (
                    f["type"] == "messagesSnapshot"
                    and f["sessionId"] == cancel_chat_id
                    and any(
                        m["role"] == "assistant"
                        and m["content"] == "partial slow"
                        and m["streamingFinished"] is False
                        for m in f["messages"]
                    )
                )
            )
            ws.send_json({"schemaVersion": 1, "type": "interruptTurn", "sessionId": cancel_chat_id})
            cancelled = assert_no_active_generation(ws, cancel_chat_id)
            assert cancelled["session"].get("lastTurnInterrupted") is True

            error_chat_id = "33333333-4444-4555-8666-777777777777"
            ws.send_json({"schemaVersion": 1, "type": "openSession", "sessionId": error_chat_id})
            ws.send_json({"schemaVersion": 1, "type": "newSession", "sessionId": error_chat_id, "text": "fail prompt"})
            ws.recv_until(
                lambda f: (
                    f["type"] == "messageAppended"
                    and f["sessionId"] == error_chat_id
                    and f["message"]["role"] == "assistant"
                    and f["message"].get("isError") is True
                    and "fixture failure" in f["message"]["content"]
                )
                or (
                    f["type"] == "messagesSnapshot"
                    and f["sessionId"] == error_chat_id
                    and any(
                        m["role"] == "assistant"
                        and m.get("isError") is True
                        and "fixture failure" in m["content"]
                        for m in f["messages"]
                    )
                )
            )
            assert_no_active_generation(ws, error_chat_id)

            ws.send_json({"schemaVersion": 1, "type": "archiveSession", "sessionId": new_chat_id})
            ws.recv_until(
                lambda f: (
                    f["type"] == "sessionUpdated"
                    and f["session"]["id"] == new_chat_id
                    and f["session"]["isArchived"] is True
                )
            )
            ws.send_json({"schemaVersion": 1, "type": "unarchiveSession", "sessionId": new_chat_id})
            ws.recv_until(
                lambda f: (
                    f["type"] == "sessionUpdated"
                    and f["session"]["id"] == new_chat_id
                    and f["session"]["isArchived"] is False
                )
            )
            ws.close()

            timeout_port = port + 1
            timeout_env = env.copy()
            timeout_env.update(
                {
                    "CLAWIX_BRIDGE_PORT": str(timeout_port),
                    "CLAWIX_E2E_HANG_THREAD_LIST": "1",
                    "CLAWIX_BRIDGE_THREAD_LIST_TIMEOUT_SECONDS": "0.2",
                    "CLAWIX_BRIDGE_RATE_LIMITS_TIMEOUT_SECONDS": "0.2",
                }
            )
            timeout_daemon = subprocess.Popen([str(BIN)], cwd=ROOT, env=timeout_env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            timeout_ws = None
            try:
                deadline = time.time() + 8
                while time.time() < deadline:
                    try:
                        timeout_ws = WebSocket(timeout_port)
                        break
                    except OSError:
                        time.sleep(0.05)
                if timeout_ws is None:
                    _, err = timeout_daemon.communicate(timeout=1)
                    raise AssertionError(err)
                timeout_ws.send_json(auth_frame(token, "Timeout Desktop", "desktop", "timeout-desktop"))
                timeout_ws.recv_until(lambda f: f["type"] == "authOk")
                timeout_ws.send_json({"schemaVersion": 1, "type": "listSessions"})
                timeout_ws.recv_until(lambda f: f["type"] == "bridgeState" and f["state"] == "ready", timeout=5)
            finally:
                if timeout_ws is not None:
                    timeout_ws.close()
                timeout_daemon.terminate()
                try:
                    timeout_daemon.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    timeout_daemon.kill()
                    timeout_daemon.wait(timeout=5)
        finally:
            daemon.terminate()
            try:
                daemon.wait(timeout=5)
            except subprocess.TimeoutExpired:
                daemon.kill()
                daemon.wait(timeout=5)


if __name__ == "__main__":
    main()
