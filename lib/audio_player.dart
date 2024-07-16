import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:rxdart/rxdart.dart';


class PositionData {
  const PositionData(
    this.position,
    this.bufferedPosition,
    this.duration,
  );

  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;
}

class AudioPlayerScreen extends StatefulWidget {
  final String imageUrl;
  final String title;
  final String mp3Url;
  final String dateTime;
  

  const AudioPlayerScreen({
    required this.imageUrl,
    required this.title,
    required this.dateTime,
    required this.mp3Url,
    super.key,
  });

  @override
  _AudioPlayerScreenState createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  late AudioPlayer _audioPlayer;

  Stream<PositionData> get _positionDataStream =>
    Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
      _audioPlayer.positionStream,
      _audioPlayer.bufferedPositionStream,
      _audioPlayer.durationStream,
      (position, bufferedPosition, duration) => PositionData(
        position, 
        bufferedPosition, 
        duration ?? Duration.zero,
        ),
    );


  @override
  void initState() {
    super.initState();
    //_audioPlayer = AudioPlayer()..setUrl(widget.mp3Url);
    _audioPlayer = AudioPlayer();
    _init();

  }

  int? extractEpisodeNumber(String episodeString) {
    RegExp regExp = RegExp(r'EP (\d+):');

    // Match the regular expression against the string
    Match? match = regExp.firstMatch(episodeString);

    if (match != null) {
      // Extract the first capturing group (the number)
      String episodeNumberStr = match.group(1)!;
      int episodeNumber = int.parse(episodeNumberStr);
      return episodeNumber;
    } else {
      return null;
    }
  }

  Future<void> _init() async{
    final audioSource = AudioSource.uri(
      Uri.parse(widget.mp3Url),
      tag: MediaItem(
        id: '${extractEpisodeNumber(widget.title)}', 
        title: widget.title,
        artUri: Uri.parse(widget.imageUrl)
        )
    );
    await _audioPlayer.setAudioSource(audioSource);
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.home),
            onPressed: () {
              Navigator.of(context).pop(); // Return to the home page
            },
          ),
        
        // IconButton(
        //   onPressed: () {},
        //   icon: const Icon(Icons.keyboard_arrow_down_rounded),
        // ),
        // actions: [
        //   IconButton(
        //     onPressed: () {}, 
        //     icon: const Icon(Icons.more_horiz)
        //     )
        // ],
      ),
      body: Container(
        padding: const EdgeInsets.all(20),
        height: double.infinity,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.fromARGB(255, 149, 7, 7), Color.fromARGB(255, 9, 1, 0)]
          )
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StreamBuilder<SequenceState?>(
              stream: _audioPlayer.sequenceStateStream, 
              builder: (context, snapshot) {
                final state = snapshot.data;
                if(state?.sequence.isEmpty ?? true){
                  return const SizedBox();
                }
                return Column(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            offset: Offset(2, 4),
                            blurRadius: 4,
                          )
                        ],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedNetworkImage(
                          imageUrl: widget.imageUrl,
                          height: 300,
                          width: 300,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.dateTime,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                );


              }
            ),
            const SizedBox(height: 20),
            StreamBuilder<PositionData>(
              stream: _positionDataStream, 
              builder: (context, snapshot) {
                final positionData = snapshot.data;
                return ProgressBar(
                  barHeight: 8,
                  baseBarColor: Colors.grey[600],
                  bufferedBarColor: Colors.grey,
                  progressBarColor: Colors.red,
                  thumbColor: Colors.red,
                  timeLabelTextStyle: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  progress: positionData?.position ?? Duration.zero,
                  buffered: positionData?.bufferedPosition ?? Duration.zero,
                  total: positionData?.duration ?? Duration.zero,
                  onSeek: _audioPlayer.seek,
                );
              }
            ),
            const SizedBox(height: 20),
            Controls(audioPlayer: _audioPlayer),
          ],
        ),
      ),
 
    );
  }


}


class Controls extends StatelessWidget {
  final AudioPlayer audioPlayer; 
  const Controls({
    super.key, 
    required this.audioPlayer
    });
  
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: audioPlayer.playerStateStream, 
      builder: (context, snapshot) {
        final playerState = snapshot.data;
        final processingState = playerState?.processingState;
        final playing = playerState?.playing;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: () {
                final newPosition = audioPlayer.position - const Duration(seconds: 10);
                audioPlayer.seek(newPosition < Duration.zero ? Duration.zero : newPosition);
              },
              iconSize: 40,
              color: Colors.white,
              icon: const Icon(Icons.replay_10_rounded),
            ),
            if (!(playing ?? false)) ...[
              IconButton(
                onPressed: audioPlayer.play, 
                iconSize: 80,
                color: Colors.white,
                icon: const Icon(Icons.play_arrow_rounded),
              ),
            ] else if (processingState != ProcessingState.completed) ...[
              IconButton(
                onPressed: audioPlayer.pause, 
                iconSize: 80,
                color: Colors.white,
                icon: const Icon(Icons.pause_rounded),
              ),
            ] else ...[
              const Icon(
                Icons.play_arrow_rounded,
                size: 80,
                color: Colors.white,
              ),
            ],
            IconButton(
              onPressed: () {
                final newPosition = audioPlayer.position + const Duration(seconds: 10);
                audioPlayer.seek(newPosition);
              },
              iconSize: 40,
              color: Colors.white,
              icon: const Icon(Icons.forward_10_rounded),
            ),
          ],
        );
      }
    );
  }
}

