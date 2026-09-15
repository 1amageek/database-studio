#!/usr/bin/env python3
"""Seed and inspect a fresh isolated sample server; always stop the owned process."""
import argparse
import json
import os
import select
import socket
import struct
import subprocess
import time
from pathlib import Path
from generate import COUNTS, tagged, write_bundle


def run(cli, server, directory):
    directory.mkdir(parents=True, exist_ok=False, mode=0o700)
    env = {k: v for k, v in os.environ.items() if not any(w in k.upper() for w in ('TOKEN', 'PASSWORD', 'SECRET', 'API_KEY'))}
    env['DATABASE_CLI_CONFIG_HOME'] = str(directory/'cli')
    versions = [subprocess.check_output([str(p), '--version'], text=True, env=env, timeout=10).strip() for p in (cli, server)]
    if versions[0] != versions[1]:
        raise RuntimeError(f'CLI/server version mismatch: {versions}')
    rows = write_bundle(directory/'fixtures', 20260915)
    with socket.socket() as reservation:
        reservation.bind(('127.0.0.1', 0))
        port = reservation.getsockname()[1]
    config = directory/'server.json'
    with (directory/'bootstrap.log').open('w') as log:
        process = subprocess.Popen([str(server), 'bootstrap', '--config', str(config), '--storage', 'sqlite',
            '--path', str(directory/'database.sqlite'), '--host', '127.0.0.1', '--port', str(port)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log, env=env)
        try:
            deadline = time.monotonic()+15
            def read_exact(count):
                result = bytearray()
                while len(result) < count:
                    remaining = deadline-time.monotonic()
                    if remaining <= 0 or not select.select([process.stdout], [], [], remaining)[0]:
                        raise TimeoutError('Bootstrap response timed out')
                    chunk = os.read(process.stdout.fileno(), count-len(result))
                    if not chunk: raise RuntimeError('Incomplete bootstrap response')
                    result.extend(chunk)
                return bytes(result)
            size = struct.unpack('>I', read_exact(4))[0]
            if not 0 < size <= 65536: raise RuntimeError('Invalid bootstrap frame size')
            credential = json.loads(read_exact(size))
            token = credential['token']
            process.stdin.write(b'\x01'); process.stdin.flush()
            if process.wait(timeout=15) != 0: raise RuntimeError('Bootstrap failed')
        finally:
            if process.poll() is None: process.kill(); process.wait(timeout=10)
    configuration = json.loads(config.read_text())
    configuration['entityPolicies'] = [
        {'entity': entity, 'roles': {operation: ['admin'] for operation in ('list', 'get', 'create', 'update', 'delete')}}
        for entity in COUNTS
    ]
    configuration['entityPolicies'][0]['roles'].pop('delete')
    config.write_text(json.dumps(configuration, indent=2)+'\n')
    env['DATABASE_ACCESS_TOKEN'] = token
    endpoint = credential['endpoint']
    evidence = dict(cli=str(cli), server=str(server), version=versions[0], endpoint=endpoint,
                    inserted=0, verified=False)
    def command(*arguments):
        result = subprocess.run([str(cli), *arguments, '--endpoint', endpoint, '--database', 'main'],
            capture_output=True, text=True, env=env, timeout=45)
        if result.returncode:
            raise RuntimeError(f'{arguments[0]} failed ({result.returncode}): '+result.stderr.replace(token, '[redacted]'))
        return json.loads(result.stdout)
    with (directory/'server.log').open('w') as log:
        process = subprocess.Popen([str(server), 'serve', '--config', str(config)], stdout=log, stderr=subprocess.STDOUT, env=env)
        try:
            for _ in range(100):
                if process.poll() is not None: raise RuntimeError('Server exited during startup')
                try:
                    with socket.create_connection(('127.0.0.1', port), timeout=.1): break
                except OSError: time.sleep(.05)
            evidence['capabilities'] = command('capabilities')
            plan = command('schema', 'plan', '@'+str(directory/'fixtures/schema.json'))
            evidence['schemaPlan'] = plan
            applied = command('schema', 'apply', '@'+str(directory/'fixtures/schema.json'),
                              '--expected-fingerprint', plan['currentFingerprint'], '--idempotency-key', 'maintenance-schema-v1')
            if 'id' in applied:
                evidence['schemaJob'] = command('job', 'wait', applied['id'], applied['family'], applied['kind'])
            for entity, records in rows.items():
                for row in records:
                    command('entity', 'insert', entity, json.dumps(tagged(row['id'])),
                            json.dumps({'$type': 'object', 'value': {k: tagged(v) for k, v in row.items()}}),
                            '--idempotency-key', 'maintenance-'+row['id'])
                    evidence['inserted'] += 1
            denied = subprocess.run([str(cli), 'entity', 'delete', 'Factory', json.dumps(tagged('factory-0001')),
                '--idempotency-key', 'maintenance-denied-delete', '--endpoint', endpoint, '--database', 'main'],
                capture_output=True, text=True, env=env, timeout=45)
            if denied.returncode != 4 or 'ACCESS_DENIED' not in denied.stderr:
                raise RuntimeError('Undeclared delete permission did not reject the mutation')
            evidence['undeclaredDeleteDenied'] = True
            probe = dict(rows['WorkOrder'][0], id='authorization-probe')
            def fields(row):
                return json.dumps({'$type': 'object', 'value': {key: tagged(value) for key, value in row.items()}})
            command('entity', 'insert', 'WorkOrder', json.dumps(tagged(probe['id'])), fields(probe),
                    '--idempotency-key', 'authorization-probe-insert')
            probe['name'] = 'Authorization update verified'
            command('entity', 'update', 'WorkOrder', json.dumps(tagged(probe['id'])), fields(probe),
                    '--idempotency-key', 'authorization-probe-update')
            result = command('query', 'sql', "SELECT name FROM WorkOrder WHERE id = 'authorization-probe'", '--output', 'json')
            if result != [{'name': tagged(probe['name'])}]:
                raise RuntimeError('Authorized update readback mismatch')
            command('entity', 'delete', 'WorkOrder', json.dumps(tagged(probe['id'])),
                    '--idempotency-key', 'authorization-probe-delete')
            evidence['crudVerified'] = True
            process.terminate()
            if process.wait(timeout=20) != 0:
                raise RuntimeError('Server did not shut down cleanly before restart')
            try:
                with socket.create_connection(('127.0.0.1', port), timeout=.2):
                    raise RuntimeError('Stopped server remained reachable before restart')
            except OSError:
                pass
            process = subprocess.Popen([str(server), 'serve', '--config', str(config)],
                stdout=log, stderr=subprocess.STDOUT, env=env)
            for _ in range(100):
                if process.poll() is not None:
                    raise RuntimeError('Server exited during restart')
                try:
                    with socket.create_connection(('127.0.0.1', port), timeout=.1): break
                except OSError: time.sleep(.05)
            command('capabilities')
            evidence['restarted'] = True
            evidence['readback'] = {}
            for entity in COUNTS:
                result = command('query', 'sql', f'SELECT COUNT(*) AS sample_count FROM {entity}', '--output', 'json')
                evidence['readback'][entity] = result
                if len(result) != 1 or result[0]['sample_count']['$type'] not in ('int64', 'uint64') or int(result[0]['sample_count']['value']) != COUNTS[entity]:
                    raise RuntimeError(f'Count verification failed for {entity}')
            evidence['verified'] = True
        except Exception as error:
            evidence['failure'] = str(error).replace(token, '[redacted]')
            raise
        finally:
            process.terminate()
            try: process.wait(timeout=20)
            except subprocess.TimeoutExpired: process.kill(); process.wait(timeout=10)
            evidence['serverExitCode'] = process.returncode
            try:
                with socket.create_connection(('127.0.0.1', port), timeout=.2):
                    evidence['negativeReadiness'] = False
            except OSError: evidence['negativeReadiness'] = True
            shutdown_ok = process.returncode == 0 and evidence['negativeReadiness']
            if not shutdown_ok:
                evidence['verified'] = False
                evidence.setdefault('failure', 'Server shutdown verification failed')
            (directory/'evidence.json').write_text(json.dumps(evidence, indent=2)+'\n')
            if not shutdown_ok:
                raise RuntimeError('Server shutdown verification failed')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', type=Path, required=True)
    parser.add_argument('--server', type=Path, required=True)
    parser.add_argument('--directory', type=Path, required=True)
    args = parser.parse_args()
    run(args.cli.resolve(), args.server.resolve(), args.directory.resolve())
