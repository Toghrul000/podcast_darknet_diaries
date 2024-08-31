import 'dart:convert';
import 'dart:io';
import 'package:html/dom.dart' as html;
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:just_audio/just_audio.dart';
import 'package:podcast_darknet_diaries/audio_player.dart';
import 'package:podcast_darknet_diaries/downloads.dart';
import 'package:podcast_darknet_diaries/episode.dart';
import 'package:podcast_darknet_diaries/episode_search_delegate.dart';
import 'package:podcast_darknet_diaries/favourites.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';



Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.ryanheise.bg_demo.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );

  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AudioPlayerProvider()),
        ChangeNotifierProvider(create: (context) => FavouritesProvider()..loadFavourites()),
        ChangeNotifierProvider(create: (context) => DownloadProvider()),
      ],
      child: const MyApp(),
    ),
  );
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
    final mainContent = document.querySelector('.single-post');
    if (mainContent != null) {
      // Remove script sections containing 'window.playerConfiguration'
      final scriptElements = mainContent.querySelectorAll('script');
      for (var script in scriptElements) {
        if (script.text.contains('window.playerConfiguration')) {
          script.remove();
        }
      }
      // Buffer to collect the content
      final contentBuffer = StringBuffer();
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

  String processElementContent(html.Element element) {
    StringBuffer contentBuffer = StringBuffer();
    for (var child in element.nodes) {
      if (child is html.Text) {
        switch (element.localName) {
          case 'a':
            contentBuffer.write(' [${child.text.trim()}](${child.attributes['href']})');
            break;
          case 'h1':
            contentBuffer.writeln('\n# ${child.text.trim()}\n');
            break;
          case 'h2':
            contentBuffer.writeln('\n## ${child.text.trim()}\n');
            break;
          case 'h3':
            contentBuffer.writeln('\n### ${child.text.trim()}\n');
            break;
          case 'h4':
            contentBuffer.writeln('\n#### ${child.text.trim()}\n');
            break;
          case 'h5':
            contentBuffer.writeln('\n##### ${child.text.trim()}\n');
            break;
          case 'h6':
            contentBuffer.writeln('\n###### ${child.text.trim()}\n');
            break;
          case 'p':
            contentBuffer.writeln('\n${child.text.trim()}');
            break;
          default:
            contentBuffer.write(child.text.trim());
            break;
        }
      } else if (child is html.Element) {
        switch (child.localName) {
          case 'a':
            contentBuffer.write(' [${child.text.trim()}](${child.attributes['href']})');
            break;
          case 'h1':
            contentBuffer.writeln('\n# ${child.text.trim()}\n');
            break;
          case 'h2':
            contentBuffer.writeln('\n## ${child.text.trim()}\n');
            break;
          case 'h3':
            contentBuffer.writeln('\n### ${child.text.trim()}\n');
            break;
          case 'h4':
            contentBuffer.writeln('\n#### ${child.text.trim()}\n');
            break;
          case 'h5':
            contentBuffer.writeln('\n##### ${child.text.trim()}\n');
            break;
          case 'h6':
            contentBuffer.writeln('\n###### ${child.text.trim()}\n');
            break;
          case 'p':
            contentBuffer.writeln('\n${child.text.trim()}\n');
            break;
          case 'ul':
            contentBuffer.writeln(processListContent(child));
            break;
          case 'li':
            contentBuffer.writeln('- ${processElementContent(child)}');
            break;
          default:
            contentBuffer.write(child.text.trim());
            break;
        }
      }
    }
    return contentBuffer.toString().trim();
  }

  String processListContent(html.Element element) {
    StringBuffer listBuffer = StringBuffer();
    for (var child in element.children) {
      if (child.localName == 'li') {
        listBuffer.writeln('- ${processElementContent(child)}');
      }
    }
    return listBuffer.toString().trim();
  }


  int extractEpisodeNumber(String episodeString) {
    RegExp regExp = RegExp(r'EP (\d+):');
    Match? match = regExp.firstMatch(episodeString);
    if (match != null) {
      String episodeNumberStr = match.group(1)!;
      int episodeNumber = int.parse(episodeNumberStr);
      return episodeNumber;
    } else {
      return -1;
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
  double _progress = 0.0;
  bool isLoadingLastPlayed = false;
  bool _isFetchingNewEpisodes = false;

  @override
  void initState() {
    super.initState();
    _episodeFuture = _initializeEpisodes();
    _loadLastSaved();

    if(mounted){
        context.read<AudioPlayerProvider>().audioPlayer.playingStream.listen((playing) {
        setState(() {
          // This will trigger the UI update when the playing state changes
        });
      });
    }
  }


  void reFetch() {
    setState(() {
      Provider.of<FavouritesProvider>(context, listen: false).setErrorMessage(null);
      _errorMessage = null; // Reset the error message
      _episodeFuture = _initializeEpisodes();
    });
  }

  void _handleHardReFetch() {
    setState(() {
      Provider.of<FavouritesProvider>(context, listen: false).setErrorMessage(null);
      _errorMessage = null; // Reset the error message
      _episodeFuture = _hardReFetch();
    });
  }

  void _loadLastSaved() async {
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getBool('save') ?? false)) {
      final lastPlayedDataString = prefs.getString('lastPlayedData');
      if (lastPlayedDataString != null) {
        final lastPlayedData = LastPlayedData.fromJson(jsonDecode(lastPlayedDataString));
        if (mounted) {
          final audioPlayerProvider = Provider.of<AudioPlayerProvider>(context, listen: false);
          final audioPlayer = audioPlayerProvider.audioPlayer;
          try {
            final UriAudioSource audioSource;
            if (File(lastPlayedData.mp3Url).existsSync() && File(lastPlayedData.imageUrl).existsSync()) {
              audioSource = AudioSource.uri(
                Uri.file(lastPlayedData.mp3Url),
                tag: MediaItem(
                  id: '${extractEpisodeNumber(lastPlayedData.title)}',
                  title: lastPlayedData.title,
                  artUri: Uri.file(lastPlayedData.imageUrl),
                  displayTitle: lastPlayedData.title,
                  displaySubtitle: lastPlayedData.dateTime,
                  extras: {
                    'mp3Url': lastPlayedData.mp3Url,
                  },
                ),
              );
            } else {
              audioSource = AudioSource.uri(
                Uri.parse(lastPlayedData.mp3Url),
                tag: MediaItem(
                  id: '${extractEpisodeNumber(lastPlayedData.title)}',
                  title: lastPlayedData.title,
                  artUri: Uri.parse(lastPlayedData.imageUrl),
                  displayTitle: lastPlayedData.title,
                  displaySubtitle: lastPlayedData.dateTime,
                  extras: {
                    'mp3Url': lastPlayedData.mp3Url,
                  },
                ),
              );
            }
            await audioPlayer.setAudioSource(audioSource);
            await audioPlayer.seek(Duration(milliseconds: lastPlayedData.position));
          } catch (e) {
            if (mounted) {
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
    }
  }

  void _loadLastPlayed() async {
    final prefs = await SharedPreferences.getInstance();
    final lastPlayedDataString = prefs.getString('lastPlayedData');
    if (lastPlayedDataString != null) {
      final lastPlayedData = LastPlayedData.fromJson(jsonDecode(lastPlayedDataString));
      setState(() {
        isLoadingLastPlayed = true;
      });
      if (mounted) {
        final audioPlayerProvider = Provider.of<AudioPlayerProvider>(context, listen: false);
        final audioPlayer = audioPlayerProvider.audioPlayer;
        try {
          final UriAudioSource audioSource;
          if (File(lastPlayedData.mp3Url).existsSync() && File(lastPlayedData.imageUrl).existsSync()) {
            audioSource = AudioSource.uri(
              Uri.file(lastPlayedData.mp3Url),
              tag: MediaItem(
                id: '${extractEpisodeNumber(lastPlayedData.title)}',
                title: lastPlayedData.title,
                artUri: Uri.file(lastPlayedData.imageUrl),
                displayTitle: lastPlayedData.title,
                displaySubtitle: lastPlayedData.dateTime,
                extras: {
                  'mp3Url': lastPlayedData.mp3Url,
                },
              ),
            );
          } else {
            audioSource = AudioSource.uri(
              Uri.parse(lastPlayedData.mp3Url),
              tag: MediaItem(
                id: '${extractEpisodeNumber(lastPlayedData.title)}',
                title: lastPlayedData.title,
                artUri: Uri.parse(lastPlayedData.imageUrl),
                displayTitle: lastPlayedData.title,
                displaySubtitle: lastPlayedData.dateTime,
                extras: {
                  'mp3Url': lastPlayedData.mp3Url,
                },
              ),
            );
          }
          await audioPlayer.setAudioSource(audioSource);
          setState(() {
            isLoadingLastPlayed = false;
          });
          await audioPlayer.seek(Duration(milliseconds: lastPlayedData.position));
          await audioPlayer.play();
        } catch (e) {
          if (mounted) {
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
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No Saved Episode', style: TextStyle(fontWeight: FontWeight.bold),),
            duration: const Duration(seconds: 4),
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


  Future<List<Episode>> _hardReFetch() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      int? latestEpisode = await lastEpisodeNumber();

      if (latestEpisode != null) {
        setState(() {
          _isFetchingNewEpisodes = true; 
          _progress = 0.0;
        });

        for (int i = latestEpisode; i > 0; i--) {
          String episodeUrl = 'https://darknetdiaries.com/episode/$i/';
          html.Document? document = await fetchEpisodeDetails(episodeUrl);
          if (document != null) {
            String mp3Url = getMp3Url(document) ?? '';
            String imageUrl = getBackgroundImageUrl(document) ?? '';
            String title = getTitle(document) ?? '';
            String dateTime = getDateTime(document) ?? '';
            String content = getEpisodeContent(document) ?? '';
            
            Episode episode = Episode(
              episodeNumber: extractEpisodeNumber(title),
              imageUrl: imageUrl,
              title: title,
              dateTime: dateTime,
              content: content,
              mp3Url: mp3Url,
            );
            await _cacheEpisode(i, episode);
            setState(() {
              _progress = (latestEpisode - i + 1) / latestEpisode;
            });
          }
        }
        setState(() {
          _isFetchingNewEpisodes = false; 
        });
        await prefs.setInt('lastEpisode', latestEpisode);
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

  Future<List<Episode>> _initializeEpisodes() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      int? lastStoredEpisode = prefs.getInt('lastEpisode');
      int? latestEpisode = await lastEpisodeNumber();

      if (latestEpisode != null) {
        if (lastStoredEpisode == null || lastStoredEpisode < latestEpisode) {
          setState(() {
            _isFetchingNewEpisodes = true; 
            _progress = 0.0;
          });
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
                episodeNumber: extractEpisodeNumber(title),
                imageUrl: imageUrl,
                title: title,
                dateTime: dateTime,
                content: content,
                mp3Url: mp3Url,
              );

              await _cacheEpisode(i, episode);
              
              setState(() {
                _progress = (latestEpisode - i + 1) / latestEpisode;
              });
            }
          }
          setState(() {
            _isFetchingNewEpisodes = false; 
          });
          await prefs.setInt('lastEpisode', latestEpisode);
        } else {
          setState(() {
            _isFetchingNewEpisodes = false; 
          });
        }
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
        iconTheme: const IconThemeData(color: Colors.grey), 
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
                delegate: EpisodeSearchDelegate(episodes, context),
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
                          MaterialPageRoute(builder: (context) => const PersistentMiniPlayerWrapper(child: DownloadsPage())),
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
                          MaterialPageRoute(builder: (context) => const PersistentMiniPlayerWrapper(child: FavouritesPage())),
                        );
                      },
                    ),
                    const Divider(color: Colors.white), 
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
                                fontSize: 18.0, 
                              ),
                            ),
                          ),
                          Switch(
                            value: _isNewestFirst,
                            onChanged: (value) {
                              setState(() {
                                _isNewestFirst = value;
                                reFetch();
                              });
                            },
                            activeColor: Colors.red, 
                            activeTrackColor: Colors.red[200], 
                            inactiveThumbColor: Colors.grey, 
                            inactiveTrackColor: Colors.grey[600], 
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.play_circle, color: Colors.white), 
                title: Row(
                  children: [
                    const Text(
                      'Load Last Played',
                      style: TextStyle(color: Colors.white), 
                    ),
                    if (isLoadingLastPlayed) 
                      const SizedBox(
                        width: 8, 
                      ),
                    if (isLoadingLastPlayed)
                      const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.0,
                          color: Colors.red,
                        ),
                      ),
                  ],
                ),
                onTap: () {
                  setState(() {
                    _loadLastPlayed();
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.refresh, color: Colors.white), 
                title: const Text(
                  'Hard Re-Fetch Episodes',
                  style: TextStyle(color: Colors.white), 
                ),
                onTap: () {
                  Navigator.pop(context); 
                  _handleHardReFetch(); 
                },
              ),
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
      body: Stack(
        children: [
          FutureBuilder<List<Episode>>(
            future: _episodeFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          const CircularProgressIndicator(
                            color: Colors.red,
                          ),
                          Positioned(
                            child: Text(
                              _isFetchingNewEpisodes 
                              ? '${(_progress * 100).toStringAsFixed(0)}%' 
                              : '',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Fetching episodes...',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      )
                    ],
                  )
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
                    return RefreshIndicator(
                      onRefresh: () async {
                        reFetch();
                      },
                      color: Colors.red, // The color of the refresh indicator
                      backgroundColor: const Color.fromARGB(255, 7, 0, 0), // Background color of the refresh indicator
                      child: ListView.builder(
                        itemCount: episodes.length,
                        itemBuilder: (context, index) {
                          Episode episode = episodes[index];
                          int episodeNumber = episode.episodeNumber;
                          bool isFavourite = favouritesProvider.favourites.contains(episodeNumber);

                          return EpisodeItem(
                            episodeNumber: episodeNumber,
                            imageUrl: episode.imageUrl,
                            title: episode.title,
                            dateTime: episode.dateTime,
                            content: episode.content,
                            mp3Url: episode.mp3Url,
                            isFavourite: isFavourite,
                            onFavouriteToggle: () {
                              favouritesProvider.toggleFavourite(episodeNumber);
                            },
                            homeContext: context,
                          );
                        },
                      ),
                    );
                  },
                );
              }
            },
          ),
          Consumer<AudioPlayerProvider>(
            builder: (context, audioProvider, child) {
              final audioPlayer = audioProvider.audioPlayer;
              final hasAudioSource = audioPlayer.currentIndex != null;
              bool isStopped = !audioProvider.audioPlayer.playing && audioProvider.audioPlayer.processingState == ProcessingState.idle;
              if (hasAudioSource && !isStopped) {
                return const Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: MiniPlayer(),
                );
              } else {
                return const SizedBox.shrink();
              }
            },
          ),
        ],
      ),
    );
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Markdown(
            selectable: true,
            data: '''
# Welcome to Darknet Diaries fanmade podcast app!

This app was created as a fun project to learn Flutter mobile development and explore its capabilities. I love Darknet Diaries, and that is why I chose this podcast for the app. I hope you enjoy using the app as much as I enjoyed making it. 

If you have any comments or feedback about the app that you want to directly send to me, feel free to send them to [25879G@protonmail.com](mailto:25879G@protonmail.com).
            ''',
            styleSheet: MarkdownStyleSheet(
              p: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
              h1: const TextStyle(
                color: Colors.red,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              a: const TextStyle(
                color: Colors.blue,
                decoration: TextDecoration.underline,
              ),
            ),
            onTapLink: (text, url, title) {
                  launchUrl(Uri.parse(url!));
              },
          ),
        ),
      ),
    );
  }
}