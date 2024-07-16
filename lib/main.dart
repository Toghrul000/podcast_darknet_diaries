import 'dart:convert';
import 'package:html/dom.dart' as html;
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:podcast_darknet_diaries/audio_player.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';


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

class FavouritesProvider extends ChangeNotifier {
  List<int> _favourites = [];

  List<int> get favourites => _favourites;

  Future<void> loadFavourites() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? favouritesJson = prefs.getString('favourites');
    if (favouritesJson != null) {
      _favourites = (jsonDecode(favouritesJson) as List<dynamic>).cast<int>();
    } else {
      _favourites = [];
    }
    notifyListeners();
  }

  Future<void> toggleFavourite(int episodeNumber) async {
    if (_favourites.contains(episodeNumber)) {
      _favourites.remove(episodeNumber);
    } else {
      _favourites.add(episodeNumber);
    }
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('favourites', jsonEncode(_favourites));
    notifyListeners();
  }
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
  var response = await http.get(Uri.parse(url));
  if (response.statusCode == 200) {
    var document = html_parser.parse(response.body);
    return document;
  } else {
    print('Request failed with status: ${response.statusCode}.');
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
      var episodeDateAndDuration = episodeDateElement?.text.split('|').map((e) => e.trim()).toList() ?? [];
      var episodeDate = episodeDateAndDuration.isNotEmpty ? episodeDateAndDuration[0] : 'N/A';
      var episodeDuration = episodeDateAndDuration.length > 1 ? episodeDateAndDuration[1] : 'N/A';
      return "$episodeDate $episodeDuration";
  } else {
    return null;
  }

}


String? getBackgroundImageUrl(html.Document document) {
  var heroSection = document.querySelector('.hero.hero--single');
  if (heroSection != null) {
      var backgroundImageElement = heroSection.querySelector('.hero__image');
      var backgroundImageUrl = 'https://darknetdiaries.com${backgroundImageElement?.attributes['style']?.split('url(')[1].split(')')[0] ?? 'N/A'}';
      return backgroundImageUrl;
  } else {
    return null;
  }
}


String? getMp3Url(html.Document document){
  var mainContent = document.querySelector('.single-post');
  if (mainContent != null){
    var scriptElements = mainContent.querySelectorAll('script');
    for (var script in scriptElements) {
      if (script.text.contains('window.playerConfiguration')) {
        // Extract and print the mp3 link from the script content
        String? mp3Link = extractMp3Link(script.text);
        if (mp3Link != null) {
          return mp3Link;
        } else {
          print("Mp3 regex failed");
          return null;
        }
      }
    }
  } else {
    print("Main content no single-post item");
    return null;
  }
  return null;
}


String? getEpisodeContent(html.Document document) {
  var mainContent = document.querySelector('.single-post');
    if (mainContent != null) {
      // Find and exclude the specific script sections
      var scriptElements = mainContent.querySelectorAll('script');
      for (var script in scriptElements) {
        if (script.text.contains('window.playerConfiguration')) {
          script.remove();
        }
      }
      StringBuffer contentBuffer = StringBuffer();
      for (var node in mainContent.nodes) {
        if (node is html.Element) {
          if (node.localName == 'h3' && node.text.contains('Transcript')) {
            break;
          } else if (node.localName == 'p' && node.text.contains('Full Transcript')) {
            continue;
          } else {
            contentBuffer.writeln(node.text.trim());
          }
        }
      }
      return contentBuffer.toString().trim();
    } else {
      return 'Main content not found.';
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

Future<int?> lastEpisodeNumber() async {
  // Define the URL for the request
  var url = Uri.parse('https://darknetdiaries.com/episode/');
  var response = await http.get(url);
  if (response.statusCode == 200) {
    var document = html_parser.parse(response.body);
    var episodeTitles = document.querySelectorAll('.post__title');
    if (episodeTitles.isNotEmpty) {
      return extractEpisodeNumber(episodeTitles[0].text);
    } else {
      print('No episode titles found.');
      return null;
    }
  } else {
    // Print the error message
    print('Request failed with status: ${response.statusCode}.');
    return null;
  }
}

  Future<List<Episode>>? _episodeFuture;

  @override
  void initState() {
    super.initState();
    _episodeFuture = _initializeEpisodes();
  }

  Future<List<Episode>> _initializeEpisodes() async {
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

      return (await _getCachedEpisodes()).reversed.toList();
    }

    return [];
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
      ),
      drawer: Drawer(
        child: Container(
          color: const Color.fromARGB(255, 0, 0, 0), // Set your desired background color here
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
                leading: const Icon(Icons.download, color: Colors.white), // Change icon color if needed
                title: const Text(
                  'Downloads',
                  style: TextStyle(color: Colors.white), // Change text color if needed
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const DownloadsPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.favorite, color: Colors.white), // Change icon color if needed
                title: const Text(
                  'Favourites',
                  style: TextStyle(color: Colors.white), // Change text color if needed
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const FavouritesPage()),
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
              child: CircularProgressIndicator(),
            );
          } else if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
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
                    bool isFavourite = episodeNumber != null && favouritesProvider.favourites.contains(episodeNumber);

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

class FavouritesPage extends StatefulWidget {
  const FavouritesPage({super.key});

  @override
  _FavouritesPageState createState() => _FavouritesPageState();
}

class _FavouritesPageState extends State<FavouritesPage> {
  List<Episode> _favouriteEpisodes = [];

  @override
  void initState() {
    super.initState();
    _loadFavouriteEpisodes();
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

  Future<void> _loadFavouriteEpisodes() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? favouritesJson = prefs.getString('favourites');
    if (favouritesJson != null) {
      List<int> favouriteEpisodeNumbers = (jsonDecode(favouritesJson) as List<dynamic>).cast<int>();
      List<Episode> allEpisodes = await _getCachedEpisodes();

      setState(() {
        _favouriteEpisodes = allEpisodes
            .where((episode) => favouriteEpisodeNumbers.contains(extractEpisodeNumber(episode.title) ?? -1))
            .toList();
      });
    }
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Favourites', style: TextStyle(color: Colors.red)),
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
      body: _favouriteEpisodes.isEmpty
          ? const Center(
              child: Text(
                'No favourite episodes.',
                style: TextStyle(color: Colors.white),
              ),
            )
          : Consumer<FavouritesProvider>(
              builder: (context, favouritesProvider, child) {
                return ListView.builder(
                  itemCount: _favouriteEpisodes.length,
                  itemBuilder: (context, index) {
                    Episode episode = _favouriteEpisodes[index];
                    int? episodeNumber = extractEpisodeNumber(episode.title);
                    return EpisodeItem(
                      imageUrl: episode.imageUrl,
                      title: episode.title,
                      dateTime: episode.dateTime,
                      content: episode.content,
                      mp3Url: episode.mp3Url,
                      isFavourite: episodeNumber != null && favouritesProvider.favourites.contains(episodeNumber),
                      onFavouriteToggle: () {
                        if (episodeNumber != null) {
                          favouritesProvider.toggleFavourite(episodeNumber);
                          setState(() {
                            _favouriteEpisodes.removeAt(index);
                          });
                        }
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}


class EpisodeItem extends StatelessWidget {
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
              height: 100,
              width: 100,
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
            ],
          ),
        ],
      ),
    );
  }
}



class EpisodeScreen extends StatelessWidget {
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
          title,
          style: const TextStyle(color: Colors.white), // AppBar title color to white
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              dateTime,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Center(
              child: IconButton(
                icon: const Icon(Icons.play_arrow_rounded, size: 64, color: Colors.white), // Play button color to white
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
            ),
            const SizedBox(height: 16),
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
            ),
            const SizedBox(height: 16),
            Text(
              content,
              style: const TextStyle(fontSize: 18, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

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
      body: const Center(
        child: Text('Downloads Page Content'),
      ),
    );
  }
}
