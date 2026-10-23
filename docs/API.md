# 橡树镇本地 API · v0.2.0

默认地址：`http://127.0.0.1:8765`。请求和响应为 UTF-8 JSON；所有接口操作同一世界。服务启动后会实时推进，验收时可使用 `--paused` 或先设置暂停。标准库服务只用于本机原型。

## 查询

- `GET /health`：`status`、`schema_version`、`service`。
- `GET /definition`：共同地图尺寸、建筑、障碍、地点、NPC 资料和日程。
- `GET /world`：世界状态，字段见下文。
- `GET /npcs`：3 位 NPC 的完整状态数组。
- `GET /npcs/{id}`：`mia`、`oliver`、`leo` 中一个角色。
- `GET /snapshots`：按 ID 倒序的存档元信息，包含 `id/name/created_at/run_id/tick/event_seq`。
- `GET /events?npc=mia&day=1&after=0&limit=100`：按事件序号升序分页。`npc/day` 可省略；`after` 为排除性游标，默认 0；`limit` 范围 1～1000，默认 100。返回 `events` 与 `next_after`。
- `GET /events?latest=true&limit=6`：最近 6 条，仍按时间升序返回，便于展示。
- `GET /events?run_id=...`：查询历史运行分支，省略则查询当前世界。

`/world` 的主要字段：

```json
{
  "schema_version": 1,
  "revision": 42,
  "run_id": "运行分支标识",
  "tick": 960,
  "day": 1,
  "minute": 480.0,
  "paused": true,
  "speed": 1,
  "event_seq": 19,
  "weather": "晴",
  "temperature": 22,
  "period": "清晨",
  "npcs": [],
  "places": {},
  "recent_events": []
}
```

上例中的数组和字典仅为字段占位。实际 `npcs` 包含 3 位角色的 `id/name/role/bio/color/schedule` 和 `position/route/facing/moving/animation_time/current_entry/current_day/arrived/last_place/visits/activity/destination/destination_name`。坐标采用原始 544 × 368 地图像素；朝向 `0/1/2/3` 对应下/左/右/上。`places` 包含地点名称、网格坐标及已抵达的 `occupants`。

`tick` 是从第 1 天 00:00 开始累计的 30 秒单位；`day/minute/period` 都由它派生。`revision` 是 SQLite 每次成功提交后增加的版本，不是游戏时间。

## 控制

所有 POST 均需 JSON 对象请求体。

| 接口 | 请求示例 | 结果 |
| --- | --- | --- |
| `POST /clock` | `{"paused":true,"speed":12}` | 设置暂停和速度，任一字段可省略；速度只支持 1/4/12 |
| `POST /advance` | `{"minutes":1440}` | 推进完整一天；0～1440，必须为 0.5 的倍数，默认 60 |
| `POST /save` | `{"name":"第一天验收"}` | 返回 `snapshot_id` 与保存后的 `state` |
| `POST /restore` | `{"snapshot_id":1}` | 恢复完整行为状态与存档之前日志，返回当前世界 |
| `POST /reset` | `{"start_minute":0}` | 新世界从第 1 天 00:00 开始；整数 0～1439，默认 470 |

`/advance` 明确手动推进，暂停状态不会阻止它。推进经过所有固定步，保留全部中间活动，不能用于倒退；倒退使用恢复存档。实时驱动与所有请求由同一把锁串行提交，避免并发请求覆盖世界。

PowerShell 验收示例：

```powershell
$base = 'http://127.0.0.1:8765'
Invoke-RestMethod "$base/clock" -Method Post -ContentType 'application/json' -Body '{"paused":true}'
Invoke-RestMethod "$base/reset" -Method Post -ContentType 'application/json' -Body '{"start_minute":0}'
Invoke-RestMethod "$base/clock" -Method Post -ContentType 'application/json' -Body '{"paused":true}'
Invoke-RestMethod "$base/advance" -Method Post -ContentType 'application/json' -Body '{"minutes":1440}'
$save = Invoke-RestMethod "$base/save" -Method Post -ContentType 'application/json' -Body '{"name":"day-one"}'
Invoke-RestMethod "$base/advance" -Method Post -ContentType 'application/json' -Body '{"minutes":60}'
$body = @{snapshot_id=$save.snapshot_id} | ConvertTo-Json
Invoke-RestMethod "$base/restore" -Method Post -ContentType 'application/json' -Body $body
Invoke-RestMethod "$base/events?npc=mia&day=1&limit=1000"
```

## 事件

记录类型：世界开始、日程计划、出发、抵达、活动开始、活动结束、未完成行程调整、跨天、时钟控制、保存和恢复。

```json
{
  "run_id": "运行分支标识",
  "seq": 12,
  "tick": 960,
  "day": 1,
  "minute": 480.0,
  "type": "departed",
  "npc_id": "mia",
  "message": "米娅出发前往橡树图书馆",
  "payload": {"place":"library","activity":"整理书架"}
}
```

同一运行分支内序号连续且唯一，所有角色使用同一游戏时钟。记录的是活动生命周期，不会逐帧重复写入静止行为。世界事件的 `npc_id` 为 `null`。

## 保存、恢复与错误

状态和新增事件在同一 SQLite 事务中保存。快照包含未完成路线，恢复不重新寻路；恢复时创建新运行分支，并复制到存档序号为止的事件。原分支和之后的历史事件不删除，旧存档仍可反复恢复。

服务重启直接恢复最后提交的当前状态；单进程占用锁阻止 CLI 和服务同时打开同一数据库。数据库模式和快照都带版本号，不兼容版本会拒绝加载。

- `200`：成功。
- `400`：无效参数、JSON 或不支持的存档版本。
- `404`：接口、角色或快照不存在。
- `500`：内部操作失败，事务回滚。

错误格式为 `{"error":"中文错误描述"}`。数据库是唯一持久化来源；不要在服务运行时直接编辑数据库，也不要对同一个数据库并行使用 CLI。
