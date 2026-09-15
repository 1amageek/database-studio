#!/usr/bin/env python3
"""Generate a deterministic maintenance workspace without contacting a database."""
import argparse
import hashlib
import json
import random
from pathlib import Path

COUNTS = dict(Factory=2, ProductionLine=18, Equipment=180, Sensor=300,
              Technician=40, WorkOrder=260, Incident=200)


def generate(seed=20260915):
    rng = random.Random(seed)
    rows = {name: [] for name in COUNTS}
    def add(entity, **fields):
        rows[entity].append(dict(id=f'{entity.lower()}-{len(rows[entity])+1:04d}', **fields))
        return rows[entity][-1]
    for i in range(2):
        add('Factory', name=['East Factory', 'West Factory'][i], region=['Tokyo', 'Osaka'][i])
    for i in range(18):
        add('ProductionLine', name=f'Line {i+1:02d}', factoryID=rows['Factory'][i % 2]['id'])
    for i in range(180):
        line = rows['ProductionLine'][i % 18]
        add('Equipment', name=f'Equipment {i+1:03d}', lineID=line['id'], factoryID=line['factoryID'],
            equipmentType=['CNC', 'Press', 'Conveyor', 'Robot'][i % 4], criticality=rng.randint(1, 5))
    for i in range(300):
        equipment = rows['Equipment'][i % 180]
        add('Sensor', name=f'Sensor {i+1:03d}', equipmentID=equipment['id'], factoryID=equipment['factoryID'],
            sensorType=['Temperature', 'Vibration', 'Pressure'][i % 3], reading=rng.randint(10, 100))
    for i in range(40):
        add('Technician', name=f'Technician {i+1:02d}', factoryID=rows['Factory'][i % 2]['id'],
            specialty=['Mechanical', 'Electrical'][i % 2])
    for i in range(260):
        equipment = rng.choice(rows['Equipment'])
        technician = rng.choice([t for t in rows['Technician'] if t['factoryID'] == equipment['factoryID']])
        add('WorkOrder', name=f'Inspection {i+1:03d}', equipmentID=equipment['id'], factoryID=equipment['factoryID'],
            technicianID=technician['id'], status=['Open', 'InProgress', 'Completed'][i % 3],
            priority=rng.randint(1, 5), scheduledAt=f'2026-09-{1+i%28:02d}T09:00:00Z')
    for i in range(200):
        sensor = rng.choice(rows['Sensor'])
        add('Incident', name=f'Incident {i+1:03d}', sensorID=sensor['id'], equipmentID=sensor['equipmentID'],
            factoryID=sensor['factoryID'], severity=rng.randint(1, 5),
            occurredAt=f'2026-09-{1+i%28:02d}T10:00:00Z', resolved=i % 3 == 0)
    validate(rows)
    return rows


def validate(rows):
    assert {k: len(v) for k, v in rows.items()} == COUNTS
    by_id = {row['id']: (kind, row) for kind, records in rows.items() for row in records}
    assert len(by_id) == 1000
    targets = dict(factoryID='Factory', lineID='ProductionLine', equipmentID='Equipment',
                   sensorID='Sensor', technicianID='Technician')
    for records in rows.values():
        for row in records:
            for field, target in targets.items():
                if field in row:
                    kind, parent = by_id[row[field]]
                    assert kind == target
                    if 'factoryID' in parent:
                        assert row['factoryID'] == parent['factoryID']


def value_type(value):
    return 'bool' if isinstance(value, bool) else 'int64' if isinstance(value, int) else 'string'


def tagged(value):
    kind = value_type(value)
    return {'$type': kind, 'value': str(value) if kind == 'int64' else value}


def schema(rows):
    entities = []
    for name, records in rows.items():
        fields = [dict(name=key, number=i+1, type=value_type(value), optional=False,
                       array=False, referenceTargetEntity=None, defaultValue=None)
                  for i, (key, value) in enumerate(records[0].items())]
        entities.append(dict(name=name, identifierType={'kind': 'string'}, fields=fields,
            directory={'components': [{'kind': 'static', 'value': 'maintenance-sample'},
                                      {'kind': 'static', 'value': name}], 'layer': 'default'},
            indexes=[], relationships=[], fieldAccessRules=[], enumMetadata={}, ontology=None,
            polymorphicMembership=None))
    return dict(formatVersion=3, schemaVersion=dict(major=1, minor=0, patch=0), entities=entities)


def write_bundle(output, seed):
    output.mkdir(parents=True, exist_ok=False)
    rows = generate(seed)
    def write(name, value):
        (output/name).write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n')
    write('records.json', rows)
    write('schema.json', schema(rows))
    write('typed-records.json', {kind: [{key: tagged(value) for key, value in row.items()}
                                      for row in records] for kind, records in rows.items()})
    statements = []
    def literal(value):
        if isinstance(value, bool): return 'TRUE' if value else 'FALSE'
        if isinstance(value, int): return str(value)
        return "'" + value.replace("'", "''") + "'"
    for kind, records in rows.items():
        for row in records:
            statements.append(f'INSERT INTO {kind} ({", ".join(row)}) VALUES ({", ".join(map(literal, row.values()))});')
    (output/'seed.sql').write_text('\n'.join(statements)+'\n')
    write('expected.json', dict(seed=seed, total=1000, counts=COUNTS,
        openWorkOrders=sum(r['status'] == 'Open' for r in rows['WorkOrder']),
        unresolvedIncidents=sum(not r['resolved'] for r in rows['Incident']),
        factories={f['id']: sum(r.get('factoryID') == f['id'] for records in rows.values() for r in records)
                   for f in rows['Factory']}))
    namespace = 'urn:maintenance:'
    rdf_type = '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>'
    subclass = '<http://www.w3.org/2000/01/rdf-schema#subClassOf>'
    label = '<http://www.w3.org/2000/01/rdf-schema#label>'
    owl_class = '<http://www.w3.org/2002/07/owl#Class>'
    links = {'factoryID', 'lineID', 'equipmentID', 'sensorID', 'technicianID'}
    ontology = [f'<{namespace}{name}> {rdf_type} {owl_class} .' for name in rows]
    hierarchy = {'MachiningEquipment': 'Equipment', 'TransportEquipment': 'Equipment',
                 'CNC': 'MachiningEquipment', 'Press': 'MachiningEquipment',
                 'Conveyor': 'TransportEquipment', 'Robot': 'TransportEquipment'}
    for child, parent in hierarchy.items():
        ontology.extend([f'<{namespace}{child}> {rdf_type} {owl_class} .',
                         f'<{namespace}{child}> {subclass} <{namespace}{parent}> .'])
    graphs = {factory['id']: [] for factory in rows['Factory']}
    for kind, records in rows.items():
        for row in records:
            factory = row.get('factoryID', row['id'])
            subject = f'<{namespace}{row["id"]}>'
            graph = f'<{namespace}{factory}>'
            class_name = row.get('equipmentType', kind)
            triples = [(rdf_type, f'<{namespace}{class_name}>'), (label, json.dumps(row['name']))]
            for key, value in row.items():
                if key in ('id', 'name'): continue
                if key in links:
                    obj = f'<{namespace}{value}>'
                else:
                    datatype = {'bool': 'boolean', 'int64': 'integer', 'string': 'string'}[value_type(value)]
                    lexical = str(value).lower() if isinstance(value, bool) else str(value)
                    obj = json.dumps(lexical) + f'^^<http://www.w3.org/2001/XMLSchema#{datatype}>'
                triples.append((f'<{namespace}{key}>', obj))
            graphs[factory].extend(f'{subject} {predicate} {obj} {graph} .' for predicate, obj in triples)
    (output/'ontology.nq').write_text('\n'.join(ontology)+'\n')
    (output/'dataset.nq').write_text('\n'.join(line for lines in graphs.values() for line in lines)+'\n')
    for factory, lines in graphs.items():
        (output/f'{factory}.nq').write_text('\n'.join(lines)+'\n')
    shape = '<urn:maintenance:EquipmentShape>'
    prop = '<urn:maintenance:EquipmentLineShape>'
    sh = 'http://www.w3.org/ns/shacl#'
    shapes = [f'{shape} {rdf_type} <{sh}NodeShape> .',
              f'{shape} <{sh}targetSubjectsOf> <{namespace}equipmentType> .',
              f'{shape} <{sh}property> {prop} .',
              f'{prop} <{sh}path> <{namespace}lineID> .',
              f'{prop} <{sh}minCount> "1"^^<http://www.w3.org/2001/XMLSchema#integer> .',
              f'{prop} <{sh}nodeKind> <{sh}IRI> .']
    (output/'shapes.nq').write_text('\n'.join(shapes)+'\n')
    write('checksums.json', {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(output.iterdir())})
    return rows


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--seed', type=int, default=20260915)
    args = parser.parse_args()
    write_bundle(args.output, args.seed)
    print(f'Generated 1000 records in {args.output}. No database was modified.')
