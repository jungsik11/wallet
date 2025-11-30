import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'responsive_text.dart';
import 'package:app/services/ollama_service.dart'; // Add this import

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

  final OllamaService _ollamaService = OllamaService(); // Add OllamaService instance

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
              final models = await _ollamaService.fetchOllamaModels();
              setState(() {
                _models = models;
                if (_models.isNotEmpty) {
                  String? preferredModel;
                  // First, try to find a model that contains 'gpt' (case-insensitive)
                  for (String modelName in models) {
                    if (modelName.toLowerCase().contains('gpt')) {
                      preferredModel = modelName;
                      break;
                    }
                  }
      
                  if (preferredModel != null) {
                    _selectedModel = preferredModel;
                  } else if (_models.contains('llama3:latest')) {
                    _selectedModel = 'llama3:latest';
                  } else {
                    _selectedModel = _models.first;
                  }
                }
                _isFetchingModels = false;
              });    } catch (e) {
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
      await for (var chunk in _ollamaService.sendChatMessage(
          model: _selectedModel!,
          prompt: "다음 질문에 대해 요점만 간략하게 한국어로만 대답해: ${userMessage.text}")) {
        setState(() {
          botMessage.text += chunk;
        });
        _scrollToBottom();
      }
      setState(() {
        _isLoading = false;
      });
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
      backgroundColor: Colors.transparent,
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
                                              child: CircularProgressIndicator(strokeWidth: 2.0, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                                          : DropdownButton<String>(
                                              value: _selectedModel,
                                              hint: Text('Select Model', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: getResponsiveFontSize(context, 11))),
                                              dropdownColor: Theme.of(context).cardColor,
                                              items: _models.map((String model) {
                                                return DropdownMenuItem<String>(
                                                  value: model,
                                                  child: Text(
                                                    model.length > 20
                                                        ? '${model.substring(0, 17)}...'
                                                        : model,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: getResponsiveFontSize(context, 11)),
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
                                        icon: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
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
                                                ? Theme.of(context).colorScheme.primaryContainer
                                                : Theme.of(context).colorScheme.secondaryContainer, // Desaturated teal
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
                                            style: TextStyle(color: message.isUser ? Theme.of(context).colorScheme.onPrimaryContainer : Theme.of(context).colorScheme.onSecondaryContainer, fontSize: getResponsiveFontSize(context, 11)),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                if (_isLoading)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                    child: LinearProgressIndicator(backgroundColor: Theme.of(context).colorScheme.surfaceVariant, valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.secondary)),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _controller,
                                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: getResponsiveFontSize(context, 11)),
                                          decoration: InputDecoration(
                                            hintText: '메시지를 입력하세요...',
                                            hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: getResponsiveFontSize(context, 11)),
                                            filled: true,
                                            fillColor: Theme.of(context).colorScheme.surfaceVariant,
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
                                        icon: Icon(Icons.send, color: Theme.of(context).colorScheme.secondary), // Use theme color
                                        onPressed: _isLoading || _selectedModel == null
                                            ? null
                                            : _sendMessage,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),    );
  }
}
