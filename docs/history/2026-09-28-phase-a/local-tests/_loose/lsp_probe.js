// Minimal LSP client: connect to Godot LSP over TCP, open a file, print diagnostics.
const net = require('net'); const fs = require('fs'); const path = require('path');
const [port, root, file] = process.argv.slice(2);
const toUri = p => 'file:///' + path.resolve(p).split(path.sep).join('/');
const sock = net.connect(+port, '127.0.0.1');
let buf = Buffer.alloc(0), id = 0;
const send = (m) => { const s = JSON.stringify(Object.assign({jsonrpc: '2.0'}, m)); sock.write(`Content-Length: ${Buffer.byteLength(s)}\r\n\r\n${s}`); };
sock.on('data', d => {
  buf = Buffer.concat([buf, d]);
  for (;;) {
    const h = buf.indexOf('\r\n\r\n'); if (h < 0) return;
    const len = +/Content-Length: (\d+)/i.exec(buf.slice(0, h).toString())[1];
    if (buf.length < h + 4 + len) return;
    const msg = JSON.parse(buf.slice(h + 4, h + 4 + len).toString()); buf = buf.slice(h + 4 + len);
    if (msg.id === 1 && msg.result) {
      send({method: 'initialized', params: {}});
      send({method: 'textDocument/didOpen', params: {textDocument: {uri: toUri(file), languageId: 'gdscript', version: 1, text: fs.readFileSync(file, 'utf8')}}});
    } else if (msg.method === 'textDocument/publishDiagnostics') {
      console.log('DIAG', msg.params.uri.split('/').pop(), JSON.stringify(msg.params.diagnostics.map(d => [d.severity, d.range.start.line + 1, d.message])));
    }
  }
});
sock.on('connect', () => send({id: 1, method: 'initialize', params: {processId: process.pid, rootUri: toUri(root), capabilities: {}}}));
sock.on('error', e => { console.log('ERR', e.message); process.exit(2); });
setTimeout(() => process.exit(0), 6000);
