"""Loopback-only JSON API and fixed-step real-time driver. Python standard library."""
import argparse
import json
import math
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

from simulation import DEFINITION
from storage import Store

ROOT = Path(__file__).resolve().parents[1]


class Service:
    def __init__(self, db):
        self.store = Store(db)
        self.budget = 0.0
        self.last_time = time.monotonic()

    def update(self):
        with self.store.lock:
            now = time.monotonic()
            delta, self.last_time = now - self.last_time, now
            if self.store.sim.state['paused']:
                self.budget = 0
                return
            self.budget += min(delta, 1) * 4 * self.store.sim.state['speed']
            ticks = int(self.budget)
            if ticks:
                self.store.advance(ticks)
                self.budget -= ticks

    def dispatch(self, method, path, data=None):
        url = urlsplit(path)
        query = parse_qs(url.query)
        with self.store.lock:
            if method == 'GET':
                if url.path == '/health': return dict(status='ok', schema_version=1, service='oak-and-ember')
                if url.path == '/world': return self.store.view()
                if url.path == '/definition': return DEFINITION
                if url.path == '/npcs': return self.store.view()['npcs']
                if url.path.startswith('/npcs/'):
                    npc = next((n for n in self.store.view()['npcs'] if n['id'] == url.path.split('/')[-1]), None)
                    if npc is None: raise KeyError('角色不存在')
                    return npc
                if url.path == '/snapshots': return self.store.snapshots()
                if url.path == '/events':
                    limit = int(query.get('limit', ['100'])[0])
                    after = int(query.get('after', ['0'])[0])
                    day = int(query['day'][0]) if 'day' in query else None
                    npc = query.get('npc', [None])[0]
                    if not 1 <= limit <= 1000 or after < 0 or (day is not None and day < 1): raise ValueError('日志分页参数无效')
                    if npc and npc not in [n['id'] for n in DEFINITION['residents']]: raise ValueError('角色不存在')
                    events = self.store.events(npc, day, after, limit, query.get('latest') == ['true'], query.get('run_id', [None])[0])
                    return dict(events=events, next_after=events[-1]['seq'] if events else after)
            if method == 'POST':
                if not isinstance(data, dict): raise ValueError('请求体必须为 JSON 对象')
                if url.path == '/advance':
                    minutes = data.get('minutes', 60)
                    if isinstance(minutes, bool) or not isinstance(minutes, (float, int)) or not math.isfinite(minutes) or not 0 <= minutes <= 1440 or minutes * 2 != int(minutes * 2):
                        raise ValueError('minutes 必须为 0～1440 的 0.5 倍数')
                    result = self.store.advance(int(minutes * 2))
                elif url.path == '/clock':
                    if not data or set(data) - {'paused', 'speed'}: raise ValueError('只支持 paused 和 speed')
                    if any(value is None for value in data.values()): raise ValueError('时钟参数不能为 null')
                    result = self.store.controls(data)
                elif url.path == '/save': result = self.store.save(data.get('name', '手动存档'))
                elif url.path == '/restore':
                    snapshot_id = data.get('snapshot_id')
                    if isinstance(snapshot_id, bool) or not isinstance(snapshot_id, int) or snapshot_id < 1: raise ValueError('snapshot_id 必须为正整数')
                    result = self.store.restore(snapshot_id)
                elif url.path == '/reset': result = self.store.reset(data.get('start_minute', 470))
                else: raise KeyError('接口不存在')
                self.last_time = time.monotonic()
                self.budget = 0
                return result
        raise KeyError('接口不存在')


def make_server(service, port):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_): pass

        def do_GET(self): self.handle_request('GET')

        def do_POST(self): self.handle_request('POST')

        def handle_request(self, method):
            try:
                data = None
                if method == 'POST':
                    size = int(self.headers.get('Content-Length', '0'))
                    if not 0 < size <= 65536: raise ValueError('请求体大小无效')
                    data = json.loads(self.rfile.read(size).decode('utf-8'))
                result = service.dispatch(method, self.path, data)
                status = 200
            except KeyError as exc:
                result, status = dict(error=str(exc.args[0])), 404
            except (ValueError, TypeError) as exc:
                result, status = dict(error=str(exc)), 400
            except Exception:
                result, status = dict(error='服务内部错误，当前事务已回滚'), 500
            encoded = json.dumps(result, ensure_ascii=False, allow_nan=False).encode('utf-8')
            self.send_response(status)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Content-Length', str(len(encoded)))
            self.end_headers()
            try: self.wfile.write(encoded)
            except (BrokenPipeError, ConnectionResetError): pass
    return ThreadingHTTPServer(('127.0.0.1', port), Handler)


def main():
    parser = argparse.ArgumentParser(description='橡树镇统一模拟 API / SQLite 服务')
    parser.add_argument('--db', default=str(ROOT / '.runtime/town.sqlite3'))
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--paused', action='store_true', help='启动时暂停实时驱动')
    args = parser.parse_args()
    Path(args.db).parent.mkdir(parents=True, exist_ok=True)
    service = Service(args.db)
    if args.paused: service.store.controls({'paused': True})
    try:
        server = make_server(service, args.port)
    except Exception:
        service.store.close()
        raise
    stop = threading.Event()
    def driver():
        while not stop.wait(0.05):
            try: service.update()
            except Exception as exc:
                print(f'模拟推进失败：{exc}', flush=True)
                stop.set()
                server.shutdown()
    thread = threading.Thread(target=driver, daemon=True)
    thread.start()
    print(f'Oak & Ember API: http://127.0.0.1:{server.server_port} | SQLite: {args.db}', flush=True)
    try: server.serve_forever(poll_interval=0.1)
    except KeyboardInterrupt: pass
    finally:
        stop.set()
        thread.join(timeout=2)
        server.server_close()
        service.store.close()


if __name__ == '__main__': main()
