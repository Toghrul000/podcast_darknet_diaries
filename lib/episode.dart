import 'package:http/http.dart' as http;
import 'package:podcast_darknet_diaries/audio_player.dart';
import 'package:podcast_darknet_diaries/favourites.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';




class EpisodeItem extends StatefulWidget {
  final String imageUrl;
  final String title;
  final String dateTime;
  final String content;
  final String mp3Url;
  final bool isFavourite;
  final VoidCallback onFavouriteToggle;

  const EpisodeItem({
    required this.imageUrl,
    required this.title,
    required this.dateTime,
    required this.content,
    required this.mp3Url,
    required this.isFavourite,
    required this.onFavouriteToggle,
    super.key,
  });

  @override
  State<EpisodeItem> createState() => _EpisodeItemState();
}

class _EpisodeItemState extends State<EpisodeItem> {
  double _downloadProgress = 0.0;
  bool _isDownloading = false;
  String? _imagePath;
  String? _audioPath;


  int? extractEpisodeNumber(String episodeString) {
    RegExp regExp = RegExp(r'EP (\d+):');
    Match? match = regExp.firstMatch(episodeString);
    if (match != null) {
      String episodeNumberStr = match.group(1)!;
      int episodeNumber = int.parse(episodeNumberStr);
      return episodeNumber;
    } else {
      return null;
    }
  }


  Future<void> _downloadEpisode() async {
    int? episodeNumber = extractEpisodeNumber(widget.title);
    if (episodeNumber != null){
      final prefs = await SharedPreferences.getInstance();
      List<String> downloads = prefs.getStringList('downloads') ?? [];
      if (!downloads.contains(episodeNumber.toString())) {
        setState(() {
          _isDownloading = true;
        });

        await _saveEpisodeFilesWithProgress(episodeNumber, widget.imageUrl, widget.mp3Url, (progress) {
          setState(() {
            _downloadProgress = progress;
          });
        });

        if (_imagePath != null && _audioPath != null) {
          await saveEpisodeMetadata(episodeNumber.toString(), widget.title, widget.dateTime, _imagePath!, _audioPath!);
        }
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0.0;
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Already in Downloads!'),
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

  Future<void> _saveEpisodeFilesWithProgress(int episodeNumber, String imageUrl, String audioUrl, Function(double) onProgress) async {
    final directory = await getApplicationDocumentsDirectory();

    // Create directories if they don't exist
    final imgDir = Directory('${directory.path}/assets/img');
    if (!await imgDir.exists()) {
      await imgDir.create(recursive: true);
    }

    final audioDir = Directory('${directory.path}/assets/audio');
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }

    // Save image with progress
    final imagePath = '${directory.path}/assets/img/episode_$episodeNumber.jpg';
    final imageFile = File(imagePath);
    await _downloadFile(imageUrl, imageFile);

    // Save audio with progress
    final audioPath = '${directory.path}/assets/audio/episode_$episodeNumber.mp3';
    final audioFile = File(audioPath);
    await _downloadFileWithProgress(audioUrl, audioFile, onProgress);

    setState(() {
      _imagePath = imagePath;
      _audioPath = audioPath;
    });
  }

    Future<void> _downloadFile(String url, File file) async {
      final response = await http.Client().send(http.Request('GET', Uri.parse(url)));
      final fileSink = file.openWrite();

      await response.stream.pipe(fileSink);

      await fileSink.flush();
      await fileSink.close();
    }


  Future<void> _downloadFileWithProgress(String url, File file, Function(double) onProgress) async {
    final response = await http.Client().send(http.Request('GET', Uri.parse(url)));
    final contentLength = response.contentLength;
    int bytesReceived = 0;

    final fileSink = file.openWrite();

    await response.stream.map((chunk) {
      bytesReceived += chunk.length;
      onProgress(bytesReceived / contentLength!);
      return chunk;
    }).pipe(fileSink);

    await fileSink.flush();
    await fileSink.close();
  }

  Future<void> saveEpisodeMetadata(String episodeNumber, String title, String dateTime, String imagePath, String audioPath) async {
    final prefs = await SharedPreferences.getInstance();
    
    prefs.setString('offline_ep_${episodeNumber}_title', title);
    prefs.setString('offline_ep_${episodeNumber}_dateTime', dateTime);
    prefs.setString('offline_ep_${episodeNumber}_imagePath', imagePath);
    prefs.setString('offline_ep_${episodeNumber}_audioPath', audioPath);
    
    List<String> downloads = prefs.getStringList('downloads') ?? [];
    if (!downloads.contains(episodeNumber)) {
      downloads.add(episodeNumber);
      prefs.setStringList('downloads', downloads);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EpisodeScreen(
                    imageUrl: widget.imageUrl,
                    title: widget.title,
                    dateTime: widget.dateTime,
                    content: widget.content,
                    mp3Url: widget.mp3Url,
                  ),
                ),
              );
            },
            child: CachedNetworkImage(
              imageUrl: widget.imageUrl,
              placeholder: (context, url) => const CircularProgressIndicator(color: Colors.red,),
              errorWidget: (context, url, error) => const Icon(Icons.error),
              height: 105,
              width: 105,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EpisodeScreen(
                      imageUrl: widget.imageUrl,
                      title: widget.title,
                      dateTime: widget.dateTime,
                      content: widget.content,
                      mp3Url: widget.mp3Url,
                    ),
                  ),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.dateTime,
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.content,
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          Column(
            children: [
              IconButton(
                icon: Icon(
                  widget.isFavourite ? Icons.favorite : Icons.favorite_border,
                  color: Colors.white,
                ),
                onPressed: widget.onFavouriteToggle,
              ),
              IconButton(
                icon: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AudioPlayerScreen(
                        imageUrl: widget.imageUrl,
                        title: widget.title,
                        dateTime: widget.dateTime,
                        mp3Url: widget.mp3Url,
                      ),
                    ),
                  );
                },
              ),
              _isDownloading
              ? Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(value: _downloadProgress, color: Colors.red,),
                    Positioned(
                      child: Text(
                        '${(_downloadProgress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                )
          : IconButton(
              icon: const Icon(Icons.download, color: Colors.white,),
              onPressed: _downloadEpisode,
            ),
            ],
          ),
        ],
      ),
    );
  }
}



class EpisodeScreen extends StatefulWidget {
  final String imageUrl;
  final String title;
  final String dateTime;
  final String content;
  final String mp3Url;

  const EpisodeScreen({
    required this.imageUrl,
    required this.title,
    required this.dateTime,
    required this.content,
    required this.mp3Url,
    super.key,
  });

  @override
  _EpisodeScreenState createState() => _EpisodeScreenState();
}

class _EpisodeScreenState extends State<EpisodeScreen> {
  bool isFavourite = false;
  int? episodeNumber;
  double _downloadProgress = 0.0;
  bool _isDownloading = false;
  String? _imagePath;
  String? _audioPath;

  @override
  void initState() {
    super.initState();
    episodeNumber = extractEpisodeNumber(widget.title);
    if (episodeNumber != null) {
      isFavourite = Provider.of<FavouritesProvider>(context, listen: false).favourites.contains(episodeNumber);
    }
  }

  void toggleFavourite() {
    if (episodeNumber != null) {
      Provider.of<FavouritesProvider>(context, listen: false).toggleFavourite(episodeNumber!);
      setState(() {
        isFavourite = !isFavourite;
      });
    }
  }

  Future<void> _downloadEpisode() async {
    if (episodeNumber != null) {
      final prefs = await SharedPreferences.getInstance();
      List<String> downloads = prefs.getStringList('downloads') ?? [];
      if (!downloads.contains(episodeNumber.toString())) {
        setState(() {
          _isDownloading = true;
        });

        await _saveEpisodeFilesWithProgress(episodeNumber!, widget.imageUrl, widget.mp3Url, (progress) {
          setState(() {
            _downloadProgress = progress;
          });
        });

        if (_imagePath != null && _audioPath != null) {
          await saveEpisodeMetadata(episodeNumber!.toString(), widget.title, widget.dateTime, _imagePath!, _audioPath!);
        }
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0.0;
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Already in Downloads!'),
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

  Future<void> _saveEpisodeFilesWithProgress(int episodeNumber, String imageUrl, String audioUrl, Function(double) onProgress) async {
    final directory = await getApplicationDocumentsDirectory();

    // Create directories if they don't exist
    final imgDir = Directory('${directory.path}/assets/img');
    if (!await imgDir.exists()) {
      await imgDir.create(recursive: true);
    }

    final audioDir = Directory('${directory.path}/assets/audio');
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }

    // Save image with progress
    final imagePath = '${directory.path}/assets/img/episode_$episodeNumber.jpg';
    final imageFile = File(imagePath);
    await _downloadFile(imageUrl, imageFile);

    // Save audio with progress
    final audioPath = '${directory.path}/assets/audio/episode_$episodeNumber.mp3';
    final audioFile = File(audioPath);
    await _downloadFileWithProgress(audioUrl, audioFile, onProgress);

    setState(() {
      _imagePath = imagePath;
      _audioPath = audioPath;
    });
  }

  Future<void> _downloadFile(String url, File file) async {
    final response = await http.Client().send(http.Request('GET', Uri.parse(url)));
    final fileSink = file.openWrite();

    await response.stream.pipe(fileSink);

    await fileSink.flush();
    await fileSink.close();
  }

  Future<void> _downloadFileWithProgress(String url, File file, Function(double) onProgress) async {
    final response = await http.Client().send(http.Request('GET', Uri.parse(url)));
    final contentLength = response.contentLength;
    int bytesReceived = 0;

    final fileSink = file.openWrite();

    await response.stream.map((chunk) {
      bytesReceived += chunk.length;
      onProgress(bytesReceived / contentLength!);
      return chunk;
    }).pipe(fileSink);

    await fileSink.flush();
    await fileSink.close();
  }

  Future<void> saveEpisodeMetadata(String episodeNumber, String title, String dateTime, String imagePath, String audioPath) async {
    final prefs = await SharedPreferences.getInstance();
    
    prefs.setString('offline_ep_${episodeNumber}_title', title);
    prefs.setString('offline_ep_${episodeNumber}_dateTime', dateTime);
    prefs.setString('offline_ep_${episodeNumber}_imagePath', imagePath);
    prefs.setString('offline_ep_${episodeNumber}_audioPath', audioPath);
    
    List<String> downloads = prefs.getStringList('downloads') ?? [];
    if (!downloads.contains(episodeNumber)) {
      downloads.add(episodeNumber);
      prefs.setStringList('downloads', downloads);
    }
  }

  int? extractEpisodeNumber(String episodeString) {
    RegExp regExp = RegExp(r'EP (\d+):');
    Match? match = regExp.firstMatch(episodeString);
    if (match != null) {
      String episodeNumberStr = match.group(1)!;
      int episodeNumber = int.parse(episodeNumberStr);
      return episodeNumber;
    } else {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Set background color to black
      appBar: AppBar(
        backgroundColor: Colors.black, // Set AppBar background color to black
        leading: IconButton(
          icon: const Icon(Icons.home, color: Colors.white), // Home icon color to white
          onPressed: () {
            Navigator.popUntil(context, (route) => route.isFirst);
          },
        ),
        title: Text(
          widget.title,
          style: const TextStyle(color: Colors.white), // AppBar title color to white
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              widget.dateTime,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(
                      isFavourite ? Icons.favorite : Icons.favorite_border,
                      size: 50,
                      color: Colors.white,
                    ),
                    onPressed: toggleFavourite,
                  ),
                  IconButton(
                    icon: const Icon(Icons.play_arrow_rounded, size: 64, color: Colors.white), // Play button color to white
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AudioPlayerScreen(
                            imageUrl: widget.imageUrl,
                            title: widget.title,
                            dateTime: widget.dateTime,
                            mp3Url: widget.mp3Url,
                          ),
                        ),
                      );
                    },
                  ),
                  _isDownloading
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(value: _downloadProgress, color: Colors.red),
                          Positioned(
                            child: Text(
                              '${(_downloadProgress * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      )
                    : IconButton(
                        icon: const Icon(Icons.download, size: 50, color: Colors.white),
                        onPressed: _downloadEpisode,
                      ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            CachedNetworkImage(
              placeholder: (context, url) => const CircularProgressIndicator(color: Colors.red),
              errorWidget: (context, url, error) => const Icon(Icons.error),
              imageUrl: widget.imageUrl,
              fit: BoxFit.cover,
            ),
            const SizedBox(height: 16),
            // Text(
            //   widget.content,
            //   style: const TextStyle(fontSize: 18, color: Colors.white),
            // ),
            MarkdownBody(
              data: widget.content,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(fontSize: 18, color: Colors.white),
                h1: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                h2: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                h3: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                h4: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                h5: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                h6: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                listBullet: const TextStyle(fontSize: 18, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

