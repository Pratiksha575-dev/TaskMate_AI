import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dialogflow_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatScreen extends StatefulWidget {
  final DialogflowService dialogflowService;

  const ChatScreen({Key? key, required this.dialogflowService}) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late DialogflowService _dialogflowService;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> messages = [];

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool isListening = false;
  bool isMicEnabledByUser = false;
  bool _isSpeechInitialized = false;
  String? userName;

  String removeEmojis(String text) {
    final emojiRegex = RegExp(
      r'[\u{1F600}-\u{1F64F}'  // Emoticons
      r'\u{1F300}-\u{1F5FF}'  // Symbols & pictographs
      r'\u{1F680}-\u{1F6FF}'  // Transport/map symbols
      r'\u{2600}-\u{26FF}'    // Misc symbols
      r'\u{2700}-\u{27BF}'    // Dingbats
      r'\u{1F1E6}-\u{1F1FF}'  // Flags
      r'\u{1F900}-\u{1F9FF}'  // Supplemental symbols
      r'\u{1FA70}-\u{1FAFF}'  // More symbols
      r'\u{200D}'             // Zero width joiner
      r'\u{FE0F}]',           // Variation selector
      unicode: true,
    );
    return text.replaceAll(emojiRegex, '').trim();
  }

  @override
  void initState() {
    super.initState();
    _dialogflowService = widget.dialogflowService;
    _initializeSpeech();
    _fetchUserName();

    _tts.setCompletionHandler(() {
      print("🔁 TTS complete");
      if (isMicEnabledByUser && !_speech.isListening) {
        startListening();
      }
    });
  }

  Future<void> _initializeSpeech() async {
    try {
      bool available = await _speech.initialize(
        onStatus: (status) => print("STT Status: $status"),
        onError: (error) async {
          print("❌ STT Error: ${error.errorMsg}");

          if (error.errorMsg == 'error_no_match' && isMicEnabledByUser) {
            print("⚠️ No match. Restarting listening...");
            await Future.delayed(Duration(milliseconds: 500));
            startListening();
          }
        },
      );
      if (available) {
        print("✅ STT Initialized Successfully");
        _isSpeechInitialized = true;
      }
    } catch (e) {
      print("❌ Speech init error: $e");
    }
  }

  late String currentUserId;
  void _fetchUserName() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        currentUserId = user.uid;
        print("🧠 Logged-in user ID: $currentUserId");
      }

      // Fetch name as before if needed
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(user!.uid).get();
      setState(() {
        userName = userDoc.exists ? userDoc['name'] : null;
      });
    } catch (e) {
      print("❌ Error fetching user data: $e");
    }
  }

  void toggleListening() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      await Permission.microphone.request();
      return;
    }

    if (!isMicEnabledByUser) {
      print("🎤 Mic enabled by user");
      isMicEnabledByUser = true;
      startListening();
    } else {
      print("🛑 Mic disabled by user");
      isMicEnabledByUser = false;
      await _speech.stop();
      setState(() => isListening = false);
    }
  }

  void startListening() async {
    if (!_isSpeechInitialized || !isMicEnabledByUser) return;

    print("🎧 Listening...");
    setState(() => isListening = true);

    await _speech.listen(
      onResult: (result) async {
        if (result.finalResult) {
          String spokenText = result.recognizedWords.trim();
          print("✅ Final recognized: $spokenText");

          if (spokenText.isNotEmpty) {
            setState(() {
              messages.add({"text": spokenText, "isUser": true});
            });

            try {
              String botReply = await _dialogflowService.getDialogflowResponse(spokenText, userId: currentUserId);
              botReply = botReply.isEmpty ? "I'm not sure how to help with that." : botReply;

              setState(() {
                messages.add({"text": botReply, "isUser": false});
              });

              await _speech.stop();
              setState(() => isListening = false);
              await _speak(botReply);
            } catch (e) {
              print("❌ Dialogflow error: $e");
            }

            scrollToBottom();
          }
        }
      },
      listenMode: stt.ListenMode.dictation,
      cancelOnError: false,
      partialResults: true,
    );
  }

  void sendMessage(String userMessage) async {
    if (userMessage.isEmpty) return;

    setState(() {
      messages.add({"text": userMessage, "isUser": true});
    });
    _controller.clear();
    scrollToBottom();

    try {
      String botResponse = await _dialogflowService.getDialogflowResponse(userMessage, userId: currentUserId);
      botResponse = botResponse.isEmpty ? "I'm not sure how to help with that." : botResponse;

      setState(() {
        messages.add({"text": botResponse, "isUser": false});
      });

      await _speak(botResponse);
    } catch (e) {
      print("❌ Dialogflow error: $e");
    }

    scrollToBottom();
  }

  Future<void> _speak(String text) async {
    try {
      final cleaned = removeEmojis(text);
      await _tts.setLanguage("en-US");
      await _tts.setPitch(1.0);
      await _tts.speak(cleaned);
    } catch (e) {
      print("🔇 TTS error: $e");
    }
  }

  void scrollToBottom() {
    Future.delayed(Duration(milliseconds: 300), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF101828),
      appBar: AppBar(
        backgroundColor: Color(0xFF181F35),
        title: Text("Chatbot", style: TextStyle(color: Colors.white)),
        iconTheme: IconThemeData(color: Colors.white),
        elevation: 2,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: messages.length,
              itemBuilder: (context, index) {
                bool isUser = messages[index]['isUser'];
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    padding: EdgeInsets.all(12),
                    margin: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                    decoration: BoxDecoration(
                      color: isUser ? Color(0xFF397EFA) : Color(0xFF9D4EDD),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      messages[index]['text'],
                      style: TextStyle(color: Colors.white, fontSize: 17),
                    ),
                  ),
                );
              },
            ),
          ),

          /// 🔴 Glowing Mic Animation
          AnimatedContainer(
            duration: Duration(milliseconds: 300),
            height: isListening ? 80 : 0,
            curve: Curves.easeInOut,
            child: isListening
                ? Center(
              child: Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.withOpacity(0.1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.6),
                      blurRadius: 25,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(Icons.mic, color: Colors.red, size: 36),
              ),
            )
                : SizedBox.shrink(),
          ),

          /// 💬 Message input field and buttons
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: TextStyle(color: Colors.white, fontSize: 17),
                    decoration: InputDecoration(
                      hintText: "Type a message...",
                      hintStyle: TextStyle(color: Color(0xFFA0AEC0)),
                      filled: true,
                      fillColor: Color(0xFF1E1E2E),
                      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                IconButton(
                  icon: Icon(
                    isMicEnabledByUser ? Icons.mic : Icons.mic_none,
                    color: isMicEnabledByUser ? Color(0xFFEF4444) : Color(0xFF9D4EDD),
                    size: 28,
                  ),
                  onPressed: toggleListening,
                ),
                IconButton(
                  icon: Icon(Icons.send, color: Color(0xFF9D4EDD), size: 26),
                  onPressed: () => sendMessage(_controller.text.trim()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}