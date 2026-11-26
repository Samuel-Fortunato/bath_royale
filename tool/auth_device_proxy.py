"""Private loopback TLS gateway for the isolated Auth instance, never REST.

Run prepare/serve in a mode-0700 directory outside the checkout. No request,
response, password, verification token or private key is printed.
"""
import argparse
import base64
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import ssl
import subprocess


def prepare(directory):
    root = Path(__file__).resolve().parent.parent
    if directory.resolve() == root or root in directory.resolve().parents:
        raise RuntimeError('Device credentials must remain outside the checkout')
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    if directory.is_symlink() or directory.stat().st_mode & 0o077:
        raise RuntimeError('Private directory required')
    for name in ('server.key', 'server.pem', 'defines.json'):
        if (directory / name).exists():
            raise RuntimeError('Refusing to replace existing device configuration')
    subprocess.run([
        'openssl', 'req', '-x509', '-newkey', 'rsa:3072', '-noenc', '-days', '7',
        '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost',
        '-addext', 'basicConstraints=critical,CA:TRUE',
        '-keyout', str(directory / 'server.key'),
        '-out', str(directory / 'server.pem'),
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    (directory / 'defines.json').write_text(json.dumps({
        'SUPABASE_URL': 'https://localhost:55474',
        'SUPABASE_PUBLISHABLE_KEY': 'local-device-client',
        'BATH_DEVICE_CA_BASE64': base64.b64encode(
            (directory / 'server.pem').read_bytes()).decode('ascii'),
    }))


class Gateway(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def proxy(self):
        if not self.path.startswith('/auth/v1/'):
            self.send_error(404)
            return
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 <= length <= 1024 * 1024 or self.headers.get('Transfer-Encoding'):
                raise ValueError('Unsupported body')
            body = self.rfile.read(length)
            headers = {k: v for k, v in self.headers.items()
                       if k.lower() in ('content-type', 'authorization', 'apikey')}
            connection = http.client.HTTPConnection('127.0.0.1', 55471, timeout=15)
            try:
                connection.request(self.command, self.path[len('/auth/v1'):], body, headers)
                response = connection.getresponse()
                payload = response.read()
                self.send_response(response.status)
                self.send_header('Content-Type', response.getheader('Content-Type', 'application/json'))
                self.send_header('Content-Length', str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
            finally:
                connection.close()
        except (OSError, ValueError, http.client.HTTPException):
            self.send_error(502)

    do_GET = do_POST = do_PUT = do_DELETE = proxy


def serve(directory):
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(directory / 'server.pem', directory / 'server.key')
    server = ThreadingHTTPServer(('127.0.0.1', 55474), Gateway)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    print('Local TLS Auth gateway ready on 127.0.0.1:55474', flush=True)
    try:
        server.serve_forever()
    finally:
        server.server_close()


if __name__ == '__main__':
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('prepare', 'serve'))
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    if args.action == 'prepare':
        prepare(args.directory)
    else:
        serve(args.directory)
