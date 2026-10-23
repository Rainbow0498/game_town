import copy
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch

from simulation import Simulation, DEFINITION
from storage import Store
from server import Service, make_server

ROOT = Path(__file__).resolve().parents[1]


def behavior(state):
    result = {key:copy.deepcopy(state[key]) for key in ('tick', 'npcs', 'paused', 'speed', 'schema_version')}
    keys = ('id', 'position', 'route', 'facing', 'moving', 'animation_time', 'current_entry', 'current_day', 'arrived', 'last_place', 'visits')
    result['npcs'] = [{key:npc[key] for key in keys} for npc in result['npcs']]
    return result


class TownTests(unittest.TestCase):
    def setUp(self):
        (ROOT / '.runtime').mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=ROOT / '.runtime')
        self.path = Path(self.temp.name) / 'test.sqlite3'
        self.store = Store(self.path)

    def tearDown(self):
        self.store.close()
        self.temp.cleanup()

    def test_day_all_npcs_reach_every_scheduled_place(self):
        self.store.reset(0)
        for _ in range(2880):
            self.store.sim.advance(1)
            for npc in self.store.sim.state['npcs']:
                self.assertTrue(self.store.sim.walkable((int(npc['position'][0]//16), int(npc['position'][1]//16))))
        self.assertEqual((self.store.sim.day, self.store.sim.minute), (2, 0))
        for npc, data in zip(self.store.sim.state['npcs'], DEFINITION['residents']):
            self.assertTrue({e['place'] for e in data['schedule']} <= npc['visits'].keys())
        events = self.store.sim.pending
        self.assertIn('day_started', [e['type'] for e in events])
        for npc in self.store.sim.state['npcs']:
            for kind in ('departed', 'arrived', 'activity_started', 'activity_finished'):
                self.assertTrue(any(e['npc_id'] == npc['id'] and e['type'] == kind for e in events))
        self.assertEqual([e['seq'] for e in events], list(range(events[0]['seq'], events[0]['seq']+len(events))))

    def test_fixed_step_independent_of_batch_size(self):
        a = Simulation(start_minute=0)
        b = Simulation(copy.deepcopy(a.state))
        initial_count = len(a.pending)
        a.advance(2880)
        for _ in range(96): b.advance(30)
        self.assertEqual(a.state, b.state)
        self.assertEqual(a.pending[initial_count:], b.pending)

    def test_paths_are_connected_cardinal_and_obstacle_free(self):
        sim = self.store.sim
        for origin in DEFINITION['places']:
            for target in DEFINITION['places']:
                path = sim.path(sim.center(origin), target)
                self.assertEqual(path[-1], sim.center(target))
                for a, b in zip(path, path[1:]):
                    self.assertAlmostEqual(abs(a[0]-b[0]) + abs(a[1]-b[1]), 16)
                    self.assertTrue(sim.walkable((int(b[0]//16), int(b[1]//16))))

    def test_mid_walk_save_restore_and_identical_continuation(self):
        self.store.reset(480)
        self.store.advance(3)
        self.assertTrue(any(n['route'] for n in self.store.sim.state['npcs']))
        snapshot_id = self.store.save('路途中存档')['snapshot_id']
        saved = copy.deepcopy(self.store.sim.state)
        expected = Simulation(saved)
        expected.advance(600)
        original_run = saved['run_id']
        self.store.advance(1000)
        old_events = self.store.events(run_id=original_run, limit=1000)
        restored = self.store.restore(snapshot_id)
        self.assertEqual(behavior(saved), behavior(restored))
        self.assertNotEqual(original_run, restored['run_id'])
        self.assertEqual(self.store.events(run_id=original_run, limit=1000), old_events)
        self.store.advance(600)
        self.assertEqual(behavior(expected.state), behavior(self.store.sim.state))
        self.assertEqual(len(self.store.events(npc='mia', limit=1000)), len([e for e in self.store.events(limit=1000) if e['npc_id'] == 'mia']))

    def test_process_restart_recovers_exact_current_world(self):
        self.store.advance(97)
        self.store.controls({'paused':True, 'speed':12})
        before = self.store.view()
        self.store.close()
        self.store = Store(self.path)
        self.assertEqual(self.store.view(), before)

    def test_database_has_only_one_authoritative_writer(self):
        before = self.store.view()
        with self.assertRaises(RuntimeError): Store(self.path)
        self.assertEqual(before, self.store.view())

    def test_transaction_failure_keeps_state_and_events_unchanged(self):
        before = self.store.view()
        events = self.store.events(limit=1000)
        def failing():
            self.store.sim.advance(100)
            self.store.db.execute('INSERT INTO missing_table VALUES (1)')
        with self.assertRaises(sqlite3.OperationalError): self.store.mutate(failing)
        self.assertEqual(before, self.store.view())
        self.assertEqual(events, self.store.events(limit=1000))
        with self.assertRaises(KeyError): self.store.restore(999)
        self.assertEqual(before, self.store.view())

    def test_events_survive_restart_and_support_day_actor_cursor(self):
        self.store.reset(0)
        self.store.advance(2880)
        all_events = self.store.events(limit=1000)
        first = self.store.events(npc='leo', day=1, limit=3)
        next_page = self.store.events(npc='leo', day=1, after=first[-1]['seq'], limit=100)
        expected = [e for e in all_events if e['npc_id'] == 'leo' and e['day'] == 1]
        self.assertEqual(first+next_page, expected)
        self.store.close()
        self.store = Store(self.path)
        self.assertEqual(all_events, self.store.events(limit=1000))
        self.assertEqual(self.store.db.execute('PRAGMA integrity_check').fetchone()[0], 'ok')

    def test_corrupt_or_newer_snapshot_rejected_without_overwrite(self):
        snap = self.store.save('test')['snapshot_id']
        state = copy.deepcopy(self.store.sim.state)
        state['schema_version'] = 999
        with self.store.db:
            self.store.db.execute('UPDATE snapshots SET payload=? WHERE id=?', (json.dumps(state), snap))
        before = self.store.view()
        with self.assertRaises(ValueError): self.store.restore(snap)
        self.assertEqual(before, self.store.view())

    def test_cli_day_and_restore_in_separate_processes(self):
        db = str(Path(self.temp.name) / 'cli.sqlite3')
        env = dict(os.environ, PYTHONIOENCODING='utf-8')
        def run(*args):
            result = subprocess.run([sys.executable, str(ROOT/'backend/cli.py'), *args, '--db', db],
                                    capture_output=True, text=True, encoding='utf-8', env=env, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)
        first = run('simulate-day')
        self.assertEqual(first['state']['tick'], (470+1440)*2)
        run('simulate-day')
        restored = run('restore', '--snapshot-id', str(first['snapshot_id']))
        self.assertEqual(behavior(first['state']), behavior(restored))
        restarted = run('state')
        self.assertEqual(restored, restarted)


class HttpTests(unittest.TestCase):
    def setUp(self):
        (ROOT / '.runtime').mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=ROOT/'.runtime')
        self.service = Service(Path(self.temp.name)/'api.sqlite3')
        self.server = make_server(self.service, 0)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f'http://127.0.0.1:{self.server.server_port}'

    def tearDown(self):
        self.server.shutdown()
        self.thread.join(2)
        self.server.server_close()
        self.service.store.close()
        self.temp.cleanup()

    def request(self, path, data=None, status=200):
        request = urllib.request.Request(self.base+path, data=json.dumps(data).encode() if data is not None else None,
                                         headers={'Content-Type':'application/json'})
        try: response = urllib.request.urlopen(request, timeout=10)
        except urllib.error.HTTPError as exc: response = exc
        self.assertEqual(response.status, status)
        return json.loads(response.read())

    def test_real_http_complete_day_save_restore(self):
        self.assertEqual(self.request('/health')['status'], 'ok')
        self.request('/reset', {'start_minute':0})
        self.request('/clock', {'paused':True})
        result = self.request('/advance', {'minutes':1440})
        self.assertEqual((result['day'], result['minute']), (2, 0))
        self.assertEqual(len(self.request('/npcs')), 3)
        self.assertEqual(self.request('/npcs/mia')['id'], 'mia')
        saved = self.request('/save', {'name':'一天验收'})
        self.request('/advance', {'minutes':120})
        restored = self.request('/restore', {'snapshot_id':saved['snapshot_id']})
        self.assertEqual(behavior(saved['state']), behavior(restored))
        self.assertEqual(self.request('/snapshots')[0]['name'], '一天验收')
        events = self.request('/events?npc=mia&day=1&limit=1000')['events']
        self.assertTrue(events)
        self.assertTrue(all(e['npc_id'] == 'mia' and e['day'] == 1 for e in events))

    def test_bad_input_and_concurrent_requests(self):
        before = self.request('/world')
        for body in ({'minutes':-1}, {'minutes':1441}, {'minutes':True}, {'minutes':0.1}):
            self.request('/advance', body, 400)
        self.request('/clock', {'speed':2}, 400)
        self.request('/clock', {'paused':'false'}, 400)
        self.request('/restore', {'snapshot_id':9999}, 404)
        self.request('/events?limit=1001', status=400)
        self.request('/missing', status=404)
        self.assertEqual(before, self.request('/world'))
        with ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(lambda _:self.request('/advance', {'minutes':10}), range(8)))
        self.assertEqual(self.request('/world')['tick'], before['tick'] + 160)

    def test_realtime_clock_pause_speed_same_fixed_steps(self):
        self.service.last_time = 100
        with patch('server.time.monotonic', return_value=101): self.service.update()
        self.assertEqual(self.service.store.sim.state['tick'], 944)
        self.service.store.controls({'paused':True})
        with patch('server.time.monotonic', return_value=102): self.service.update()
        self.assertEqual(self.service.store.sim.state['tick'], 944)
        self.service.store.controls({'paused':False, 'speed':12})
        with patch('server.time.monotonic', return_value=103): self.service.update()
        self.assertEqual(self.service.store.sim.state['tick'], 992)


if __name__ == '__main__': unittest.main(verbosity=2)
