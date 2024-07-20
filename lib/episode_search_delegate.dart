import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'main.dart'; 

class EpisodeSearchDelegate extends SearchDelegate<Episode?> {
  final List<Episode> episodes;

  EpisodeSearchDelegate(this.episodes);

  @override
  ThemeData appBarTheme(BuildContext context) {
    return ThemeData(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: Colors.white), // Text color for the query text
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: Colors.white54), // Hint text color
      ),
    );
  }

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, null);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    List<Episode> matchQuery = [];
    for (var episode in episodes) {
      if (episode.title.toLowerCase().contains(query.toLowerCase())) {
        matchQuery.add(episode);
      }
    }

    return Container(
      color: Colors.black, // Set background color to black
      child: ListView.builder(
        itemCount: matchQuery.length,
        itemBuilder: (context, index) {
          var episode = matchQuery[index];
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EpisodeScreen(
                    imageUrl: episode.imageUrl,
                    title: episode.title,
                    dateTime: episode.dateTime,
                    content: episode.content,
                    mp3Url: episode.mp3Url,
                  ),
                ),
              );
            },
            child: ListTile(
              leading: CachedNetworkImage(
                imageUrl: episode.imageUrl,
                placeholder: (context, url) => const CircularProgressIndicator(),
                errorWidget: (context, url, error) => const Icon(Icons.error),
                width: 50,
                height: 50,
                fit: BoxFit.cover,
              ),
              title: Text(episode.title, style: const TextStyle(color: Colors.white)),
              subtitle: Text(episode.dateTime, style: const TextStyle(color: Colors.grey)),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    List<Episode> matchQuery = [];
    for (var episode in episodes) {
      if (episode.title.toLowerCase().contains(query.toLowerCase())) {
        matchQuery.add(episode);
      }
    }

    return Container(
      color: Colors.black, // Set background color to black
      child: ListView.builder(
        itemCount: matchQuery.length,
        itemBuilder: (context, index) {
          var episode = matchQuery[index];
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EpisodeScreen(
                    imageUrl: episode.imageUrl,
                    title: episode.title,
                    dateTime: episode.dateTime,
                    content: episode.content,
                    mp3Url: episode.mp3Url,
                  ),
                ),
              );
            },
            child: ListTile(
              leading: CachedNetworkImage(
                imageUrl: episode.imageUrl,
                placeholder: (context, url) => const CircularProgressIndicator(),
                errorWidget: (context, url, error) => const Icon(Icons.error),
                width: 50,
                height: 50,
                fit: BoxFit.cover,
              ),
              title: Text(episode.title, style: const TextStyle(color: Colors.white)),
              subtitle: Text(episode.dateTime, style: const TextStyle(color: Colors.grey)),
            ),
          );
        },
      ),
    );
  }
}
