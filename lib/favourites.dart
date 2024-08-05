import 'dart:convert';
import 'package:podcast_darknet_diaries/episode.dart';
import 'package:podcast_darknet_diaries/main.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';



class FavouritesProvider extends ChangeNotifier {
  List<int> _favourites = [];
  String? _errorMessage;

  List<int> get favourites => _favourites;
  String? get errorMessage => _errorMessage;

  void setErrorMessage(String? message) {
    _errorMessage = message;
  }

  Future<void> loadFavourites() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? favouritesJson = prefs.getString('favourites');
      if (favouritesJson != null) {
        _favourites = (jsonDecode(favouritesJson) as List<dynamic>).cast<int>();
      } else {
        _favourites = [];
      }
      _errorMessage = null; // Reset the error message on success
    } catch (e) {
      _errorMessage = 'Failed to load favourites';
    }
    notifyListeners();
  }

  Future<void> toggleFavourite(int episodeNumber) async {
    if (_favourites.contains(episodeNumber)) {
      _favourites.remove(episodeNumber);
    } else {
      _favourites.add(episodeNumber);
    }
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('favourites', jsonEncode(_favourites));
      _errorMessage = null; // Reset the error message on success
    } catch (e) {
      _errorMessage = 'Failed to update favourites';
    }
    notifyListeners();
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

      // // This is sorted version
      // setState(() {
      //   _favouriteEpisodes = allEpisodes
      //       .where((episode) => favouriteEpisodeNumbers.contains(extractEpisodeNumber(episode.title) ?? -1))
      //       .toList();
      // });
      setState(() {
        _favouriteEpisodes = favouriteEpisodeNumbers.map((episodeNumber) {
          return allEpisodes.firstWhere((episode) => extractEpisodeNumber(episode.title) == episodeNumber);
        }).toList();
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
                if (favouritesProvider.errorMessage != null) {
                  return Center(
                    child: Text(
                      'Error: ${favouritesProvider.errorMessage}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }
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