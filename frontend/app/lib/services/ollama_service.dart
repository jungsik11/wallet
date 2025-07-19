import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:app/constants/api_constants.dart';

class OllamaService {
  Future<List<String>> fetchOllamaModels() async {
    try {
      final response = await http.get(Uri.parse(ApiConstants.ollamaListModels));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        final List<dynamic> models = data['models'] ?? [];
        return models.map((model) => model['name'].toString()).toList();
      } else {
        throw Exception('Failed to load Ollama models: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching Ollama models: $e');
    }
  }

  Stream<String> sendChatMessage({required String model, required String prompt}) async* {
    final request = http.Request(
      'POST',
      Uri.parse('${ApiConstants.ollamaBaseUrl}/api/generate'),
    );
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode({
      'model': model,
      'prompt': prompt,
      'stream': true,
      'options': {'num_predict': 512}
    });

    final response = await request.send();

    if (response.statusCode == 200) {
      await for (var chunk in response.stream.transform(utf8.decoder)) {
        final lines = chunk.split('\n');
        for (final line in lines) {
          if (line.isNotEmpty) {
            final jsonResponse = jsonDecode(line);
            if (jsonResponse['response'] != null) {
              yield jsonResponse['response'];
            }
            if (jsonResponse['done'] == true) {
              return; // End of stream
            }
          }
        }
      }
    } else {
      throw Exception('Failed to send message: ${response.reasonPhrase}');
    }
  }
}
