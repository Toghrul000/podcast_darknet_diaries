import 'dart:async';
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
import 'package:url_launcher/url_launcher.dart';



class DownloadProvider with ChangeNotifier {
  final Map<int, bool> _downloading = {};
  final Map<int, double> _downloadProgress = {};
  final Map<int, String> _imagePaths = {};
  final Map<int, String> _audioPaths = {};
  final Map<int, Completer<void>> _downloadCompleters = {};

  bool isDownloading(int episodeNumber) => _downloading[episodeNumber] ?? false;
  double getDownloadProgress(int episodeNumber) => _downloadProgress[episodeNumber] ?? 0.0;
  String? getImagePath(int episodeNumber) => _imagePaths[episodeNumber];
  String? getAudioPath(int episodeNumber) => _audioPaths[episodeNumber];

  void startDownload(int episodeNumber) {
    if (!_downloading.containsKey(episodeNumber) || !_downloading[episodeNumber]!) {
      _downloading[episodeNumber] = true;
      _downloadCompleters[episodeNumber] = Completer<void>();
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
      notifyListeners();
    }
  }

  void cancelDownload(int episodeNumber) async {
    if (_downloading[episodeNumber] ?? false) {
      _downloading[episodeNumber] = false;
      _downloadProgress[episodeNumber] = 0.0;
      await _deleteFiles(episodeNumber);
      _resetMetadata(episodeNumber);
      _downloadCompleters[episodeNumber]?.complete();
      _downloadCompleters.remove(episodeNumber);
      notifyListeners();
    }
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
  }

  void _resetMetadata(int episodeNumber) {
    _imagePaths.remove(episodeNumber);
    _audioPaths.remove(episodeNumber);
    // Reset metadata in shared preferences
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('offline_ep_${episodeNumber}_title');
      prefs.remove('offline_ep_${episodeNumber}_dateTime');
      prefs.remove('offline_ep_${episodeNumber}_imagePath');
      prefs.remove('offline_ep_${episodeNumber}_audioPath');
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
      try {
        if(context.mounted){
          startDownload(episodeNumber);
          await _saveEpisodeFilesWithProgress(context, episodeNumber, imageUrl, mp3Url, (progress) {
            updateDownloadProgress(episodeNumber, progress);
          });
          if (getImagePath(episodeNumber) != null && getAudioPath(episodeNumber) != null) {
            await saveEpisodeMetadata(episodeNumber.toString(), title, dateTime, getImagePath(episodeNumber)!, getAudioPath(episodeNumber)!);
          }
          completeDownload(episodeNumber, getImagePath(episodeNumber)!, getAudioPath(episodeNumber)!);
        }
      } catch (e) {
        if (context.mounted) {
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
    } else {
      if (context.mounted) {
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

  Future<void> _saveEpisodeFilesWithProgress(BuildContext context, int episodeNumber, String imageUrl, String audioUrl, Function(double) onProgress) async {
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
    try {
      if(context.mounted) {
        // Save image with progress
        final imagePath = '${directory.path}/assets/img/episode_$episodeNumber.jpg';
        final imageFile = File(imagePath);
        await _downloadFile(context, episodeNumber, imageUrl, imageFile);
        updateImagePath(episodeNumber, imagePath);
      }

      if(context.mounted) {
        // Save audio with progress
        final audioPath = '${directory.path}/assets/audio/episode_$episodeNumber.mp3';
        final audioFile = File(audioPath);
        await _downloadFileWithProgress(context, episodeNumber, audioUrl, audioFile, onProgress);
        updateAudioPath(episodeNumber, audioPath);
      }
    } catch (e) {
      if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$e'),
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

  Future<void> _downloadFile(BuildContext context, int episodeNumber, String url, File file) async {
    final response = await http.Client().send(http.Request('GET', Uri.parse(url)));
    final fileSink = file.openWrite();
    try {
      await response.stream.listen((chunk) {
        if (!isDownloading(episodeNumber)) {
          throw Exception('Download cancelled');
        }
        fileSink.add(chunk);
      }).asFuture();
    } 
    // catch (e) {
    //   if (context.mounted) {
    //     ScaffoldMessenger.of(context).showSnackBar(
    //       SnackBar(
    //         content: Text('$e'),
    //         duration: const Duration(seconds: 5),
    //         backgroundColor: Colors.red,
    //         behavior: SnackBarBehavior.floating,
    //         shape: RoundedRectangleBorder(
    //           borderRadius: BorderRadius.circular(10.0),
    //         ),
    //       ),
    //     );
    //   }
    // } 
    finally {
      await fileSink.flush();
      await fileSink.close();
    }
  }

  Future<void> _downloadFileWithProgress(BuildContext context, int episodeNumber, String url, File file, Function(double) onProgress) async {
    final response = await http.Client().send(http.Request('GET', Uri.parse(url)));
    final contentLength = response.contentLength;
    int bytesReceived = 0;
    final fileSink = file.openWrite();
    try {
      await response.stream.map((chunk) {
        if (!isDownloading(episodeNumber)) {
          throw Exception('Download cancelled');
        }
        bytesReceived += chunk.length;
        onProgress(bytesReceived / contentLength!);
        return chunk;
      }).pipe(fileSink);
    } 
    // catch (e) {
    //   if (context.mounted) {
    //     ScaffoldMessenger.of(context).showSnackBar(
    //       SnackBar(
    //         content: Text('$e'),
    //         duration: const Duration(seconds: 5),
    //         backgroundColor: Colors.red,
    //         behavior: SnackBarBehavior.floating,
    //         shape: RoundedRectangleBorder(
    //           borderRadius: BorderRadius.circular(10.0),
    //         ),
    //       ),
    //     );
    //   }
    // } 
    finally {
      await fileSink.flush();
      await fileSink.close();
    }
  }

  Future<void> saveEpisodeMetadata(String episodeNumber, String title, String dateTime, String imagePath, String audioPath) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> downloads = prefs.getStringList('downloads') ?? [];
    downloads.add(episodeNumber);
    await prefs.setStringList('downloads', downloads);
    await prefs.setString('offline_ep_${episodeNumber}_title', title);
    await prefs.setString('offline_ep_${episodeNumber}_dateTime', dateTime);
    await prefs.setString('offline_ep_${episodeNumber}_imagePath', imagePath);
    await prefs.setString('offline_ep_${episodeNumber}_audioPath', audioPath);
  }
}






class EpisodeItem extends StatelessWidget {
  final String imageUrl;
  final String title;
  final String dateTime;
  final String content;
  final int episodeNumber;
  final String mp3Url;
  final bool isFavourite;
  final VoidCallback onFavouriteToggle;

  const EpisodeItem({
    required this.imageUrl,
    required this.title,
    required this.dateTime,
    required this.content,
    required this.mp3Url,
    required this.episodeNumber,
    required this.isFavourite,
    required this.onFavouriteToggle,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final downloadProvider = Provider.of<DownloadProvider>(context);
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
                    episodeNumber: episodeNumber,
                    imageUrl: imageUrl,
                    title: title,
                    dateTime: dateTime,
                    content: content,
                    mp3Url: mp3Url,
                  ),
                ),
              );
            },
            child: CachedNetworkImage(
              imageUrl: imageUrl,
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
                      imageUrl: imageUrl,
                      title: title,
                      dateTime: dateTime,
                      content: content,
                      mp3Url: mp3Url,
                      episodeNumber: episodeNumber,
                    ),
                  ),
                );
              },
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
                  const SizedBox(height: 8),
                  Text(
                    content,
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
                  isFavourite ? Icons.favorite : Icons.favorite_border,
                  color: Colors.white,
                ),
                onPressed: onFavouriteToggle,
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
                        imageUrl: imageUrl,
                        title: title,
                        dateTime: dateTime,
                        mp3Url: mp3Url,
                      ),
                    ),
                  );
                },
              ),
              downloadProvider.isDownloading(episodeNumber)
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: downloadProvider.getDownloadProgress(episodeNumber),
                        color: Colors.red,
                      ),
                      Positioned(
                        child: Text(
                          '${(downloadProvider.getDownloadProgress(episodeNumber) * 100).toStringAsFixed(0)}%',
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
                    icon: const Icon(Icons.download, color: Colors.white),
                    onPressed: () {
                      downloadProvider.downloadEpisode(context, episodeNumber, title, dateTime, imageUrl, mp3Url);
                    },
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
  final int episodeNumber;

  const EpisodeScreen({
    required this.imageUrl,
    required this.title,
    required this.dateTime,
    required this.content,
    required this.mp3Url,
    required this.episodeNumber,
    super.key,
  });

  @override
  State<EpisodeScreen> createState() => _EpisodeScreenState();
}

class _EpisodeScreenState extends State<EpisodeScreen> {
  bool isFavourite = false;

  @override
  void initState() {
    super.initState();
    isFavourite = Provider.of<FavouritesProvider>(context, listen: false).favourites.contains(widget.episodeNumber);
  }

  void toggleFavourite() {
    Provider.of<FavouritesProvider>(context, listen: false).toggleFavourite(widget.episodeNumber);
    setState(() {
      isFavourite = !isFavourite;
    });
  }

  @override
  Widget build(BuildContext context) {
    final downloadProvider = Provider.of<DownloadProvider>(context);
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
                  downloadProvider.isDownloading(widget.episodeNumber)
                    ? 
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: downloadProvider.getDownloadProgress(widget.episodeNumber),
                              color: Colors.red,
                            ),
                            Positioned(
                              child: Text(
                                '${(downloadProvider.getDownloadProgress(widget.episodeNumber) * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 50, color: Colors.white),
                          onPressed: () => downloadProvider.cancelDownload(widget.episodeNumber),
                        ),
                      ],
                    )
                    : IconButton(
                        icon: const Icon(Icons.download, size: 50, color: Colors.white),
                        onPressed: () {
                          downloadProvider.downloadEpisode(context, widget.episodeNumber, widget.title, widget.dateTime, widget.imageUrl, widget.mp3Url);
                        },
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
              onTapLink: (text, url, title) {
                  launchUrl(Uri.parse(url!));
              },
            ),
          ],
        ),
      ),
    );
  }
}

