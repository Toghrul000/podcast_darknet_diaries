import 'dart:convert';

import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:podcast_darknet_diaries/audio_player.dart';
import 'package:podcast_darknet_diaries/image_item.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;

class DownloadProvider with ChangeNotifier {
  final Map<int, bool> _downloading = {};
  final Map<int, double> _downloadProgress = {};
  final Map<int, String> _imagePaths = {};
  final Map<int, String> _audioPaths = {};
  final Map<int, Completer<void>> _downloadCompleters = {};
  final Map<int, http.Client> _httpClients = {}; // Keep track of HTTP clients

  bool isDownloading(int episodeNumber) => _downloading[episodeNumber] ?? false;
  double getDownloadProgress(int episodeNumber) => _downloadProgress[episodeNumber] ?? 0.0;
  String? getImagePath(int episodeNumber) => _imagePaths[episodeNumber];
  String? getAudioPath(int episodeNumber) => _audioPaths[episodeNumber];

  void startDownload(int episodeNumber) {
    if (!_downloading.containsKey(episodeNumber) || !_downloading[episodeNumber]!) {
      _downloading[episodeNumber] = true;
      _downloadCompleters[episodeNumber] = Completer<void>();
      _httpClients[episodeNumber] = http.Client(); // Initialize HTTP client
      _downloadProgress[episodeNumber] = 0.0;
      notifyListeners();
    }
  }

  void updateDownloadProgress(int episodeNumber, double progress) {
    if (_downloading[episodeNumber] ?? false) {
      _downloadProgress[episodeNumber] = progress;
      notifyListeners();
    }
  }

  void completeDownload(int episodeNumber, String imagePath, String audioPath) {
    if (_downloading[episodeNumber] ?? false) {
      _downloading[episodeNumber] = false;
      _downloadProgress[episodeNumber] = 1.0;
      _imagePaths[episodeNumber] = imagePath;
      _audioPaths[episodeNumber] = audioPath;
      _downloadCompleters[episodeNumber]?.complete();
      _cleanUpAfterDownload(episodeNumber);
      notifyListeners();
    }
  }

  void deleteDownload(int episodeNumber) {
    _downloading.remove(episodeNumber);
    _downloadProgress.remove(episodeNumber);
    _imagePaths.remove(episodeNumber);
    _audioPaths.remove(episodeNumber);
    _downloadCompleters.remove(episodeNumber);
    _httpClients[episodeNumber]?.close(); 
    _httpClients.remove(episodeNumber);
    notifyListeners();
  }

  void cancelDownload(BuildContext context, int episodeNumber) async {
    if (_downloading[episodeNumber] ?? false) {
      _downloading[episodeNumber] = false;
      _downloadProgress[episodeNumber] = 0.0;
      _httpClients[episodeNumber]?.close(); // Cancel the download by closing the client
      _cleanUpAfterDownload(episodeNumber);
      notifyListeners();

      // Delete partially downloaded files and metadata
      await _deleteFiles(episodeNumber);

      // Show "Download cancelled" message
      if(context.mounted){
        _showSnackBarMessage(context, 'Download cancelled', Colors.red);
      }
      
      // Complete the completer to unblock any awaiters
      _downloadCompleters[episodeNumber]?.complete();
    }
  }

  void _cleanUpAfterDownload(int episodeNumber) {
    // Clean up any state associated with the download
    _downloadCompleters.remove(episodeNumber);
    _httpClients.remove(episodeNumber);
  }

  Future<void> _deleteFiles(int episodeNumber) async {
    final imagePath = _imagePaths[episodeNumber];
    final audioPath = _audioPaths[episodeNumber];
    if (imagePath != null) {
      final imageFile = File(imagePath);
      if (await imageFile.exists()) {
        await imageFile.delete();
      }
    }
    if (audioPath != null) {
      final audioFile = File(audioPath);
      if (await audioFile.exists()) {
        await audioFile.delete();
      }
    }

    // Reset metadata in SharedPreferences
    _resetMetadata(episodeNumber);
  }

  void _resetMetadata(int episodeNumber) {
    _imagePaths.remove(episodeNumber);
    _audioPaths.remove(episodeNumber);
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('offline_ep_$episodeNumber');
      List<String> downloads = prefs.getStringList('downloads') ?? [];
      downloads.remove(episodeNumber.toString());
      prefs.setStringList('downloads', downloads);
    });
  }

  Future<void> awaitDownload(int episodeNumber) {
    return _downloadCompleters[episodeNumber]?.future ?? Future.value();
  }

  void updateImagePath(int episodeNumber, String imagePath) {
    _imagePaths[episodeNumber] = imagePath;
    notifyListeners();
  }

  void updateAudioPath(int episodeNumber, String audioPath) {
    _audioPaths[episodeNumber] = audioPath;
    notifyListeners();
  }

  Future<void> downloadEpisode(BuildContext context, int episodeNumber, String title, String dateTime, String imageUrl, String mp3Url) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> downloads = prefs.getStringList('downloads') ?? [];
    if (!downloads.contains(episodeNumber.toString())) {
      if (context.mounted) {
        startDownload(episodeNumber);
        await _saveEpisodeFilesWithProgress(context, episodeNumber, imageUrl, mp3Url, (progress) {
          updateDownloadProgress(episodeNumber, progress);
        });
        if(isDownloading(episodeNumber)){
          if (getImagePath(episodeNumber) != null && getAudioPath(episodeNumber) != null) {
            await saveEpisodeMetadata(episodeNumber.toString(), title, dateTime, getImagePath(episodeNumber)!, getAudioPath(episodeNumber)!);
          }

          completeDownload(episodeNumber, getImagePath(episodeNumber)!, getAudioPath(episodeNumber)!);
          if(context.mounted){
            _showSnackBarMessage(context, 'Download finished', Colors.green);
          }
        }
      }
    } else {
      if (context.mounted) {
        _showSnackBarMessage(context, 'Already in Downloads!', Colors.red);
      }
    }
  }

  Future<void> _saveEpisodeFilesWithProgress(BuildContext context, int episodeNumber, String imageUrl, String audioUrl, Function(double) onProgress) async {
    final directory = await getApplicationDocumentsDirectory();
    final imgDir = Directory('${directory.path}/assets/img');
    if (!await imgDir.exists()) {
      await imgDir.create(recursive: true);
    }

    final audioDir = Directory('${directory.path}/assets/audio');
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }
    if (context.mounted) {
      final imagePath = '${directory.path}/assets/img/episode_$episodeNumber.jpg';
      final imageFile = File(imagePath);
      await _downloadFile(context, episodeNumber, imageUrl, imageFile);
      updateImagePath(episodeNumber, imagePath);
    }

    if (context.mounted) {
      final audioPath = '${directory.path}/assets/audio/episode_$episodeNumber.mp3';
      final audioFile = File(audioPath);
      await _downloadFileWithProgress(context, episodeNumber, audioUrl, audioFile, onProgress);
      updateAudioPath(episodeNumber, audioPath);
    }
  }

  Future<void> _downloadFile(BuildContext context, int episodeNumber, String url, File file) async {
    final client = _httpClients[episodeNumber];
    if (client == null || !isDownloading(episodeNumber)) return;

    try {
      final response = await client.send(http.Request('GET', Uri.parse(url)));
      final fileSink = file.openWrite();
      try {
        await response.stream.listen((chunk) {
          fileSink.add(chunk);
        }).asFuture();
      } finally {
        if(isDownloading(episodeNumber)){
          await fileSink.flush();
          await fileSink.close();
        }
      }
    } on http.ClientException {
      return;
    }

  }

  Future<void> _downloadFileWithProgress(BuildContext context, int episodeNumber, String url, File file, Function(double) onProgress) async {
    final client = _httpClients[episodeNumber];
    if (client == null || !isDownloading(episodeNumber)) return;
    try {
      final response = await client.send(http.Request('GET', Uri.parse(url)));
      final contentLength = response.contentLength;
      int bytesReceived = 0;
      final fileSink = file.openWrite();
      try {
        await response.stream.map((chunk) {
          bytesReceived += chunk.length;
          onProgress(bytesReceived / contentLength!);
          return chunk;
        }).pipe(fileSink);
      } finally {
        if(isDownloading(episodeNumber)){
          await fileSink.flush();
          await fileSink.close();
        }
      }
    } on http.ClientException {
      return;
    }

  }

  Future<void> saveEpisodeMetadata(String episodeNumber, String title, String dateTime, String imagePath, String audioPath) async {
    final prefs = await SharedPreferences.getInstance();

    List<String> downloads = prefs.getStringList('downloads') ?? [];
    downloads.add(episodeNumber);
    await prefs.setStringList('downloads', downloads);

      // Create a map for the episode data
    Map<String, String> episodeData = {
      'title': title,
      'dateTime': dateTime,
      'imagePath': imagePath,
      'audioPath': audioPath,
    };

    // Serialize the map to a JSON string
    String episodeJson = jsonEncode(episodeData);
    await prefs.setString('offline_ep_$episodeNumber', episodeJson);

  }

  void _showSnackBarMessage(BuildContext context, String message, MaterialColor color) {
    // You can move this method to the appropriate widget context or provider
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold),),
        duration: const Duration(seconds: 4),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.0),
        ),
      ),
    );
  }
}


class DownloadsEpisodeItem extends StatelessWidget {
  final String episodeNumber;
  final String title;
  final String dateTime;
  final String imagePath;
  final String audioPath;
  final VoidCallback onDelete;

  const DownloadsEpisodeItem({
    required this.episodeNumber,
    required this.title,
    required this.dateTime,
    required this.imagePath,
    required this.audioPath,
    required this.onDelete,
    super.key,
  });

  void _navigateToAudioPlayer(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AudioPlayerScreen(
          imageUrl: imagePath,
          title: title,
          dateTime: dateTime,
          mp3Url: audioPath,
        ),
      ),
    );
  }

  void _playAudio(BuildContext context) async {
    if(context.mounted){
      final audioPlayerProvider = Provider.of<AudioPlayerProvider>(context, listen: false);
      final audioPlayer = audioPlayerProvider.audioPlayer;
      try {
        final UriAudioSource audioSource;
        if (File(audioPath).existsSync() && File(imagePath).existsSync()) {
          audioSource = AudioSource.uri(
            Uri.file(audioPath),
            tag: MediaItem(
              id: episodeNumber,
              title: title,
              artUri: Uri.file(imagePath),
              displayTitle: title,
              displaySubtitle: dateTime,
              extras: {
                'mp3Url': audioPath,
              },
            ),
          );
        } else {
          audioSource = AudioSource.uri(
            Uri.parse(audioPath),
            tag: MediaItem(
              id: episodeNumber,
              title: title,
              artUri: Uri.parse(imagePath),
              displayTitle: title,
              displaySubtitle: dateTime,
              extras: {
                'mp3Url': audioPath,
              },           
            ),
          );
        }
        await audioPlayer.setAudioSource(audioSource);
        await audioPlayer.play();
      } catch (e) {
        if (context.mounted){
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Something went wrong: $e'),
              duration: const Duration(seconds: 5),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.0),
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> deleteEpisode(BuildContext context) async {

    final prefs = await SharedPreferences.getInstance();
    if(context.mounted){
      final provider = Provider.of<AudioPlayerProvider>(context, listen: false);
      provider.handleOfflineEpisodeDeletion(title, imagePath, audioPath);
    }

    // Remove metadata
    prefs.remove('offline_ep_$episodeNumber');
    final lastPlayedDataString = prefs.getString('lastPlayedData');
    if (lastPlayedDataString != null) {
      final lastPlayedData = LastPlayedData.fromJson(jsonDecode(lastPlayedDataString));
      var lastPlayedImageUrl = lastPlayedData.imageUrl;
      var lastPlayedMp3Url = lastPlayedData.mp3Url;
      if (lastPlayedImageUrl.startsWith('file://')) {
        lastPlayedImageUrl = lastPlayedImageUrl.replaceFirst('file://', '');
      }
      if (lastPlayedMp3Url.startsWith('file://')) {
        lastPlayedMp3Url = lastPlayedMp3Url.replaceFirst('file://', '');
      }
      if (lastPlayedData.title == title &&
          lastPlayedImageUrl == imagePath &&
          lastPlayedMp3Url == audioPath) {
        await prefs.remove('lastPlayedData');
      }
    }

    // Remove from downloads list
    List<String> downloads = prefs.getStringList('downloads') ?? [];
    downloads.remove(episodeNumber);
    prefs.setStringList('downloads', downloads);
    
    // Delete files
    await File(imagePath).delete();
    await File(audioPath).delete();

    // Remove the episode details from the DownloadProvider
    if(context.mounted){
      final provider = Provider.of<DownloadProvider>(context, listen: false);
      provider.deleteDownload(int.parse(episodeNumber));
    }

    // Notify parent to update the UI
    onDelete();

  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _navigateToAudioPlayer(context),
            child: ImageItem(
              imageLink: imagePath,
              height: 80,
              width: 80,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: GestureDetector(
              onTap: () => _navigateToAudioPlayer(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    dateTime,
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          Column(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 30,
                ),
                onPressed: () => _playAudio(context),
              ),
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () async {
                  await deleteEpisode(context);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}




class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  List<Map<String, dynamic>> downloadedEpisodes = [];

  @override
  void initState() {
    super.initState();
    fetchDownloadedEpisodes();
  }


  Future<void> fetchDownloadedEpisodes() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> downloads = prefs.getStringList('downloads') ?? [];

    List<Map<String, dynamic>> episodes = [];
    for (String episodeNumber in downloads) {
      // Get the JSON string from SharedPreferences
      String? episodeJson = prefs.getString('offline_ep_$episodeNumber');

      if (episodeJson != null) {
        // Deserialize the JSON string to a map
        Map<String, dynamic> episodeData = jsonDecode(episodeJson);

        episodes.add({
          'episodeNumber': episodeNumber,
          'title': episodeData['title'] ?? '',
          'dateTime': episodeData['dateTime'] ?? '',
          'imagePath': episodeData['imagePath'] ?? '',
          'audioPath': episodeData['audioPath'] ?? '',
        });
      }
    }

    setState(() {
      downloadedEpisodes = episodes;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 4, 0, 0),
      appBar: AppBar(
        title: const Text('Downloads', style: TextStyle(color: Colors.red)),
        backgroundColor: const Color.fromARGB(255, 20, 0, 0),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () {
              Navigator.of(context).pop(); // Return to the home page
            },
          ),
        ],
      ),
      body: downloadedEpisodes.isEmpty
          ? const Center(
              child: Text(
                'No downloaded episodes',
                style: TextStyle(color: Colors.white),
              ),
            )
          : ListView.builder(
              itemCount: downloadedEpisodes.length,
              itemBuilder: (context, index) {
                var episode = downloadedEpisodes[index];
                return DownloadsEpisodeItem(
                  episodeNumber: episode['episodeNumber'],
                  title: episode['title'],
                  dateTime: episode['dateTime'],
                  imagePath: episode['imagePath'],
                  audioPath: episode['audioPath'],
                  onDelete: fetchDownloadedEpisodes,
                );
              },
            ),
    );
  }
}
