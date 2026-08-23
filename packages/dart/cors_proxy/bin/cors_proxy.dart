import 'dart:io';

import 'package:cors_proxy/server.dart';

/// ```
/// dart run cors_proxy --root apps/tv/build/web --port 8080
/// ```
Future<void> main(List<String> args) async {
  var port = 8080;
  Directory? root;
  var public = false;
  var quiet = false;
  var referer = _kinostrain;
  var agent = _bravia;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--port' || '-p':
        port = int.tryParse(args[++i]) ?? port;
      case '--root' || '-r':
        root = Directory(args[++i]);
      case '--public':
        public = true;
      case '--quiet' || '-q':
        quiet = true;
      case '--referer':
        referer = args[++i];
      case '--agent':
        agent = args[++i];
      case '--help' || '-h':
        stdout.writeln(_usage);
        return;
    }
  }

  if (root != null && !root.existsSync()) {
    stderr.writeln('no such directory: ${root.path}');
    exitCode = 2;
    return;
  }

  final proxy = CorsProxy(
    port: port,
    root: root,
    address: public ? InternetAddress.anyIPv4 : null,
    onLog: quiet ? null : (line) => stdout.writeln('  $line'),
    defaultReferer: referer,
    defaultAgent: agent,
  );

  await proxy.start();
  stdout.writeln('proxy on ${proxy.url}');
  if (root != null) stdout.writeln('serving ${root.absolute.path}');
  if (public) {
    stdout.writeln(
      'bound to every interface — this forwards to any host it is given, '
      'so do not leave it on a network you do not trust',
    );
  }

  await ProcessSignal.sigint.watch().first;
  await proxy.stop();
}

/// The site every host in this stack is expecting to hear from.
const _kinostrain = 'https://kinostrain.com/';

/// What the box asks with, so a CDN sees the same client it would on one.
const _bravia =
    'Mozilla/5.0 (Linux; Android 12; BRAVIA) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0 Safari/537.36';

const _usage = '''
Forwards what a browser will not, and serves the web build beside it.

  --root, -r <dir>   the built web app to serve at /
  --port, -p <n>     default 8080
  --public           bind every interface instead of loopback
  --quiet, -q        do not log requests
  --referer <url>    sent when a request does not name one
  --agent <string>   likewise for User-Agent
''';
