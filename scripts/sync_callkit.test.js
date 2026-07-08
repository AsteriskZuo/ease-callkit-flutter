const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync, spawnSync } = require('node:child_process');
const test = require('node:test');

const scriptPath = path.join(__dirname, 'sync_callkit.js');

function run(command, args, cwd) {
  return execFileSync(command, args, { cwd, encoding: 'utf8' });
}

function writeFile(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content);
}

function makeRepo(root, files) {
  fs.mkdirSync(root, { recursive: true });
  run('git', ['init'], root);
  run('git', ['config', 'user.email', 'test@example.com'], root);
  run('git', ['config', 'user.name', 'Test User'], root);

  for (const [relativePath, content] of Object.entries(files)) {
    writeFile(path.join(root, relativePath), content);
  }

  run('git', ['add', '.'], root);
  run('git', ['commit', '-m', 'initial'], root);
}

function runScript(sourceRepo, targetRepo, version) {
  return spawnSync(
    process.execPath,
    [scriptPath, sourceRepo, targetRepo, version],
    { encoding: 'utf8' },
  );
}

test('stops when source repo has uncommitted or untracked files', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'sync-callkit-dirty-source-'));
  const source = path.join(tmp, 'source');
  const target = path.join(tmp, 'target');

  makeRepo(source, {
    'pubspec.yaml': 'name: em_chat_callkit\nversion: 0.0.1\nhomepage: https://www.easemob.com\n',
  });
  makeRepo(target, {
    'pubspec.yaml': 'name: agora_chat_callkit\nversion: 1.0.0\nhomepage: https://www.agora.io\n',
  });

  writeFile(path.join(source, 'untracked.txt'), 'dirty');

  const result = runScript(source, target, '2.0.0');

  assert.equal(result.status, 1);
  assert.match(result.stderr + result.stdout, /source repo is not clean/i);
});

test('stops when target repo has tracked changes', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'sync-callkit-dirty-target-'));
  const source = path.join(tmp, 'source');
  const target = path.join(tmp, 'target');

  makeRepo(source, {
    'pubspec.yaml': 'name: em_chat_callkit\nversion: 0.0.1\nhomepage: https://www.easemob.com\n',
  });
  makeRepo(target, {
    'pubspec.yaml': 'name: agora_chat_callkit\nversion: 1.0.0\nhomepage: https://www.agora.io\n',
  });

  writeFile(
    path.join(target, 'pubspec.yaml'),
    'name: agora_chat_callkit\nversion: 1.0.1\nhomepage: https://www.agora.io\n',
  );

  const result = runScript(source, target, '2.0.0');

  assert.equal(result.status, 1);
  assert.match(result.stderr + result.stdout, /target repo has tracked changes/i);
});

test('mirrors source into target then applies agora callkit replacements', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'sync-callkit-mirror-'));
  const source = path.join(tmp, 'source');
  const target = path.join(tmp, 'target');

  makeRepo(source, {
    'pubspec.yaml': [
      'name: em_chat_callkit',
      'description: source',
      'version: 0.0.1',
      'homepage: https://www.easemob.com',
      'dependencies:',
      '  im_flutter_sdk: ^4.15.2',
      'flutter:',
      '  plugin:',
      '    platforms:',
      '      android:',
      '        package: com.example.em_chat_callkit',
      '        pluginClass: EmChatCallkitPlugin',
      '      ios:',
      '        pluginClass: EmChatCallkitPlugin',
      '',
    ].join('\n'),
    'LICENSE': 'Copyright 2026 Easemob\nhttps://www.easemob.com\n',
    'CHANGELOG.md': '# Changelog\n',
    'README.md': 'README mentions em_chat_callkit and must stay copied.\n',
    'lib/inherited/tools/call_define.dart': [
      "import 'package:im_flutter_sdk/im_flutter_sdk.dart' as chat;",
      '',
      'typedef ChatCallKitClient = chat.EMClient;',
      'typedef ChatCallKitChatManager = chat.EMChatManager;',
      'typedef ChatCallKitEventHandler = chat.EMChatEventHandler;',
      'typedef ChatCallKitMessage = chat.EMMessage;',
      'typedef ChatCallKitMessageEvent = chat.ChatMessageEvent;',
      'typedef ChatCallKitChatError = chat.EMError;',
      'typedef ChatOptions = chat.EMOptions;',
      '',
    ].join('\n'),
    'ios/em_chat_callkit.podspec': 's.name = "em_chat_callkit"\n',
    'ios/Classes/EmChatCallkitPlugin.h': '@interface EmChatCallkitPlugin\n',
    'lib/em_chat_callkit.dart': 'class EmChatCallkitPlugin {}\nfinal name = "emChatCallkit";\n',
  });

  makeRepo(target, {
    'pubspec.yaml': 'name: agora_chat_callkit\nversion: 1.0.0\nhomepage: https://www.agora.io\n',
    'target_only.dart': 'must be deleted\n',
  });

  writeFile(path.join(target, 'ignored.tmp'), 'removed by git clean');

  const result = runScript(source, target, '2.3.4');

  assert.equal(result.status, 0, result.stderr + result.stdout);
  assert.equal(fs.existsSync(path.join(target, '.git')), true);
  assert.equal(fs.existsSync(path.join(target, 'target_only.dart')), false);
  assert.equal(fs.existsSync(path.join(target, 'ignored.tmp')), false);
  assert.equal(fs.existsSync(path.join(target, 'CHANGELOG.md')), false);
  assert.equal(fs.existsSync(path.join(target, 'ios/agora_chat_callkit.podspec')), true);
  assert.equal(fs.existsSync(path.join(target, 'ios/Classes/AgoraChatCallkitPlugin.h')), true);

  const pubspec = fs.readFileSync(path.join(target, 'pubspec.yaml'), 'utf8');
  assert.match(pubspec, /^name: agora_chat_callkit$/m);
  assert.match(pubspec, /^version: 2\.3\.4$/m);
  assert.match(pubspec, /^homepage: https:\/\/www\.agora\.io$/m);
  assert.match(pubspec, /agora_chat_sdk: \^4\.15\.2/);
  assert.doesNotMatch(pubspec, /im_flutter_sdk|em_chat_callkit|EmChatCallkitPlugin/);

  const license = fs.readFileSync(path.join(target, 'LICENSE'), 'utf8');
  assert.match(license, /www\.agora\.io/);
  assert.doesNotMatch(license, /easemob/i);

  const readme = fs.readFileSync(path.join(target, 'README.md'), 'utf8');
  assert.equal(readme, 'README mentions em_chat_callkit and must stay copied.\n');

  const callDefine = fs.readFileSync(
    path.join(target, 'lib/inherited/tools/call_define.dart'),
    'utf8',
  );
  assert.equal(callDefine, [
    "import 'package:agora_chat_sdk/agora_chat_sdk.dart' as chat;",
    '',
    'typedef ChatCallKitClient = chat.ChatClient;',
    'typedef ChatCallKitChatManager = chat.ChatManager;',
    'typedef ChatCallKitEventHandler = chat.ChatEventHandler;',
    'typedef ChatCallKitMessage = chat.ChatMessage;',
    'typedef ChatCallKitMessageEvent = chat.ChatMessageEvent;',
    'typedef ChatCallKitChatError = chat.ChatError;',
    'typedef ChatOptions = chat.ChatOptions;',
    '',
  ].join('\n'));
});
