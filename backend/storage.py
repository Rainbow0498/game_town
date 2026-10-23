"""SQLite transactions persist the world and its events together."""
import copy
import json
import sqlite3
import threading
import uuid
import os
from datetime import datetime, timezone

from simulation import Simulation, SCHEMA_VERSION


def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'), allow_nan=False)


class DatabaseLease:
    """One authoritative writer per database, including across UI/CLI processes."""
    def __init__(self, path):
        self.file = open(str(path) + '.lock', 'a+b')
        self.file.seek(0, 2)
        if self.file.tell() == 0:
            self.file.write(b'0')
            self.file.flush()
        self.file.seek(0)
        try:
            if os.name == 'nt':
                import msvcrt
                msvcrt.locking(self.file.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            self.file.close()
            raise RuntimeError('数据库正在使用；请通过 API 操作，或停止服务后使用 CLI') from exc

    def close(self):
        self.file.close()


class Store:
    def __init__(self, path):
        self.lock = threading.RLock()
        self.lease = DatabaseLease(path)
        try:
            self._open(path)
        except Exception:
            if hasattr(self, 'db'): self.db.close()
            self.lease.close()
            raise

    def _open(self, path):
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.execute('PRAGMA synchronous=FULL')
        version = self.db.execute('PRAGMA user_version').fetchone()[0]
        if version not in (0, SCHEMA_VERSION):
            raise ValueError('数据库版本不兼容')
        self.db.executescript('''
        CREATE TABLE IF NOT EXISTS world_state (
            id INTEGER PRIMARY KEY CHECK(id=1), revision INTEGER NOT NULL, payload TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS events (
            run_id TEXT NOT NULL, seq INTEGER NOT NULL, day INTEGER NOT NULL,
            npc_id TEXT, type TEXT NOT NULL, payload TEXT NOT NULL,
            PRIMARY KEY(run_id, seq));
        CREATE INDEX IF NOT EXISTS events_npc_day ON events(run_id, npc_id, day, seq);
        CREATE TABLE IF NOT EXISTS snapshots (
            id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
            created_at TEXT NOT NULL, run_id TEXT NOT NULL, tick INTEGER NOT NULL,
            event_seq INTEGER NOT NULL, payload TEXT NOT NULL);
        PRAGMA user_version=1;
        ''')
        row = self.db.execute('SELECT * FROM world_state WHERE id=1').fetchone()
        self.revision = row['revision'] if row else 0
        self.sim = Simulation(json.loads(row['payload'])) if row else Simulation()
        if not row:
            with self.db:
                self._persist()

    def _persist(self):
        for event in self.sim.pending:
            self.db.execute('INSERT INTO events VALUES (?,?,?,?,?,?)',
                            (event['run_id'], event['seq'], event['day'], event['npc_id'], event['type'], encode(event)))
        self.revision += 1
        self.db.execute('INSERT OR REPLACE INTO world_state VALUES (1,?,?)', (self.revision, encode(self.sim.state)))

    def mutate(self, callback):
        with self.lock:
            old_state, old_revision = copy.deepcopy(self.sim.state), self.revision
            self.sim.pending.clear()
            try:
                with self.db:
                    result = callback()
                    self._persist()
            except Exception:
                self.sim = Simulation(old_state)
                self.revision = old_revision
                raise
            self.sim.pending.clear()
            return result

    def view(self):
        with self.lock:
            return dict(self.sim.view(), revision=self.revision, recent_events=self.events(limit=6, latest=True))

    def advance(self, ticks):
        self.mutate(lambda: self.sim.advance(ticks))
        return self.view()

    def controls(self, data):
        self.mutate(lambda: self.sim.controls(**data))
        return self.view()

    def reset(self, minute=470):
        if isinstance(minute, bool) or not isinstance(minute, int) or not 0 <= minute < 1440:
            raise ValueError('start_minute 必须为 0～1439 的整数')
        def change():
            self.sim = Simulation(start_minute=minute)
        self.mutate(change)
        return self.view()

    def events(self, npc=None, day=None, after=0, limit=100, latest=False, run_id=None):
        with self.lock:
            sql = 'SELECT payload FROM events WHERE run_id=? AND seq>?'
            args = [run_id or self.sim.state['run_id'], after]
            if npc:
                sql += ' AND npc_id=?'
                args.append(npc)
            if day is not None:
                sql += ' AND day=?'
                args.append(day)
            sql += ' ORDER BY seq ' + ('DESC' if latest else 'ASC') + ' LIMIT ?'
            args.append(limit)
            result = [json.loads(row[0]) for row in self.db.execute(sql, args)]
            return result[::-1] if latest else result

    def snapshots(self):
        with self.lock:
            return [dict(row) for row in self.db.execute('SELECT id,name,created_at,run_id,tick,event_seq FROM snapshots ORDER BY id DESC')]

    def save(self, name):
        if not isinstance(name, str) or not 1 <= len(name.strip()) <= 80:
            raise ValueError('存档名称需为 1～80 个字符')
        def change():
            self.sim.emit('snapshot_saved', message=f'保存存档：{name}')
            cursor = self.db.execute('INSERT INTO snapshots(name,created_at,run_id,tick,event_seq,payload) VALUES (?,?,?,?,?,?)',
                                     (name, datetime.now(timezone.utc).isoformat(), self.sim.state['run_id'],
                                      self.sim.state['tick'], self.sim.state['event_seq'], encode(self.sim.state)))
            return cursor.lastrowid
        snapshot_id = self.mutate(change)
        return dict(snapshot_id=snapshot_id, state=self.view())

    def restore(self, snapshot_id):
        def change():
            row = self.db.execute('SELECT * FROM snapshots WHERE id=?', (snapshot_id,)).fetchone()
            if not row:
                raise KeyError('存档不存在')
            restored = Simulation(json.loads(row['payload']))
            source_run = restored.state['run_id']
            new_run = uuid.uuid4().hex
            # Fork the saved event prefix; retain the abandoned future in its original run.
            for event in self.events(after=0, limit=2**31-1, run_id=source_run):
                if event['seq'] > row['event_seq']:
                    break
                event['run_id'] = new_run
                self.db.execute('INSERT INTO events VALUES (?,?,?,?,?,?)',
                                (new_run, event['seq'], event['day'], event['npc_id'], event['type'], encode(event)))
            restored.state['run_id'] = new_run
            self.sim = restored
            self.sim.emit('snapshot_restored', message=f"恢复存档：{row['name']}", snapshot_id=snapshot_id, source_run_id=source_run)
        self.mutate(change)
        return self.view()

    def close(self):
        with self.lock:
            self.db.close()
            self.lease.close()
