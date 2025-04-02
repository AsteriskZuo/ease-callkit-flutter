import 'dart:math';

import 'package:em_chat_callkit/chat_callkit.dart';

import 'package:em_chat_callkit_example/tools/request_tool.dart';
import 'package:flutter/material.dart';

import 'package:permission_handler/permission_handler.dart';

import 'call_pages/multi_call_page.dart';
import 'call_pages/single_call_page.dart';
import 'config.dart';
import 'contact_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  assert(Config.appkey.isNotEmpty, 'must set appkey.');
  final options = ChatOptions.withAppKey(
    Config.appkey,
    autoLogin: false,
  );
  await ChatCallKitClient.getInstance.init(options);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (context, child) {
        return ChatCallKit(
          agoraAppId: Config.agoraAppId,
          child: child!,
        );
      },
      title: 'Callkit demo',
      home: const MyHomePage(title: 'Callkit demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with ChatCallKitObserver {
  ScrollController scrollController = ScrollController();
  String _chatId = "";
  String _userId = '';
  String _token = '';
  final List<String> _logText = [];

  @override
  void initState() {
    super.initState();
    // set agoraToken request handler.
    ChatCallKitManager.setRTCTokenHandler((channel, agoraAppId) {
      return requestRtcToken(channel, Random().nextInt(999999));
    });

    // set agoraUid and userId mapper handler.
    ChatCallKitManager.setUserMapperHandler((channel, agoraUid) {
      return requestAppServerUserMapper(channel, agoraUid);
    });

    ChatCallKitManager.addObserver(this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Container(
        padding: const EdgeInsets.only(left: 10, right: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.max,
          children: [
            Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: "UserId",
                    ),
                    onChanged: (userId) => _userId = userId,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: "Password",
                    ),
                    onChanged: (pwd) => _token = pwd,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  flex: 1,
                  child: TextButton(
                    onPressed: _signIn,
                    style: ButtonStyle(
                      foregroundColor: WidgetStateProperty.all(Colors.white),
                      backgroundColor:
                          WidgetStateProperty.all(Colors.lightBlue),
                    ),
                    child: const Text("SIGN IN"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextButton(
                    onPressed: _signOut,
                    style: ButtonStyle(
                      foregroundColor: WidgetStateProperty.all(Colors.white),
                      backgroundColor:
                          WidgetStateProperty.all(Colors.lightBlue),
                    ),
                    child: const Text("SIGN OUT"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextButton(
                    onPressed: _signUp,
                    style: ButtonStyle(
                      foregroundColor: WidgetStateProperty.all(Colors.white),
                      backgroundColor:
                          WidgetStateProperty.all(Colors.lightBlue),
                    ),
                    child: const Text("SIGN UP"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: "Enter userId",
                    ),
                    onChanged: (chatId) => _chatId = chatId,
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: audioCall,
                  style: ButtonStyle(
                    foregroundColor: WidgetStateProperty.all(Colors.white),
                    backgroundColor: WidgetStateProperty.all(Colors.lightBlue),
                  ),
                  child: const Text("1v1Audio"),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: videoCall,
                  style: ButtonStyle(
                    foregroundColor: WidgetStateProperty.all(Colors.white),
                    backgroundColor: WidgetStateProperty.all(Colors.lightBlue),
                  ),
                  child: const Text("1v1Video"),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: multiCall,
              style: ButtonStyle(
                foregroundColor: WidgetStateProperty.all(Colors.white),
                backgroundColor: WidgetStateProperty.all(Colors.lightBlue),
              ),
              child: const Text("Multi Call"),
            ),
            Flexible(
              child: ListView.builder(
                controller: scrollController,
                itemBuilder: (_, index) {
                  return Text(_logText[index]);
                },
                itemCount: _logText.length,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _signIn() async {
    _addLogToConsole('sign in...');
    String? agoraToken = await fetchAccountToken(_userId, _token);
    if (agoraToken == null) {
      _addLogToConsole('sign in fail.');
    } else {
      try {
        await ChatCallKitClient.getInstance.loginWithToken(_userId, agoraToken);

        _addLogToConsole('sign in success');
      } on ChatCallKitChatError catch (e) {
        _addLogToConsole('sign in fail: ${e.description}');
      }
    }
  }

  void _signOut() async {
    _addLogToConsole('sign out...');
    try {
      await ChatCallKitClient.getInstance.logout();
      _addLogToConsole('sign out success');
    } on ChatCallKitChatError catch (e) {
      _addLogToConsole('sign out fail: ${e.description}');
    }
  }

  void _signUp() async {
    _addLogToConsole('sign up...');
    String? errorStr = await registerAccount(_userId, _token);
    if (errorStr != null) {
      _addLogToConsole('sign up fail: $errorStr');
    } else {
      _addLogToConsole('sign up success');
    }
  }

  void audioCall() async {
    pushToCallPage([_chatId], ChatCallKitCallType.audio_1v1);
  }

  void videoCall() async {
    pushToCallPage([_chatId], ChatCallKitCallType.video_1v1);
  }

  void multiCall() async {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) {
      return const ContactPage(isMulti: true);
    })).then((value) {
      if (value != null && value is List && value.isNotEmpty) {
        pushToCallPage(value as List<String>, ChatCallKitCallType.multi);
      }
    });
  }

  @override
  void onReceiveCall(
    String userId,
    String callId,
    ChatCallKitCallType callType,
    Map<String, String>? ext,
  ) async {
    pushToCallPage([userId], callType, callId);
  }

  void pushToCallPage(List<String> userIds, ChatCallKitCallType callType,
      [String? callId]) async {
    Widget page;
    if (callType == ChatCallKitCallType.multi) {
      if (callId == null) {
        page = MultiCallPage.call(userIds);
      } else {
        page = MultiCallPage.receive(callId, userIds.first);
      }
    } else {
      if (callId == null) {
        page = SingleCallPage.call(userIds.first, type: callType);
      } else {
        page = SingleCallPage.receive(userIds.first, callId, type: callType);
      }
    }

    [Permission.microphone, Permission.camera].request().then((value) {
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) {
            return page;
          }),
        ).then((value) {
          if (value != null) {
            debugPrint('call end: $value');
          }
        });
      }
    });
  }

  @override
  void dispose() {
    ChatCallKitManager.removeObserver(this);
    super.dispose();
  }

  void _addLogToConsole(String log) {
    _logText.add("$_timeString: $log");
    setState(() {
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
    });
  }

  String get _timeString {
    return DateTime.now().toString().split(".").first;
  }
}
