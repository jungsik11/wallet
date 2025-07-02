import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'responsive_text.dart';

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
    // Do not load previous messages. Start with a fresh screen and a greeting.
    _messages.add(_Message(
      id: 0,
      text: '안녕하세요! 무엇을 도와드릴까요?',
      sender: 'ai',
      createdAt: DateTime.now(),
      modelName: 'greeting'
    ));
    _fetchModels();
  }

  // Saves a message to the backend.
  Future<void> _postMessageToServer(Map<String, dynamic> messageData) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiUrl/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(messageData),
      );
      if (response.statusCode != 200) {
         _showError('Failed to save message: ${response.reasonPhrase}');
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
        'prompt': "You are a helpful assistant. Answer the following question in Korean. Be concise and to the point. Question: $userMessageText",
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
                  // Stream is done, save the final message
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
            // Ensure the final message is saved if the stream closes unexpectedly
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
    final theme = Theme.of(context);
    return Scaffold(
<<<<<<< Updated upstream
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 8.0, 8.0, 8.0),
=======
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 8.0, top: 8.0),
>>>>>>> Stashed changes
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _isFetchingModels
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2.0))
                    : DropdownButton<String>(
                        value: _selectedModel,
<<<<<<< Updated upstream
                        hint: const Text('Select Model', style: TextStyle(color: Colors.white70)),
                        dropdownColor: Colors.grey[800],
=======
                        hint: Text('Select Model', style: TextStyle(color: Colors.black87, fontSize: getResponsiveFontSize(context, 14))),
                        dropdownColor: Colors.white,
>>>>>>> Stashed changes
                        items: _models.map((String model) {
                          return DropdownMenuItem<String>(
                            value: model,
                            child: Text(
                              model.length > 20 ? '${model.substring(0, 17)}...' : model,
                              overflow: TextOverflow.ellipsis,
<<<<<<< Updated upstream
                              style: const TextStyle(color: Colors.white),
=======
                              style: TextStyle(color: Colors.black87, fontSize: getResponsiveFontSize(context, 14)),
>>>>>>> Stashed changes
                            ),
                          );
                        }).toList(),
                        onChanged: (String? newValue) => setState(() => _selectedModel = newValue),
                        underline: Container(),
                      ),
<<<<<<< Updated upstream
                IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.of(context).pop()),
=======
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.black54),
                  onPressed: () => Navigator.of(context).pop(),
                ),
>>>>>>> Stashed changes
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
                final isUser = message.sender == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 5.0, horizontal: 8.0),
<<<<<<< Updated upstream
                    padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                    decoration: BoxDecoration(
                      color: isUser ? theme.colorScheme.secondary.withOpacity(0.8) : theme.cardColor,
                      borderRadius: BorderRadius.circular(20.0),
                    ),
                    child: Column(
                      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        Text(message.text, style: theme.textTheme.bodyLarge),
                        if (message.modelName != null && message.modelName != 'greeting')
                          Padding(
                            padding: const EdgeInsets.only(top: 5.0),
                            child: Text(
                              'Model: ${message.modelName}',
                              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
                            ),
                          ),
                      ],
=======
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14.0, vertical: 10.0),
                    decoration: BoxDecoration(
                      color: message.isUser
                          ? Colors.grey[200]
                          : const Color(0xFF80CBC4), // Desaturated teal
                      borderRadius: BorderRadius.circular(20.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          spreadRadius: 1,
                          blurRadius: 3,
                          offset: const Offset(0, 2), // changes position of shadow
                        ),
                      ],
                    ),
                    child: Text(
                      message.text,
                      style: TextStyle(color: message.isUser ? Colors.black87 : Colors.white, fontSize: getResponsiveFontSize(context, 15)),
>>>>>>> Stashed changes
                    ),
                  ),
                );
              },
            ),
          ),
<<<<<<< Updated upstream
          if (_isLoading) const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0), child: LinearProgressIndicator()),
=======
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: LinearProgressIndicator(backgroundColor: Colors.grey[200], valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF80CBC4))),
            ),
>>>>>>> Stashed changes
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
<<<<<<< Updated upstream
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: '메시지를 입력하세요...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.grey[800],
=======
                    style: TextStyle(color: Colors.black87, fontSize: getResponsiveFontSize(context, 16)),
                    decoration: InputDecoration(
                      hintText: '메시지를 입력하세요...',
                      hintStyle: TextStyle(color: Colors.grey[600], fontSize: getResponsiveFontSize(context, 16)),
                      filled: true,
                      fillColor: Colors.grey[100],
>>>>>>> Stashed changes
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30.0),
                        borderSide: BorderSide.none,
                      ),
<<<<<<< Updated upstream
=======
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
>>>>>>> Stashed changes
                    ),
                    onSubmitted: (value) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
<<<<<<< Updated upstream
                FloatingActionButton(
                  mini: true,
                  onPressed: _isLoading || _selectedModel == null ? null : _sendMessage,
                  child: const Icon(Icons.send),
                  backgroundColor: theme.colorScheme.secondary,
=======
                IconButton(
                  icon: const Icon(Icons.send, color: Color(0xFF80CBC4)),
                  onPressed: _isLoading || _selectedModel == null
                      ? null
                      : _sendMessage,
>>>>>>> Stashed changes
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
