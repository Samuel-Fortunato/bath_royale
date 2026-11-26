"""Loopback-only copy helper for fictional confirmation/recovery mail.

Reads only the isolated Mailpit API. Never opens verification links, sends mail,
persists tokens or prints requests. Use adb reverse tcp:55475 tcp:55475.
"""
import html
import json
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlencode, urlsplit
from urllib.request import urlopen

PAGE = r'''<!doctype html><html lang="pt-PT"><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Correio do trono — teste local</title>
<style>
body{font:16px system-ui;max-width:640px;margin:auto;padding:24px;background:#faf7f0;color:#29251f}
h1{font-size:1.6rem}label{display:block}input,button{font:inherit;box-sizing:border-box;padding:12px;margin:6px 0;width:100%;border:1px solid #8b8175;border-radius:10px}
button{background:#65533d;color:white;cursor:pointer}article{background:white;padding:16px;margin:16px 0;border-radius:16px;border:1px solid #ddd5c9}small{display:block}#status{min-height:1.5em}
</style>
<h1>Correio do trono</h1><p>Teste local de confirmação e recuperação. As mensagens ficam no computador.</p>
<form id="form"><label for="email">Email fictício</label>
<input id="email" type="email" value="device-trono@example.com" required autocapitalize="none">
<button>Atualizar mensagens</button></form><p id="status" role="status"></p><main id="messages"></main>
<p>Depois de criar a conta ou pedir recuperação, atualiza as mensagens. Copia a ligação mais recente e cola-a no campo «Código ou ligação do email» da app. Não abras a ligação: pode consumir o código.</p>
<p><a href="http://localhost:55473" rel="noreferrer">Abrir Mailpit completo</a></p>
<script>
const form=document.querySelector('#form'),status=document.querySelector('#status'),messages=document.querySelector('#messages');
form.addEventListener('submit',async event=>{
 event.preventDefault();status.textContent='A consultar o correio local…';messages.replaceChildren();
 try{
  const response=await fetch('/messages?email='+encodeURIComponent(document.querySelector('#email').value.trim()),{cache:'no-store'});
  if(!response.ok)throw Error();const items=await response.json();
  status.textContent=items.length?'Escolhe a mensagem mais recente.':'Ainda não há mensagens para este email. Atualiza após o envio.';
  for(const item of items){
   const article=document.createElement('article'),title=document.createElement('h2'),when=document.createElement('small'),field=document.createElement('input'),button=document.createElement('button');
   title.textContent=item.recovery?'Recuperar palavra-passe':'Confirmar email';when.textContent=item.created;
   field.value=item.link;field.readOnly=true;field.setAttribute('aria-label','Ligação pronta para colar na app');
   button.textContent='Copiar ligação para a app';button.type='button';
   button.onclick=async()=>{try{await navigator.clipboard.writeText(item.link);status.textContent='Ligação copiada. Volta à app e cola-a.';}catch(_){field.focus();field.select();status.textContent='Seleciona «Copiar» no campo e volta à app.';}};
   article.append(title,when,field,button);messages.append(article);
  }
 }catch(_){status.textContent='Correio local indisponível. Verifica se o ambiente de teste está ligado.';}
});
</script></html>'''


def mapped_links(text):
    """Map only the exact isolated direct Auth origin/path, preserving tokens."""
    links = []
    for candidate in re.findall(r'http://127\.0\.0\.1:55471/verify\?[^\s"<>]+', html.unescape(text)):
        parsed = urlsplit(candidate)
        query = parse_qs(parsed.query)
        if (parsed.scheme != 'http' or parsed.netloc != '127.0.0.1:55471'
                or parsed.path != '/verify' or not query.get('token')
                or query.get('type', [''])[0] not in ('signup', 'recovery')):
            continue
        link = 'https://localhost:55474/auth/v1/verify?' + parsed.query
        if link not in [item['link'] for item in links]:
            links.append({'link': link, 'recovery': query['type'][0] == 'recovery'})
    return links


def mail(path):
    with urlopen('http://127.0.0.1:55473/api/v1/' + path, timeout=5) as response:
        return json.load(response)


def messages_for(email):
    if not email or len(email) > 254 or '@' not in email:
        return []
    listing = mail('messages?' + urlencode({'limit': 100}))
    result = []
    for item in listing.get('messages', []):
        if not any(recipient.get('Address', '').casefold() == email.casefold()
                   for recipient in item.get('To', [])):
            continue
        # IDs come from the local service, but still cannot select another API path.
        identifier = item.get('ID', '')
        if not re.fullmatch(r'[A-Za-z0-9-]+', identifier):
            continue
        message = mail('message/' + identifier)
        for link in mapped_links(str(message.get('Text', '')) + ' ' + str(message.get('HTML', ''))):
            result.append({**link, 'created': item.get('Created', '')})
        if len(result) >= 5:
            break
    return sorted(result, key=lambda item: item['created'], reverse=True)[:5]


class Inbox(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def reply(self, status, content, kind):
        self.send_response(status)
        self.send_header('Content-Type', kind + '; charset=utf-8')
        self.send_header('Content-Length', str(len(content)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Referrer-Policy', 'no-referrer')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Content-Security-Policy',
                         "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; "
                         "connect-src 'self'; base-uri 'none'; frame-ancestors 'none'")
        self.end_headers()
        self.wfile.write(content)

    def do_GET(self):
        if self.headers.get('Host') not in ('localhost:55475', '127.0.0.1:55475'):
            self.reply(403, b'Forbidden', 'text/plain')
            return
        path = urlsplit(self.path)
        if path.path == '/':
            self.reply(200, PAGE.encode(), 'text/html')
        elif path.path == '/messages':
            try:
                email = parse_qs(path.query).get('email', [''])[0]
                body = json.dumps(messages_for(email)).encode()
                self.reply(200, body, 'application/json')
            except (OSError, ValueError, KeyError):
                self.reply(502, b'Local mail unavailable', 'text/plain')
        else:
            self.reply(404, b'Not found', 'text/plain')


if __name__ == '__main__':
    server = ThreadingHTTPServer(('127.0.0.1', 55475), Inbox)
    print('Private mail copy helper ready on 127.0.0.1:55475', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
