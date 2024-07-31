import 'dart:convert';
import 'package:html/dom.dart' as html;
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:podcast_darknet_diaries/audio_player.dart';
import 'package:podcast_darknet_diaries/downloads.dart';
import 'package:podcast_darknet_diaries/episode_search_delegate.dart';
import 'package:podcast_darknet_diaries/favourites.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';



Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.ryanheise.bg_demo.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );
  runApp(ChangeNotifierProvider(
      create: (context) => FavouritesProvider()..loadFavourites(),
      child: const MyApp(),
    ),);
}


class Episode {
  final String imageUrl;
  final String title;
  final String dateTime;
  final String content;
  final String mp3Url;
  Episode({required this.imageUrl, required this.title, required this.dateTime, required this.content, required this.mp3Url});

  // Method to convert Episode to JSON
  Map<String, dynamic> toJson() {
    return {
      'imageUrl': imageUrl,
      'title': title,
      'dateTime': dateTime,
      'content': content,
      'mp3Url': mp3Url,
    };
  }

  // Method to create Episode from JSON
  factory Episode.fromJson(Map<String, dynamic> json) {
    return Episode(
      imageUrl: json['imageUrl'],
      title: json['title'],
      dateTime: json['dateTime'],
      content: json['content'],
      mp3Url: json['mp3Url'],
    );
  }

}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  String? _errorMessage; // State variable to hold the error message

  String? extractMp3Link(String scriptContent) {
    RegExp regExp = RegExp(r'"mp3":\s*"([^"]+)"');
    Match? match = regExp.firstMatch(scriptContent);
    if (match != null) {
      return match.group(1);
    } else {
      return null;
    }
  }

  Future<html.Document?> fetchEpisodeDetails(String url) async {
    try {
      var response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        var document = html_parser.parse(utf8.decode(response.bodyBytes));
        return document;
      } else {
        setState(() {
          _errorMessage = 'Request failed with status: ${response.statusCode}.';
        });
        return null;
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to fetch episode details: $e';
      });
      return null;
    }
  }

  String? getTitle(html.Document document) {
    var heroSection = document.querySelector('.hero.hero--single');
    if (heroSection != null) {
      var episodeTitleElement = heroSection.querySelector('h1');
      var episodeTitle = episodeTitleElement?.text ?? 'N/A';
      return episodeTitle;
    } else {
      return null;
    }
  }

  String? getDateTime(html.Document document) {
    var heroSection = document.querySelector('.hero.hero--single');
    if (heroSection != null) {
      var episodeDateElement = heroSection.querySelector('p');
      var episodeDateAndDuration =
          episodeDateElement?.text.split('|').map((e) => e.trim()).toList() ?? [];
      var episodeDate = episodeDateAndDuration.isNotEmpty
          ? episodeDateAndDuration[0]
          : 'N/A';
      var episodeDuration = episodeDateAndDuration.length > 1
          ? episodeDateAndDuration[1]
          : 'N/A';
      return "$episodeDate $episodeDuration";
    } else {
      return null;
    }
  }

  String? getBackgroundImageUrl(html.Document document) {
    var heroSection = document.querySelector('.hero.hero--single');
    if (heroSection != null) {
      var backgroundImageElement = heroSection.querySelector('.hero__image');
      var backgroundImageUrl =
          'https://darknetdiaries.com${backgroundImageElement?.attributes['style']?.split('url(')[1].split(')')[0] ?? 'N/A'}';
      return backgroundImageUrl;
    } else {
      return null;
    }
  }

  String? getMp3Url(html.Document document) {
    var mainContent = document.querySelector('.single-post');
    if (mainContent != null) {
      var scriptElements = mainContent.querySelectorAll('script');
      for (var script in scriptElements) {
        if (script.text.contains('window.playerConfiguration')) {
          // Extract and print the mp3 link from the script content
          String? mp3Link = extractMp3Link(script.text);
          if (mp3Link != null) {
            return mp3Link;
          } else {
            return null;
          }
        }
      }
    } else {
      return null;
    }
    return null;
  }

  String? getEpisodeContent(html.Document document) {
    var mainContent = document.querySelector('.single-post');
    if (mainContent != null) {
      // Remove script sections containing 'window.playerConfiguration'
      var scriptElements = mainContent.querySelectorAll('script');
      for (var script in scriptElements) {
        if (script.text.contains('window.playerConfiguration')) {
          script.remove();
        }
      }

      // Buffer to collect the content
      StringBuffer contentBuffer = StringBuffer();

      // Iterate through each node and process text and links
      for (var node in mainContent.nodes) {
        if (node is html.Element) {
          // Break on 'Transcript' section
          if (node.localName == 'h3' && node.text.contains('Transcript')) {
            break;
          }

          // Skip 'Full Transcript' section
          if (node.localName == 'p' && node.text.contains('Full Transcript')) {
            continue;
          }

          // Process other elements
          contentBuffer.writeln(processElementContent(node));
        }
      }

      return contentBuffer.toString().trim();
    } else {
      return 'Main content not found.';
    }
  }

  // Helper function to process element content and preserve links
  String processElementContent(html.Element element) {
    StringBuffer contentBuffer = StringBuffer();
    for (var child in element.nodes) {
      if (child is html.Text) {
        contentBuffer.write(child.text.trim());
      } else if (child is html.Element) {
        if (child.localName == 'a') {
          contentBuffer.write('[${child.text.trim()}](${child.attributes['href']})');
        } else if (child.localName == 'h3') {
          contentBuffer.writeln('\n${child.text.trim()}\n');
        } else if (child.localName == 'ul') {
          contentBuffer.writeln(processListContent(child));
        } else if (child.localName == 'li') {
          contentBuffer.writeln('- ${processElementContent(child)}');
        } else {
          contentBuffer.write(child.text.trim());
        }
      }
    }
    return contentBuffer.toString().trim();
  }

  // Helper function to process list content
  String processListContent(html.Element element) {
    StringBuffer listBuffer = StringBuffer();
    for (var child in element.children) {
      if (child.localName == 'li') {
        listBuffer.writeln('- ${processElementContent(child)}');
      }
    }
    return listBuffer.toString().trim();
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

  Future<int?> lastEpisodeNumber() async {
    try {
      var url = Uri.parse('https://darknetdiaries.com/episode/');
      var response = await http.get(url);
      if (response.statusCode == 200) {
        var document = html_parser.parse(response.body);
        var episodeTitles = document.querySelectorAll('.post__title');
        if (episodeTitles.isNotEmpty) {
          return extractEpisodeNumber(episodeTitles[0].text);
        } else {
          setState(() {
            _errorMessage = 'No episode titles found.';
          });
          return null;
        }
      } else {
        setState(() {
          _errorMessage = 'Request failed with status: ${response.statusCode}.';
        });
        return null;
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to fetch episodes';
      });
      return null;
    }
  }

  Future<List<Episode>>? _episodeFuture;
  late List<Episode> episodes;
  bool _isNewestFirst = true;

  @override
  void initState() {
    super.initState();
    _episodeFuture = _initializeEpisodes();
  }

  void reFetch() {
    setState(() {
      Provider.of<FavouritesProvider>(context, listen: false).setErrorMessage(null);
      _errorMessage = null; // Reset the error message
      _episodeFuture = _initializeEpisodes();
    });
  }

  Future<List<Episode>> _initializeEpisodes() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      int? lastStoredEpisode = prefs.getInt('lastEpisode');
      int? latestEpisode = await lastEpisodeNumber();

      if (latestEpisode != null) {
        if (lastStoredEpisode == null || lastStoredEpisode < latestEpisode) {
          for (int i = latestEpisode; i > (lastStoredEpisode ?? 0); i--) {
            String episodeUrl = 'https://darknetdiaries.com/episode/$i/';
            html.Document? document = await fetchEpisodeDetails(episodeUrl);
            if (document != null) {
              String mp3Url = getMp3Url(document) ?? '';
              String imageUrl = getBackgroundImageUrl(document) ?? '';
              String title = getTitle(document) ?? '';
              String dateTime = getDateTime(document) ?? '';
              String content = getEpisodeContent(document) ?? '';
              Episode episode = Episode(
                imageUrl: imageUrl,
                title: title,
                dateTime: dateTime,
                content: content,
                mp3Url: mp3Url,
              );

              await _cacheEpisode(i, episode);
            }
          }
          await prefs.setInt('lastEpisode', latestEpisode);
        }
        // List<Episode> episodes = await _getCachedEpisodes();
        episodes = await _getCachedEpisodes();
        return _isNewestFirst ? episodes.reversed.toList() : episodes;
      }

      return [];
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to initialize episodes';
      });
      return [];
    }
  }

  Future<void> _cacheEpisode(int episodeNumber, Episode episode) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String episodeJson = jsonEncode(episode.toJson());
    await prefs.setString('episode_$episodeNumber', episodeJson);
  }

  Future<List<Episode>> _getCachedEpisodes() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<Episode> cachedEpisodes = [];

    int? lastStoredEpisode = prefs.getInt('lastEpisode');
    if (lastStoredEpisode != null) {
      for (int i = 1; i <= lastStoredEpisode; i++) {
        String? episodeJson = prefs.getString('episode_$i');
        if (episodeJson != null) {
          Episode episode = Episode.fromJson(jsonDecode(episodeJson));
          cachedEpisodes.add(episode);
        }
      }
    }

    return cachedEpisodes;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 4, 0, 0),
      appBar: AppBar(
        title: const Text(
          'Darknet Diaries',
          style: TextStyle(color: Colors.red),
        ),
        backgroundColor: const Color.fromARGB(255, 7, 0, 0),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.grey), // Set drawer icon color to gray
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.grey),
            onPressed: reFetch,
          ),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.grey),
            onPressed: () {
              showSearch(
                context: context,
                delegate: EpisodeSearchDelegate(episodes),
              );
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: Container(
          color: const Color.fromARGB(255, 0, 0, 0), 
          child: Column(
            children: <Widget>[
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: <Widget>[
                    const DrawerHeader(
                      decoration: BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage('assets/img/hero10.jpg'),
                          fit: BoxFit.cover,
                        ),
                      ),
                      child: SizedBox(),
                    ),
                    ListTile(
                      leading: const Icon(Icons.download, color: Colors.white), 
                      title: const Text(
                        'Downloads',
                        style: TextStyle(color: Colors.white), 
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const DownloadsPage()),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.favorite, color: Colors.white), 
                      title: const Text(
                        'Favourites',
                        style: TextStyle(color: Colors.white), 
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const FavouritesPage()),
                        );
                      },
                    ),
                    const Divider(color: Colors.white), // Add a divider for better separation
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _isNewestFirst ? 'Newest First' : 'Oldest First',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18.0, // Increase the font size
                              ),
                            ),
                          ),
                          Switch(
                            value: _isNewestFirst,
                            onChanged: (value) {
                              setState(() {
                                _isNewestFirst = value;
                                _episodeFuture = _initializeEpisodes(); // Re-fetch episodes with the new sorting order
                              });
                            },
                            activeColor: Colors.red, // Color of the switch thumb when it's on
                            activeTrackColor: Colors.red[200], // Color of the track when the switch is on
                            inactiveThumbColor: Colors.grey, // Color of the switch thumb when it's off
                            inactiveTrackColor: Colors.grey[600], // Color of the track when the switch is off
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // const Divider(color: Colors.white),
              ListTile(
                leading: const Icon(Icons.info, color: Colors.white), 
                title: const Text(
                  'About',
                  style: TextStyle(color: Colors.white), 
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AboutPage()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      body: FutureBuilder<List<Episode>>(
        future: _episodeFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.red,),
            );
          } else if (snapshot.hasError || _errorMessage != null) {
            Provider.of<FavouritesProvider>(context, listen: false).setErrorMessage('${_errorMessage ?? snapshot.error}');
            return Center(
              child: Text(
                'Error: ${_errorMessage ?? snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                'No episodes available.',
                style: TextStyle(color: Colors.white),
              ),
            );
          } else {
            List<Episode> episodes = snapshot.data!;
            return Consumer<FavouritesProvider>(
              builder: (context, favouritesProvider, child) {
                return ListView.builder(
                  itemCount: episodes.length,
                  itemBuilder: (context, index) {
                    Episode episode = episodes[index];

                    int? episodeNumber = extractEpisodeNumber(episode.title);
                    bool isFavourite = episodeNumber != null &&
                        favouritesProvider.favourites.contains(episodeNumber);

                    return EpisodeItem(
                      imageUrl: episode.imageUrl,
                      title: episode.title,
                      dateTime: episode.dateTime,
                      content: episode.content,
                      mp3Url: episode.mp3Url,
                      isFavourite: isFavourite,
                      onFavouriteToggle: () {
                        if (episodeNumber != null) {
                          favouritesProvider.toggleFavourite(episodeNumber);
                        }
                      },
                    );
                  },
                );
              },
            );
          }
        },
      ),
    );
  }
}


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
            Text(
              widget.content,
              style: const TextStyle(fontSize: 18, color: Colors.white),
            ),
          ],
        ),
      ),
    );
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
}


class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 4, 0, 0),
      appBar: AppBar(
        title: const Text('About', style: TextStyle(color: Colors.red)),
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
      body: const Center(
        child: Text('About Page Content'),
      ),
    );
  }
}
