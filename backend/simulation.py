"""Deterministic NPC-only world. No renderer, wall clock, database or HTTP dependency."""
from __future__ import annotations

import copy
import heapq
import json
import math
import uuid
from pathlib import Path

DEFINITION = json.loads((Path(__file__).resolve().parents[1] / 'data/town.json').read_text(encoding='utf-8'))
SCHEMA_VERSION = 1
STEP_SECONDS = 30
TICKS_PER_DAY = 86400 // STEP_SECONDS
NPC_STEP_PIXELS = 23 * STEP_SECONDS / 120  # Same movement/clock ratio as milestone 1.


class Simulation:
    def __init__(self, state=None, start_minute=470):
        self.definition = DEFINITION
        self.blocked = self._obstacles()
        self.pending = []
        if state is not None:
            self.validate(state)
            self.state = copy.deepcopy(state)
        else:
            self.state = dict(schema_version=SCHEMA_VERSION, run_id=uuid.uuid4().hex,
                              tick=int(start_minute * 2), event_seq=0, paused=False,
                              speed=1, npcs=[])
            self.emit('world_started', message='小镇开始新的一天')
            for data in self.definition['residents']:
                npc = dict(id=data['id'], position=self.center(data['home']), route=[],
                           facing=0, moving=False, animation_time=0.0, current_entry=-1,
                           current_day=-1, arrived=False, last_place='', visits={})
                self.state['npcs'].append(npc)
                self._schedule(npc)
                self._move(npc, 0)

    def _obstacles(self):
        w, h = self.definition['width'], self.definition['height']
        result = {(x, y) for y in range(h) for x in range(w) if x in (0, w-1) or y in (0, h-1)}
        for rect in [b['rect'] for b in self.definition['buildings']] + self.definition['solid_rects']:
            x, y, width, height = rect
            result.update((xx, yy) for xx in range(x, x+width) for yy in range(y, y+height))
        result.update(map(tuple, self.definition['trees']))
        return result

    def walkable(self, cell):
        x, y = cell
        return 0 <= x < self.definition['width'] and 0 <= y < self.definition['height'] and tuple(cell) not in self.blocked

    def center(self, place):
        x, y = self.definition['places'][place]['cell']
        return [x * 16 + 8.0, y * 16 + 8.0]

    def path(self, position, place):
        start = (int(position[0] // 16), int(position[1] // 16))
        goal = tuple(self.definition['places'][place]['cell'])
        frontier = [(0, start)]
        parents = {start: None}
        costs = {start: 0}
        while frontier:
            _, current = heapq.heappop(frontier)
            if current == goal:
                cells = []
                while current is not None:
                    cells.append([current[0] * 16 + 8.0, current[1] * 16 + 8.0])
                    current = parents[current]
                return cells[::-1]
            for dx, dy in [(0, -1), (-1, 0), (1, 0), (0, 1)]:
                neighbor = (current[0]+dx, current[1]+dy)
                cost = costs[current] + 1
                if self.walkable(neighbor) and cost < costs.get(neighbor, math.inf):
                    costs[neighbor] = cost
                    parents[neighbor] = current
                    priority = cost + abs(neighbor[0]-goal[0]) + abs(neighbor[1]-goal[1])
                    heapq.heappush(frontier, (priority, neighbor))
        raise ValueError(f'地点不可达：{place}')

    @property
    def day(self):
        return self.state['tick'] // TICKS_PER_DAY + 1

    @property
    def minute(self):
        return self.state['tick'] % TICKS_PER_DAY / 2

    def emit(self, kind, npc=None, message='', **payload):
        self.state['event_seq'] += 1
        self.pending.append(dict(run_id=self.state['run_id'], seq=self.state['event_seq'],
                                 tick=self.state['tick'], day=self.day, minute=self.minute,
                                 type=kind, npc_id=npc['id'] if npc else None,
                                 message=message, payload=payload))

    def _schedule(self, npc):
        data = next(d for d in self.definition['residents'] if d['id'] == npc['id'])
        active = max(i for i, e in enumerate(data['schedule']) if e['time'] <= self.minute)
        if active == npc['current_entry'] and self.day == npc['current_day']:
            return
        if npc['current_entry'] >= 0:
            old = data['schedule'][npc['current_entry']]
            self.emit('activity_finished' if npc['arrived'] else 'journey_interrupted', npc,
                      f"{data['name']}结束{old['activity']}" if npc['arrived'] else f"{data['name']}调整行程",
                      place=old['place'], activity=old['activity'])
        entry = data['schedule'][active]
        npc.update(current_entry=active, current_day=self.day, arrived=False)
        npc['route'] = self.path(npc['position'], entry['place'])
        if npc['route'] and math.dist(npc['position'], npc['route'][0]) < 1e-8:
            npc['route'].pop(0)
        npc['moving'] = bool(npc['route'])
        place_name = self.definition['places'][entry['place']]['name']
        self.emit('activity_planned', npc, f"{data['name']}计划{entry['activity']}", **entry)
        if npc['route']:
            self.emit('departed', npc, f"{data['name']}出发前往{place_name}", place=entry['place'], activity=entry['activity'])

    def _move(self, npc, distance):
        npc['animation_time'] += distance / 23
        while npc['route']:
            target = npc['route'][0]
            dx, dy = target[0]-npc['position'][0], target[1]-npc['position'][1]
            length = math.hypot(dx, dy)
            if length > 1e-8:
                npc['facing'] = (2 if dx > 0 else 1) if abs(dx) > abs(dy) else (0 if dy > 0 else 3)
            if length <= distance + 1e-8:
                npc['position'] = list(target)
                npc['route'].pop(0)
                distance -= length
            else:
                if distance > 0:
                    npc['position'] = [npc['position'][0]+dx/length*distance, npc['position'][1]+dy/length*distance]
                break
        npc['moving'] = bool(npc['route'])
        if not npc['route'] and not npc['arrived']:
            data = next(d for d in self.definition['residents'] if d['id'] == npc['id'])
            entry = data['schedule'][npc['current_entry']]
            npc.update(arrived=True, last_place=entry['place'])
            npc['visits'][entry['place']] = npc['visits'].get(entry['place'], 0) + 1
            self.emit('arrived', npc, f"{data['name']}抵达{self.definition['places'][entry['place']]['name']}", place=entry['place'])
            self.emit('activity_started', npc, f"{data['name']}开始{entry['activity']}", place=entry['place'], activity=entry['activity'])

    def advance(self, ticks):
        if isinstance(ticks, bool) or not isinstance(ticks, int) or not 0 <= ticks <= TICKS_PER_DAY:
            raise ValueError('一次推进范围为 0～2880 步（一天）')
        for _ in range(ticks):
            # Move the preceding interval, then apply tasks at the new boundary.
            for npc in self.state['npcs']:
                self._move(npc, NPC_STEP_PIXELS)
            self.state['tick'] += 1
            if self.state['tick'] % TICKS_PER_DAY == 0:
                self.emit('day_started', message=f'进入第 {self.day} 天')
            for npc in self.state['npcs']:
                self._schedule(npc)
                self._move(npc, 0)

    def controls(self, paused=None, speed=None):
        if paused is not None and not isinstance(paused, bool):
            raise ValueError('paused 必须为布尔值')
        if speed is not None and (isinstance(speed, bool) or speed not in (1, 4, 12)):
            raise ValueError('speed 只能为 1、4、12')
        for key, value in [('paused', paused), ('speed', speed)]:
            if value is not None and self.state[key] != value:
                self.state[key] = value
                self.emit('clock_changed', message='暂停时间' if self.state['paused'] else f"时间速度 {self.state['speed']}×", **{key:value})

    def view(self):
        result = copy.deepcopy(self.state)
        result.update(day=self.day, minute=self.minute,
                      weather='晴', temperature=22,
                      period='夜晚' if self.minute < 360 or self.minute >= 1200 else ('清晨' if self.minute < 660 else ('白昼' if self.minute < 1020 else '傍晚')))
        result['places'] = {key:dict(**value, occupants=[n['id'] for n in self.state['npcs'] if n['arrived'] and n['last_place'] == key]) for key, value in self.definition['places'].items()}
        for npc, data in zip(result['npcs'], self.definition['residents']):
            entry = data['schedule'][npc['current_entry']]
            npc.update(name=data['name'], role=data['role'], bio=data['bio'], color=data['color'],
                       schedule=data['schedule'], activity=entry['activity'], destination=entry['place'],
                       destination_name=self.definition['places'][entry['place']]['name'])
        return result

    def validate(self, state):
        if state.get('schema_version') != SCHEMA_VERSION:
            raise ValueError('不支持的存档版本')
        if not isinstance(state.get('tick'), int) or state['tick'] < 0:
            raise ValueError('无效的存档时钟')
        if [n['id'] for n in state['npcs']] != [d['id'] for d in self.definition['residents']]:
            raise ValueError('存档角色不匹配')
        for npc, data in zip(state['npcs'], self.definition['residents']):
            points = [npc['position']] + npc['route']
            for point in points:
                if len(point) != 2 or not all(isinstance(v, (int, float)) and math.isfinite(v) for v in point):
                    raise ValueError('存档坐标无效')
                if not self.walkable((int(point[0] // 16), int(point[1] // 16))):
                    raise ValueError('存档角色位于障碍物')
            if not 0 <= npc['current_entry'] < len(data['schedule']):
                raise ValueError('存档日程无效')
            for a, b in zip(points, points[1:]):
                if abs(a[0]-b[0]) > 1e-6 and abs(a[1]-b[1]) > 1e-6:
                    raise ValueError('存档包含斜向路径')
