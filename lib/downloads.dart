import 'package:podcast_darknet_diaries/audio_player.dart';
import 'package:podcast_darknet_diaries/image_item.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'dart:io';

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
                onPressed: () => _navigateToAudioPlayer(context),
              ),
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  // Remove metadata
                  prefs.remove('offline_ep_${episodeNumber}_title');
                  prefs.remove('offline_ep_${episodeNumber}_dateTime');
                  prefs.remove('offline_ep_${episodeNumber}_imagePath');
                  prefs.remove('offline_ep_${episodeNumber}_audioPath');
                  
                  // Remove from downloads list
                  List<String> downloads = prefs.getStringList('downloads') ?? [];
                  downloads.remove(episodeNumber);
                  prefs.setStringList('downloads', downloads);
                  
                  // Delete files
                  File(imagePath).delete();
                  File(audioPath).delete();

                  // Notify parent to update the UI
                  onDelete();
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
  _DownloadsPageState createState() => _DownloadsPageState();
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
      String title = prefs.getString('offline_ep_${episodeNumber}_title') ?? '';
      String dateTime = prefs.getString('offline_ep_${episodeNumber}_dateTime') ?? '';
      String imagePath = prefs.getString('offline_ep_${episodeNumber}_imagePath') ?? '';
      String audioPath = prefs.getString('offline_ep_${episodeNumber}_audioPath') ?? '';

      episodes.add({
        'episodeNumber': episodeNumber,
        'title': title,
        'dateTime': dateTime,
        'imagePath': imagePath,
        'audioPath': audioPath,
      });
    }

    setState(() {
      downloadedEpisodes = episodes;
    });
  }

  void handleDelete() {
    fetchDownloadedEpisodes();
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
                  onDelete: handleDelete,
                );
              },
            ),
    );
  }
}
