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
  String text;
  final bool isUser;

  _Message({required this.text, required this.isUser});
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_Message> _messages = [
    _Message(text: '안녕하세요! 무엇을 도와드릴까요?', isUser: false),
  ];
  bool _isLoading = false;
  List<String> _models = [];
  String? _selectedModel;
  bool _isFetchingModels = true;

  @override
  void initState() {
    super.initState();
    _fetchModels();
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
      final response =
          await http.get(Uri.parse('http://localhost:11434/api/tags'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = (data['models'] as List)
            .map((model) => model['name'] as String)
            .toList();
        setState(() {
          _models = models;
          if (_models.isNotEmpty) {
            _selectedModel = _models.contains('llama3:latest')
                ? 'llama3:latest'
                : _models.first;
          }
          _isFetchingModels = false;
        });
      } else {
        throw Exception('Failed to load models');
      }
    } catch (e) {
      setState(() {
        _isFetchingModels = false;
        // You could show an error message to the user here
      });
      print('Error fetching models: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_controller.text.isEmpty || _selectedModel == null) return;

    final userMessage = _Message(text: _controller.text, isUser: true);
    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
    });
    _controller.clear();
    _scrollToBottom();

    final botMessage = _Message(text: '', isUser: false);
    setState(() {
      _messages.add(botMessage);
    });

    try {
      final request = http.Request(
        'POST',
        Uri.parse('http://localhost:11434/api/generate'),
      );
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        'model': _selectedModel,
        'prompt': "다음 질문에 대해 요점만 간략하게 한국어로만 대답해: ${userMessage.text}",
        'stream': true,
        'options': {'num_predict': 512}
      });

      final response = await request.send();

      if (response.statusCode == 200) {
        response.stream.transform(utf8.decoder).listen((value) {
          final lines = value.split('\n');
          for (final line in lines) {
            if (line.isNotEmpty) {
              final jsonResponse = jsonDecode(line);
              if (jsonResponse['response'] != null) {
                setState(() {
                  botMessage.text += jsonResponse['response'];
                });
                _scrollToBottom();
              }
              if (jsonResponse['done'] == true) {
                setState(() {
                  _isLoading = false;
                });
              }
            }
          }
        });
      } else {
        setState(() {
          botMessage.text = 'Error: ${response.reasonPhrase}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        botMessage.text = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 8.0, top: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _isFetchingModels
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.0))
                    : DropdownButton<String>(
                        value: _selectedModel,
                        hint: Text('Select Model', style: TextStyle(color: Colors.black87, fontSize: getResponsiveFontSize(context, 14))),
                        dropdownColor: Colors.white,
                        items: _models.map((String model) {
                          return DropdownMenuItem<String>(
                            value: model,
                            child: Text(
                              model.length > 20
                                  ? '${model.substring(0, 17)}...'
                                  : model,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.black87, fontSize: getResponsiveFontSize(context, 14)),
                            ),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedModel = newValue;
                          });
                        },
                      ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.black54),
                  onPressed: () => Navigator.of(context).pop(),
                ),
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
                  alignment: message.isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 5.0, horizontal: 8.0),
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
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: LinearProgressIndicator(backgroundColor: Colors.grey[200], valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF80CBC4))),
            ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: TextStyle(color: Colors.black87, fontSize: getResponsiveFontSize(context, 16)),
                    decoration: InputDecoration(
                      hintText: '메시지를 입력하세요...',
                      hintStyle: TextStyle(color: Colors.grey[600], fontSize: getResponsiveFontSize(context, 16)),
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30.0),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                    ),
                    onSubmitted: (value) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: Color(0xFF80CBC4)),
                  onPressed: _isLoading || _selectedModel == null
                      ? null
                      : _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
