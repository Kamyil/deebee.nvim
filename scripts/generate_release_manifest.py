#!/usr/bin/env python3

import argparse
import json
from pathlib import Path


def parse_checksums(path: Path) -> dict[str, str]:
    checksums: dict[str, str] = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        checksum = parts[0]
        name = parts[-1].lstrip('*')
        checksums[name] = checksum
    return checksums


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', required=True)
    parser.add_argument('--protocol-version', required=True, type=int)
    parser.add_argument('--dist-dir', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()

    dist_dir = Path(args.dist_dir)
    output = Path(args.output)
    checksums = parse_checksums(dist_dir / 'checksums.txt')

    assets = []
    for path in sorted(dist_dir.glob('deebee-worker-*')):
        assets.append(
            {
                'name': path.name,
                'size': path.stat().st_size,
                'sha256': checksums.get(path.name),
            }
        )

    manifest = {
        'version': args.version,
        'protocol_version': args.protocol_version,
        'assets': assets,
        'checksums_asset': 'checksums.txt',
    }

    output.write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    main()
