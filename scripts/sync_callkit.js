#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const TEXT_EXTENSIONS = new Set([
  '.dart',
  '.yaml',
  '.yml',
  '.java',
  '.kt',
  '.h',
  '.m',
  '.swift',
  '.gradle',
  '.xml',
  '.podspec',
  '.md',
  '.plist',
  '.pbxproj',
  '.xcconfig',
  '.json',
  '.txt',
  '.properties',
  '.kts',
]);

const SKIP_CONTENT_FILES = new Set([
  'README.md',
  'pubspec.lock',
  'Podfile.lock',
  'Manifest.lock',
  'GeneratedPluginRegistrant.m',
  'GeneratedPluginRegistrant.swift',
  '.flutter-plugins',
  '.flutter-plugins-dependencies',
]);

const REPLACEMENTS = [
  ['EmChatCallkitPlugin', 'AgoraChatCallkitPlugin'],
  ['EmChatCallkit', 'AgoraChatCallkit'],
  ['emChatCallkit', 'agoraChatCallkit'],
  ['em_chat_callkit', 'agora_chat_callkit'],
  ['im_flutter_sdk', 'agora_chat_sdk'],
];

const CALL_DEFINE_CONTENT = [
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
].join('\n');

function usage() {
  return [
    'Usage:',
    '  node scripts/sync_callkit.js <source_repo> <target_repo> <target_version> <chat_sdk_version>',
    '',
    'Example:',
    '  node scripts/sync_callkit.js ../ease-callkit-flutter ../AgoraChat-Callkit-flutter 1.2.3 ^1.2.0',
  ].join('\n');
}

function fail(message) {
  console.error(message);
  process.exit(1);
}

function runGit(repo, args) {
  const result = spawnSync('git', args, {
    cwd: repo,
    encoding: 'utf8',
  });

  if (result.status !== 0) {
    fail(`Error: git ${args.join(' ')} failed in ${repo}\n${result.stderr || result.stdout}`);
  }

  return result.stdout;
}

function ensureRepo(label, repo) {
  if (!fs.existsSync(repo) || !fs.statSync(repo).isDirectory()) {
    fail(`Error: ${label} repo does not exist: ${repo}`);
  }
  if (!fs.existsSync(path.join(repo, '.git'))) {
    fail(`Error: ${label} repo is not a git repository: ${repo}`);
  }
  if (!fs.existsSync(path.join(repo, 'pubspec.yaml'))) {
    fail(`Error: ${label} repo is missing pubspec.yaml: ${repo}`);
  }
}

function ensureClean(label, repo) {
  const status = runGit(repo, ['status', '--porcelain']);
  if (status.trim().length > 0) {
    console.error(`Warning: ${label} repo is not clean: ${repo}`);
    console.error(status.trimEnd());
    process.exit(1);
  }
}

function ensureNoTrackedChanges(label, repo) {
  const status = runGit(repo, ['status', '--porcelain']);
  const trackedChanges = status
    .split('\n')
    .filter((line) => line.trim().length > 0 && !line.startsWith('??'));

  if (trackedChanges.length > 0) {
    console.error(`Warning: ${label} repo has tracked changes: ${repo}`);
    console.error(trackedChanges.join('\n'));
    process.exit(1);
  }
}

function validateVersion(label, version) {
  if (!version || /\s/.test(version)) {
    fail(`Error: ${label} must be a non-empty value without whitespace.`);
  }
}

function normalizeDependencyVersion(version) {
  if (/^[\^~><=]/.test(version)) {
    return version;
  }
  return `^${version}`;
}

function removeTargetContents(targetRepo) {
  for (const entry of fs.readdirSync(targetRepo)) {
    if (entry === '.git') {
      continue;
    }
    fs.rmSync(path.join(targetRepo, entry), { recursive: true, force: true });
  }
}

function copySourceToTarget(sourceRepo, targetRepo) {
  for (const entry of fs.readdirSync(sourceRepo)) {
    if (entry === '.git') {
      continue;
    }
    fs.cpSync(path.join(sourceRepo, entry), path.join(targetRepo, entry), {
      recursive: true,
      preserveTimestamps: true,
      force: true,
      errorOnExist: false,
    });
  }
}

function walk(root) {
  const results = [];

  function visit(current) {
    const stat = fs.lstatSync(current);
    results.push({ filePath: current, stat });

    if (!stat.isDirectory()) {
      return;
    }

    for (const entry of fs.readdirSync(current)) {
      if (entry === '.git') {
        continue;
      }
      visit(path.join(current, entry));
    }
  }

  visit(root);
  return results;
}

function isTextFile(filePath) {
  if (SKIP_CONTENT_FILES.has(path.basename(filePath))) {
    return false;
  }
  return TEXT_EXTENSIONS.has(path.extname(filePath).toLowerCase());
}

function replaceAll(text) {
  let next = text;
  for (const [from, to] of REPLACEMENTS) {
    next = next.split(from).join(to);
  }
  return next;
}

function replaceTextFiles(targetRepo) {
  let changed = 0;

  for (const { filePath, stat } of walk(targetRepo)) {
    if (!stat.isFile() || !isTextFile(filePath)) {
      continue;
    }

    const original = fs.readFileSync(filePath, 'utf8');
    const replaced = replaceAll(original);
    if (replaced !== original) {
      fs.writeFileSync(filePath, replaced);
      changed += 1;
    }
  }

  return changed;
}

function replacePathName(name) {
  return replaceAll(name);
}

function renamePaths(targetRepo) {
  const entries = walk(targetRepo)
    .filter(({ filePath }) => filePath !== targetRepo)
    .sort((a, b) => b.filePath.length - a.filePath.length);
  let renamed = 0;

  for (const { filePath } of entries) {
    if (!fs.existsSync(filePath)) {
      continue;
    }

    const dirname = path.dirname(filePath);
    const basename = path.basename(filePath);
    const nextBasename = replacePathName(basename);
    if (nextBasename === basename) {
      continue;
    }

    const nextPath = path.join(dirname, nextBasename);
    if (fs.existsSync(nextPath)) {
      fail(`Error: cannot rename ${filePath} to ${nextPath}; destination already exists.`);
    }
    fs.renameSync(filePath, nextPath);
    renamed += 1;
  }

  return renamed;
}

function updatePubspec(targetRepo, version, chatSdkVersion) {
  const pubspecPath = path.join(targetRepo, 'pubspec.yaml');
  const original = fs.readFileSync(pubspecPath, 'utf8');
  let next = replaceAll(original);

  next = next.replace(/^version:\s*.*$/m, `version: ${version}`);
  next = next.replace(/^homepage:\s*.*$/m, 'homepage: https://www.agora.io');
  next = next.replace(
    /^(\s*)agora_chat_sdk:\s*.*$/m,
    `$1agora_chat_sdk: ${normalizeDependencyVersion(chatSdkVersion)}`,
  );

  if (!/^version:\s*/m.test(next)) {
    fail('Error: pubspec.yaml does not contain a version field.');
  }
  if (!/^homepage:\s*/m.test(next)) {
    next = `${next.replace(/\s*$/, '\n')}homepage: https://www.agora.io\n`;
  }
  if (!/^\s*agora_chat_sdk:\s*/m.test(next)) {
    fail('Error: pubspec.yaml does not contain an agora_chat_sdk dependency.');
  }

  fs.writeFileSync(pubspecPath, next);
}

function updateLicense(targetRepo) {
  const licensePath = path.join(targetRepo, 'LICENSE');
  if (!fs.existsSync(licensePath)) {
    return false;
  }

  const original = fs.readFileSync(licensePath, 'utf8');
  let next = original
    .replace(/https?:\/\/(?:www\.)?easemob\.com(?:\/[^\s]*)?/gi, 'https://www.agora.io')
    .replace(/\b(?:Easemob|Hyphenate)(?:,\s*Inc\.)?\b/g, 'Agora, Inc.')
    .replace(/\b(?:easemob|hyphenate)(?:,\s*inc\.)?\b/g, 'Agora, Inc.');

  if (next === original && !/www\.agora\.io/i.test(next)) {
    next = original.replace(/\s*$/, '\n') + 'https://www.agora.io\n';
  }

  if (next !== original) {
    fs.writeFileSync(licensePath, next);
    return true;
  }
  return false;
}

function writeCallDefine(targetRepo) {
  const callDefinePath = path.join(targetRepo, 'lib', 'inherited', 'tools', 'call_define.dart');
  fs.mkdirSync(path.dirname(callDefinePath), { recursive: true });
  fs.writeFileSync(callDefinePath, CALL_DEFINE_CONTENT);
}

function deleteChangelog(targetRepo) {
  const changelogPath = path.join(targetRepo, 'CHANGELOG.md');
  if (fs.existsSync(changelogPath)) {
    fs.rmSync(changelogPath, { force: true });
    return true;
  }
  return false;
}

function main() {
  const [, , sourceArg, targetArg, version, chatSdkVersion] = process.argv;
  if (!sourceArg || !targetArg || !version || !chatSdkVersion) {
    fail(usage());
  }

  const sourceRepo = path.resolve(sourceArg);
  const targetRepo = path.resolve(targetArg);

  validateVersion('target_version', version);
  validateVersion('chat_sdk_version', chatSdkVersion);
  ensureRepo('source', sourceRepo);
  ensureRepo('target', targetRepo);
  ensureClean('source', sourceRepo);
  ensureNoTrackedChanges('target', targetRepo);

  console.log('Source repository is clean and target has no tracked changes.');
  runGit(targetRepo, ['clean', '-fdx']);
  console.log('Target untracked and ignored files cleaned.');

  removeTargetContents(targetRepo);
  copySourceToTarget(sourceRepo, targetRepo);
  console.log('Source repository copied to target.');

  const textFilesChanged = replaceTextFiles(targetRepo);
  const pathsRenamed = renamePaths(targetRepo);
  updatePubspec(targetRepo, version, chatSdkVersion);
  const licenseChanged = updateLicense(targetRepo);
  writeCallDefine(targetRepo);
  const changelogDeleted = deleteChangelog(targetRepo);

  console.log('Sync complete.');
  console.log(`Text files changed: ${textFilesChanged}`);
  console.log(`Paths renamed: ${pathsRenamed}`);
  console.log(`LICENSE updated: ${licenseChanged ? 'yes' : 'no changes needed'}`);
  console.log(`CHANGELOG.md deleted: ${changelogDeleted ? 'yes' : 'not present'}`);
}

if (require.main === module) {
  main();
}
