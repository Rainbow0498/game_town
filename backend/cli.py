"""Run exactly one day without Godot or a window, or restore a SQLite snapshot."""
import argparse
import json
from pathlib import Path
from storage import Store


def main():
    parser = argparse.ArgumentParser(description='无界面模拟与存档工具')
    parser.add_argument('command', choices=['simulate-day', 'restore', 'state', 'snapshots'])
    parser.add_argument('--db', required=True)
    parser.add_argument('--snapshot-id', type=int)
    parser.add_argument('--name', default='完整一天')
    args = parser.parse_args()
    Path(args.db).parent.mkdir(parents=True, exist_ok=True)
    store = Store(args.db)
    try:
        if args.command == 'simulate-day':
            store.controls({'paused': True})
            store.advance(2880)
            result = store.save(args.name)
        elif args.command == 'restore':
            if not args.snapshot_id: parser.error('restore 需要 --snapshot-id')
            result = store.restore(args.snapshot_id)
        elif args.command == 'snapshots': result = store.snapshots()
        else: result = store.view()
        print(json.dumps(result, ensure_ascii=False, indent=2))
    finally: store.close()


if __name__ == '__main__': main()
