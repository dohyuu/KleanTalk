#!/usr/bin/env python3
"""실제 TLS 서버가 다른 주소의 동일 포트 리스너와 공존하는지 검사한다.

사용: python3 tests/adserver_launchd_test.py [서버 실행 파일]
macOS 13+ 사용자 로그인 세션에서 실행. 임시 사용자 서비스만 만들고 정리한다.
"""
import json
import os
from pathlib import Path
import plistlib
import socket
import subprocess
import sys
import tempfile
import time
import uuid


def checked(*args):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def main():
    binary = Path(sys.argv[1] if len(sys.argv) > 1 else
                  'build/NoAdsTalk.app/Contents/Resources/kleantalk-adserver').resolve()
    if not binary.is_file():
        raise SystemExit('먼저 ./build.sh를 실행하세요.')
    with tempfile.TemporaryDirectory(prefix='noadstalk-tls-', dir='/private/tmp') as directory:
        root = Path(directory)
        (root / 'req.cnf').write_text(
            '[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n'
            '[dn]\nCN=serv.ds.kakao.com\n[ext]\nsubjectAltName=DNS:serv.ds.kakao.com\n'
            'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\n'
            'extendedKeyUsage=serverAuth\n')
        checked('/usr/bin/openssl', 'req', '-new', '-x509', '-newkey', 'rsa:2048', '-nodes',
                '-days', '1', '-config', str(root / 'req.cnf'), '-keyout', str(root / 'key.pem'),
                '-out', str(root / 'cert.pem'))
        checked('/usr/bin/openssl', 'rsa', '-in', str(root / 'key.pem'), '-outform', 'DER',
                '-out', str(root / 'key.der'))
        checked('/usr/bin/openssl', 'x509', '-in', str(root / 'cert.pem'), '-outform', 'DER',
                '-out', str(root / 'cert.der'))
        # IPv6 루프백에 점유한 포트와 같은 포트를 IPv4 TLS 서버에 준다.
        with socket.socket(socket.AF_INET6) as occupied:
            occupied.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
            occupied.bind(('::1', 0))
            occupied.listen(1)
            port = occupied.getsockname()[1]
            label = 'local.noadstalk.test.' + uuid.uuid4().hex
            domain = f'gui/{os.getuid()}'
            config = {
                'Label': label,
                'ProgramArguments': [str(binary), str(root / 'cert.der'), str(root / 'key.der')],
                'RunAtLoad': True,
                'EnvironmentVariables': {
                    'KLEANTALK_LAUNCHD_SOCKET': 'HTTPS',
                    'KLEANTALK_ADSERVER_HOST': '127.0.0.1',
                    'KLEANTALK_ADSERVER_PORT': str(port),
                },
                'Sockets': {'HTTPS': {'SockFamily': 'IPv4', 'SockType': 'stream',
                                     'SockNodeName': '127.0.0.1', 'SockServiceName': str(port)}},
                'StandardOutPath': str(root / 'stdout'),
                'StandardErrorPath': str(root / 'stderr'),
            }
            job = root / 'job.plist'
            job.write_bytes(plistlib.dumps(config))
            bootstrapped = False
            try:
                checked('launchctl', 'bootstrap', domain, str(job))
                bootstrapped = True
                result = None
                for _ in range(5):
                    result = subprocess.run([
                        '/usr/bin/curl', '--silent', '--show-error', '--noproxy', '*',
                        '--max-time', '1', '--cacert', str(root / 'cert.pem'),
                        '--resolve', f'serv.ds.kakao.com:{port}:127.0.0.1',
                        '-D', str(root / 'headers'),
                        f'https://serv.ds.kakao.com:{port}/sdk/banner?kleantalk=check',
                    ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    if result.returncode == 0:
                        break
                    time.sleep(0.1)
                assert result.returncode == 0, 'TLS server failed beside occupied port: ' + result.stderr.decode()
                payload = json.loads(result.stdout)
                assert payload['status'] == 'OK'
                assert payload['ads'][0]['mimeType'] == 'text/html'
                assert 'AdLoaded' in payload['ads'][0]['content']
                assert 'X-KleanTalk: 1' in (root / 'headers').read_text()
                print('PASS: launchd socket + concurrent IPv6 listener + verified TLS + blank ad')
            finally:
                if bootstrapped:
                    checked('launchctl', 'bootout', domain + '/' + label)


if __name__ == '__main__':
    main()
