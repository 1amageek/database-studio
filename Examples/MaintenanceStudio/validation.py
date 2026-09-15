"""Sample-owned equipment projection and real SHACL validation checks."""
import copy
import json

ENTITY = 'MaintenanceStatement'
INDEX = 'maintenance_equipment_rdf'


def iri(value):
    return {'$type': 'rdfTerm', 'value': {'kind': 'iri', 'value': value}}


def extend_schema(manifest):
    entity = copy.deepcopy(manifest['entities'][0])
    entity['name'] = ENTITY
    entity['directory']['components'][-1]['value'] = ENTITY
    names = ('id', 'subject', 'predicate', 'object', 'graph')
    entity['fields'] = [dict(name=name, number=i+1, type='string' if i == 0 else 'rdfTerm',
        optional=False, array=False, referenceTargetEntity=None, defaultValue=None)
        for i, name in enumerate(names)]
    definition = dict(kind='graph', representation='rdf', includedFields=[])
    definition.update({name: dict(name=name, number=i+1) for i, name in enumerate(names) if i})
    entity['indexes'] = [dict(entity=ENTITY, declaration=dict(name=INDEX, definition=definition))]
    manifest['entities'].append(entity)


def project(rows):
    result = []
    for equipment in rows['Equipment']:
        for field in ('equipmentType', 'lineID'):
            result.append(dict(id={'$type': 'string', 'value': equipment['id']+'-'+field},
                subject=iri('urn:maintenance:'+equipment['id']),
                predicate=iri('urn:maintenance:'+field),
                object=iri('urn:maintenance:'+equipment[field]),
                graph=iri('urn:maintenance:'+equipment['factoryID'])))
    return result


def verify(command, rows, evidence, *, seed):
    statements = project(rows)
    def insert(row, key):
        command('entity', 'insert', ENTITY, json.dumps(row['id']),
            json.dumps({'$type': 'object', 'value': row}), '--idempotency-key', key)
    def validate(factory):
        return command('shacl', 'validate', 'urn:maintenance:shapes', '--entity', ENTITY,
            '--index', INDEX, '--data-graph', json.dumps(iri('urn:maintenance:'+factory)), '--output', 'json')
    def require_normal():
        for factory in rows['Factory']:
            report = validate(factory['id'])
            if report != [dict(type='validationSummary', conforms=True, issueCount='0')]:
                raise RuntimeError('Equipment validation failed: '+json.dumps(report))
    if seed:
        for row in statements:
            insert(row, 'projection-'+row['id']['value'])
    count = command('query', 'sql', f'SELECT COUNT(*) AS sample_count FROM {ENTITY}', '--output', 'json')
    if len(count) != 1 or int(count[0]['sample_count']['value']) != 360:
        raise RuntimeError('Equipment RDF projection count mismatch')
    require_normal()
    if seed:
        removed = statements[1]
        command('entity', 'delete', ENTITY, json.dumps(removed['id']), '--idempotency-key', 'projection-delete-line')
        report = validate(rows['Equipment'][0]['factoryID'])
        evidence['shaclViolation'] = report
        if (len(report) != 2 or report[0] != dict(type='validationSummary', conforms=False, issueCount='1')
                or report[1]['focusNode'] != removed['subject']):
            raise RuntimeError('Missing equipment line was not reported precisely: '+json.dumps(report))
        insert(removed, 'projection-restore-line')
        require_normal()
        evidence['shaclValidated'] = True
    else:
        evidence['shaclRestartVerified'] = True
    evidence['projectionCount'] = 360
