#!/usr/bin/env python3
"""Own an isolated native server and Xcode runtime integration test lifecycle."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import signal
import select
import socket
import struct
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument('--server', required=True, type=Path)
parser.add_argument('--derived-data', required=True, type=Path)
parser.add_argument('--results', required=True, type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
args.results.mkdir(parents=True, exist_ok=False)
env = {k: v for k, v in os.environ.items() if not any(word in k.upper() for word in ('TOKEN', 'PASSWORD', 'SECRET', 'API_KEY'))}
env['TOOLCHAINS'] = 'com.apple.dt.toolchain.XcodeDefault'
compiler = subprocess.check_output(['xcrun', '--toolchain', 'org.swift.64202609041a', '--find', 'swiftc'], env=env, text=True).strip()
compiler_path = Path(compiler).resolve()
if not compiler_path.is_file() or 'swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-09-04-a.xctoolchain' not in compiler_path.parts:
    raise RuntimeError('The required September 4 Swift snapshot is unavailable; refusing an implicit toolchain fallback')
(args.results / 'compiler-version.log').write_text(subprocess.check_output([compiler, '--version'], env=env, text=True))
base = ['xcodebuild', '-project', str(root / 'Database Studio/Database Studio.xcodeproj'),
        '-scheme', 'Database Studio', '-destination', 'platform=macOS,arch=arm64',
        '-derivedDataPath', str(args.derived_data), 'SWIFT_EXEC=' + compiler,
        'CODE_SIGN_IDENTITY=-', 'CODE_SIGN_STYLE=Manual', 'DEVELOPMENT_TEAM=']


def run(command, name, timeout):
    with (args.results / (name + '.log')).open('w') as log:
        subprocess.run(command, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT,
                       timeout=timeout, check=True)


run(base + ['build-for-testing', '-resultBundlePath', str(args.results / 'Build.xcresult')], 'build', 900)
with tempfile.TemporaryDirectory(prefix='studio-runtime-test-') as directory:
    work = Path(directory)
    os.chmod(work, 0o700)
    with socket.socket() as allocated:
        allocated.bind(('127.0.0.1', 0))
        port = allocated.getsockname()[1]
    config = work / 'server.json'
    with (args.results / 'bootstrap.log').open('w') as log:
        process = subprocess.Popen([str(args.server), 'bootstrap', '--config', str(config),
                                    '--storage', 'sqlite', '--path', str(work / 'database.sqlite'),
                                    '--host', '127.0.0.1', '--port', str(port)],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log, env=env)
        try:
            # The outer harness timeout also bounds bootstrap pipe reads.
            deadline = time.monotonic() + 15
            def read_exact(count):
                chunks = bytearray()
                while len(chunks) < count:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0 or not select.select([process.stdout], [], [], remaining)[0]:
                        raise TimeoutError('Bootstrap frame timed out')
                    chunk = os.read(process.stdout.fileno(), count - len(chunks))
                    if not chunk:
                        raise RuntimeError('Bootstrap pipe closed before frame completion')
                    chunks.extend(chunk)
                return bytes(chunks)
            header = read_exact(4)
            assert len(header) == 4, 'Missing bootstrap frame'
            length = struct.unpack('>I', header)[0]
            assert 0 < length <= 65536, 'Invalid bootstrap size'
            payload = read_exact(length)
            response = json.loads(payload)
            assert response['createdCredential'] and response['token']
            credential = work / 'credential.json'
            credential.write_bytes(payload)
            os.chmod(credential, 0o600)
            process.stdin.write(b'\x01')
            process.stdin.flush()
            assert process.wait(timeout=15) == 0, 'Bootstrap failed'
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
    with (args.results / 'server.log').open('w') as log:
        server = subprocess.Popen([str(args.server), 'serve', '--config', str(config)],
                                  stdout=log, stderr=subprocess.STDOUT, env=env)
        try:
            for attempt in range(100):
                assert server.poll() is None, 'Server exited before test startup'
                try:
                    with socket.create_connection(('127.0.0.1', port), timeout=0.1):
                        break
                except OSError:
                    time.sleep(0.05)
            else:
                raise RuntimeError('Listener did not start')
            # Socket reachability is not protocol readiness: the first XCTest
            # requires a real authenticated capabilities + schema handshake.
            files = list((args.derived_data / 'Build/Products').glob('*.xctestrun'))
            assert files, 'Missing test configuration'
            original = max(files, key=lambda path: path.stat().st_mtime)
            settings = plistlib.loads(original.read_bytes())
            for configuration in settings['TestConfigurations']:
                for target in configuration['TestTargets']:
                    for key in ('EnvironmentVariables', 'TestingEnvironmentVariables'):
                        target.setdefault(key, {})['STUDIO_RUNTIME_TEST_CREDENTIAL'] = str(credential)
                    target.setdefault('CommandLineArguments', []).extend(['-ConnectionHistory', '', '-RuntimeConnectionHistory', ''])
            generated = original.with_name('StudioRuntimeIntegration.xctestrun')
            generated.write_bytes(plistlib.dumps(settings))
            executable = str(args.derived_data / 'Build/Products/Debug/Database Studio.app/Contents/MacOS/Database Studio')
            def test_host_pids():
                output = subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True)
                return {int(parts[0]) for line in output.splitlines()
                        if len(parts := line.strip().split(maxsplit=1)) == 2 and parts[1] == executable}
            existing_hosts = test_host_pids()
            try:
                run(['xcodebuild', 'test-without-building', '-xctestrun', str(generated),
                     '-destination', 'platform=macOS,arch=arm64', '-parallel-testing-enabled', 'NO',
                     '-only-testing:Database StudioTests/RuntimeServerTests',
                     '-only-testing:Database StudioTests/RuntimeConnectionTests',
                     '-only-testing:Database StudioTests/RuntimeConnectionPersistenceTests',
                     '-resultBundlePath', str(args.results / 'Tests.xcresult')], 'tests', 60)
            finally:
                generated.unlink(missing_ok=True)
                for pid in test_host_pids() - existing_hosts:
                    try:
                        os.kill(pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
            summary = subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                                               '--path', str(args.results / 'Tests.xcresult')], env=env)
            (args.results / 'summary.json').write_bytes(summary)
            result = json.loads(summary)
            assert result['passedTests'] == 8 and result['totalTestCount'] == 8
            assert all(result[key] == 0 for key in ('failedTests', 'skippedTests', 'expectedFailures'))
            assert not result['runtimeWarnings']
        finally:
            if server.poll() is None:
                server.send_signal(signal.SIGTERM)
                try:
                    server.wait(timeout=20)
                except subprocess.TimeoutExpired:
                    server.kill()
                    server.wait()
                    raise RuntimeError('Server failed authoritative shutdown')
            try:
                with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                    raise RuntimeError('Server endpoint remains reachable after shutdown')
            except OSError:
                pass
            (args.results / 'teardown.json').write_text(json.dumps({'serverExitCode': server.returncode, 'negativeReadiness': True}))
print('Real server runtime tests and negative readiness passed.')
