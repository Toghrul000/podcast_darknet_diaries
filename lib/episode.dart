import 'package:podcast_darknet_diaries/audio_player.dart';
import 'package:podcast_darknet_diaries/downloads.dart';
import 'package:podcast_darknet_diaries/favourites.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';


class EpisodeItem extends StatelessWidget {
  final String imageUrl;
  final String title;
  final String dateTime;
  final String content;
  final int episodeNumber;
  final String mp3Url;
  final bool isFavourite;
  final VoidCallback onFavouriteToggle;
  final BuildContext homeContext;

  const EpisodeItem({
    required this.imageUrl,
    required this.title,
    required this.dateTime,
    required this.content,
    required this.mp3Url,
    required this.episodeNumber,
    required this.isFavourite,
    required this.onFavouriteToggle,
    required this.homeContext,
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
                    homeContext: homeContext,
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
                      homeContext: homeContext,
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
                    style: const TextStyle(fontSize: 15, color: Colors.white),
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
  final BuildContext homeContext;

  const EpisodeScreen({
    required this.imageUrl,
    required this.title,
    required this.dateTime,
    required this.content,
    required this.mp3Url,
    required this.episodeNumber,
    required this.homeContext,
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
      backgroundColor: Colors.black, 
      appBar: AppBar(
        backgroundColor: Colors.black, 
        leading: IconButton(
          icon: const Icon(Icons.home, color: Colors.white), 
          onPressed: () {
            Navigator.popUntil(context, (route) => route.isFirst);
          },
        ),
        title: Text(
          widget.title,
          style: const TextStyle(color: Colors.white), 
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
                    icon: const Icon(Icons.play_arrow_rounded, size: 64, color: Colors.white), 
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
                          onPressed: () => downloadProvider.cancelDownload(widget.homeContext, widget.episodeNumber),
                        ),
                      ],
                    )
                    : IconButton(
                        icon: const Icon(Icons.download, size: 50, color: Colors.white),
                        onPressed: () {
                          downloadProvider.downloadEpisode(widget.homeContext, widget.episodeNumber, widget.title, widget.dateTime, widget.imageUrl, widget.mp3Url);
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
              selectable: true,
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

