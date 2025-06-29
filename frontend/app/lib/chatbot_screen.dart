import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({Key? key}) : super(key: key);

  @override
  _ChatbotScreenState createState() => _ChatbotScreenState();
}

class _Message {
  final int id;
  String text;
  final String sender;
  final String? modelName;
  final DateTime createdAt;

  _Message({
    required this.id,
    required this.text,
    required this.sender,
    this.modelName,
    required this.createdAt,
  });

  factory _Message.fromJson(Map<String, dynamic> json) {
    return _Message(
      id: json['id'],
      text: json['message'],
      sender: json['sender'],
      modelName: json['model_name'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_Message> _messages = [];
  bool _isLoading = false;
  List<String> _models = [];
  String? _selectedModel;
  bool _isFetchingModels = true;
  final String _apiUrl = 'http://localhost:8000'; // Backend API URL

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _fetchModels();
  }

  Future<void> _loadMessages() async {
    try {
      final response = await http.get(Uri.parse('$_apiUrl/chat'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _messages.addAll(data.map((m) => _Message.fromJson(m)).toList());
        });
        if (_messages.isEmpty) {
          _postInitialMessage();
        }
      } else {
        _showError('Failed to load chat history.');
      }
    } catch (e) {
      _showError('Error loading messages: $e');
    }
    _scrollToBottom();
  }

  Future<void> _postInitialMessage() async {
    final initialMessage = {
      'sender': 'ai',
      'message': '안녕하세요! 무엇을 도와드릴까요?',
      'model_name': 'initial'
    };
    await _postMessageToServer(initialMessage, isInitial: true);
  }

  Future<void> _postMessageToServer(Map<String, dynamic> messageData, {bool isInitial = false}) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiUrl/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(messageData),
      );
      if (response.statusCode == 200) {
        if (isInitial) {
          setState(() {
            _messages.add(_Message.fromJson(jsonDecode(utf8.decode(response.bodyBytes))));
          });
        }
      } else {
         _showError('Failed to save message.');
      }
    } catch (e) {
      _showError('Error saving message: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _fetchModels() async {
    try {
      final response = await http.get(Uri.parse('http://localhost:11434/api/tags'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = (data['models'] as List).map((model) => model['name'] as String).toList();
        setState(() {
          _models = models;
          if (_models.isNotEmpty) {
            _selectedModel = _models.contains('llama3:latest') ? 'llama3:latest' : _models.first;
          }
          _isFetchingModels = false;
        });
      } else {
        throw Exception('Failed to load models');
      }
    } catch (e) {
      setState(() {
        _isFetchingModels = false;
      });
      print('Error fetching models: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_controller.text.isEmpty || _selectedModel == null) return;

    final userMessageText = _controller.text;
    _controller.clear();

    // 1. Save user message to DB and update UI
    final userMessageData = {'sender': 'user', 'message': userMessageText};
    await _postMessageToServer(userMessageData);
    // For immediate UI update, we can create a temporary message object
    // Or reload all messages from the server after posting.
    // Here we optimistically add to the UI.
    setState(() {
       _messages.add(_Message(id: -1, text: userMessageText, sender: 'user', createdAt: DateTime.now())); // temp id
       _isLoading = true;
    });
    _scrollToBottom();

    // 2. Get AI response and save to DB
    final botMessage = _Message(id: -1, text: '', sender: 'ai', modelName: _selectedModel, createdAt: DateTime.now());
    setState(() {
      _messages.add(botMessage);
    });

    try {
      final request = http.Request('POST', Uri.parse('http://localhost:11434/api/generate'));
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        'model': _selectedModel,
        'prompt': "다음 질문에 대해 요점만 간략하게 한국어로만 대답해: $userMessageText",
        'stream': true,
        'options': {'num_predict': 512}
      });

      final response = await request.send();
      String accumulatedResponse = '';

      if (response.statusCode == 200) {
        response.stream.transform(utf8.decoder).listen(
          (value) {
            final lines = value.split('\n');
            for (final line in lines) {
              if (line.isNotEmpty) {
                final jsonResponse = jsonDecode(line);
                if (jsonResponse['response'] != null) {
                  accumulatedResponse += jsonResponse['response'] as String;
                  setState(() => botMessage.text = accumulatedResponse);
                  _scrollToBottom();
                }
                if (jsonResponse['done'] == true) {
                  final aiMessageData = {
                    'sender': 'ai',
                    'message': accumulatedResponse,
                    'model_name': _selectedModel
                  };
                  _postMessageToServer(aiMessageData);
                  setState(() => _isLoading = false);
                }
              }
            }
          },
          onDone: () {
             if (_isLoading) {
                final aiMessageData = {
                    'sender': 'ai',
                    'message': accumulatedResponse,
                    'model_name': _selectedModel
                  };
                  _postMessageToServer(aiMessageData);
                  setState(() => _isLoading = false);
             }
          },
          onError: (e) => _showError('Stream error: $e'),
        );
      } else {
        _showError('API Error: ${response.reasonPhrase}');
      }
    } catch (e) {
      _showError('Error: $e');
    }
  }

  void _showError(String message) {
    setState(() {
      _isLoading = false;
      if (_messages.isNotEmpty && _messages.last.sender == 'ai' && _messages.last.text.isEmpty) {
        _messages.last.text = message;
      }
    });
    print(message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // ... (UI code remains largely the same)
          Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _isFetchingModels
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2.0))
                    : DropdownButton<String>(
                        value: _selectedModel,
                        hint: const Text('Select Model'),
                        items: _models.map((String model) {
                          return DropdownMenuItem<String>(
                            value: model,
                            child: Text(model.length > 20 ? '${model.substring(0, 17)}...' : model, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (String? newValue) => setState(() => _selectedModel = newValue),
                      ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return Align(
                  alignment: message.sender == 'user' ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4.0),
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                    decoration: BoxDecoration(
                      color: message.sender == 'user' ? Colors.blue[100] : Colors.grey[300],
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(message.text),
                        if (message.modelName != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text('Model: ${message.modelName}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoading) const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: LinearProgressIndicator()),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(hintText: '메시지를 입력하세요...', border: OutlineInputBorder()),
                    onSubmitted: (value) => _sendMessage(),
                  ),
                ),
                IconButton(icon: const Icon(Icons.send), onPressed: _isLoading || _selectedModel == null ? null : _sendMessage),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
