#!/usr/bin/env python3
"""Freeze a connected induced graph from recorded Wikidata SPARQL responses."""
import argparse
import hashlib
import heapq
import json
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path


def prepare(cache: Path) -> dict:
    labels, triples, queries = {}, set(), []
    paths = sorted(cache.glob('batch-*.json')) + sorted(cache.glob('makers-*.json'))
    if len(paths) != 15:
        raise ValueError('Expected 12 model batches and 3 manufacturer batches')
    for path in paths:
        query = path.with_suffix('.rq')
        queries.append({'query': query.read_text(), 'responseSHA256': hashlib.sha256(path.read_bytes()).hexdigest()})
        for row in json.loads(path.read_text())['results']['bindings']:
            subject, predicate, obj = (row[key]['value'] for key in ('item', 'predicate', 'value'))
            if not all(value.startswith('http://www.wikidata.org/entity/Q') for value in (subject, obj)):
                raise ValueError('Unexpected non-entity endpoint')
            triples.add((subject, predicate, obj))
            for key in ('item', 'value'):
                labels[row[key]['value']] = row[key + 'Label']['value']
    adjacency = defaultdict(set)
    for subject, _, obj in triples:
        adjacency[subject].add(obj)
        adjacency[obj].add(subject)
    root = 'http://www.wikidata.org/entity/Q3231690'
    selected, queued, frontier = set(), {root}, [(-len(adjacency[root]), root)]
    while frontier and len(selected) < 1000:
        _, node = heapq.heappop(frontier)
        selected.add(node)
        for neighbor in sorted(adjacency[node]):
            if neighbor not in queued:
                queued.add(neighbor)
                heapq.heappush(frontier, (-len(adjacency[neighbor]), neighbor))
    if len(selected) != 1000:
        raise ValueError('Source graph cannot supply 1000 connected entities')
    retained = sorted(t for t in triples if t[0] in selected and t[2] in selected)
    if len(retained) > 4096:
        raise ValueError('Induced graph exceeds spatial relationship admission; do not truncate')
    properties_path = cache / 'properties.json'
    properties = json.loads(properties_path.read_text())['results']['bindings']
    property_labels = {'http://www.wikidata.org/prop/direct/' + r['property']['value'].rsplit('/', 1)[1]: r['label']['value'] for r in properties}
    manifest = {'source': 'Wikidata', 'sourceURL': 'https://www.wikidata.org/', 'license': 'CC0-1.0',
                'retrievedAt': datetime.fromtimestamp(max(p.stat().st_mtime for p in paths), timezone.utc).isoformat(),
                'selection': 'Connected 1000-entity degree-priority traversal from automobile model Q3231690; retain every fetched statement between selected endpoints. This is a bounded sample, not the complete automotive industry.',
                'sourceEntityCount': len(labels), 'sourceRelationCount': len(triples),
                'excludedEntityCount': len(labels) - len(selected), 'excludedRelationCount': len(triples) - len(retained),
                'labels': {node: labels[node] for node in sorted(selected)}, 'triples': retained,
                'propertyLabels': property_labels,
                'queries': queries + [{'query': (cache / 'models.rq').read_text(), 'responseSHA256': hashlib.sha256((cache / 'models.json').read_bytes()).hexdigest()},
                                      {'query': properties_path.with_suffix('.rq').read_text(), 'responseSHA256': hashlib.sha256(properties_path.read_bytes()).hexdigest()}]}
    # Verify the artifact independently from the traversal's mutable frontier.
    assert len(manifest['labels']) == 1000 and len(set(retained)) == len(retained)
    assert all(s in selected and o in selected and p in property_labels for s, p, o in retained)
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    snapshot = prepare(args.cache)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({key: value for key, value in snapshot.items() if key not in ('labels', 'triples', 'propertyLabels', 'queries')}, indent=2))
    print('Selected:', len(snapshot['labels']), 'entities /', len(snapshot['triples']), 'relationships')
