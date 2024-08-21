import 'dart:io';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:podcast_darknet_diaries/image_item.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PersistentMiniPlayerWrapper extends StatelessWidget {
  final Widget child;

  const PersistentMiniPlayerWrapper({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          child, // The main content of the screen (page)
          Consumer<AudioPlayerProvider>(
            builder: (context, audioProvider, child) {
              final audioPlayer = audioProvider.audioPlayer;
              final hasAudioSource = audioPlayer.currentIndex != null;
              bool isStopped = !audioProvider.audioPlayer.playing && audioProvider.audioPlayer.processingState == ProcessingState.idle;
              if (hasAudioSource && !isStopped) {
                return Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: MiniPlayer(audioPlayer: audioPlayer),
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

class AudioPlayerProvider with ChangeNotifier, WidgetsBindingObserver {
  final AudioPlayer _audioPlayer = AudioPlayer();

  AudioPlayerProvider() {
    WidgetsBinding.instance.addObserver(this);
    
    _audioPlayer.playingStream.listen((playing) {
      _notifySafely(); // Notify listeners when playing state changes
    });
    _audioPlayer.currentIndexStream.listen((index) {
      _notifySafely(); // Notify listeners when the current track changes
    });

    // Listen for playback events to handle stop or completion
    // _audioPlayer.playbackEventStream.listen((event) {
    //   if (event.processingState == ProcessingState.completed ||
    //       event.processingState == ProcessingState.idle) {
    //     _handleStop(); 
    //   }
    // });
  }

  // void _handleStop(){
  //   print("STOOOPPPING");
  //   saveCurrentPosition();

  // }

  void _notifySafely() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners(); // Notify listeners after the frame is rendered
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || 
        state == AppLifecycleState.paused || 
        state == AppLifecycleState.resumed) {
      return;
    }
    if (state == AppLifecycleState.resumed) return;
    if (state == AppLifecycleState.detached) {
      saveCurrentPosition(); 
    }
  }


  AudioPlayer get audioPlayer => _audioPlayer;

  Future<void> saveCurrentPosition() async {
    final prefs = await SharedPreferences.getInstance();
    if((prefs.getBool('save') ?? false)){
      final sequenceState = await _audioPlayer.sequenceStateStream.first;
      if (sequenceState != null) {
        final currentSource = sequenceState.currentSource;
        if (currentSource != null) {
          final mediaItem = currentSource.tag as MediaItem;
          await prefs.setString('lastPlayedUrl', mediaItem.extras?['mp3Url'] ?? '');
          await prefs.setString('lastPlayedImageUrl', mediaItem.artUri?.toString() ?? '');
          await prefs.setString('lastPlayedTitle', mediaItem.title);
          await prefs.setString('lastPlayedDateTime', mediaItem.displaySubtitle ?? '');
          await prefs.setInt('lastPlayedPosition', _audioPlayer.position.inMilliseconds);
        }
      }

    }
  }

  @override
  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    // saveCurrentPosition();
    await _audioPlayer.dispose();
    _notifySafely();

    super.dispose();
  }
}

class MiniPlayer extends StatelessWidget {
  final AudioPlayer audioPlayer;

  MiniPlayer({required this.audioPlayer, super.key}) {
    _setSaveTrue();
  }

  Future<void> _setSaveFalse() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('save', false);
  }


  Future<void> _setSaveTrue() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('save', true);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<SequenceState?>(
            stream: audioPlayer.sequenceStateStream,
            builder: (context, snapshot) {
              final state = snapshot.data;
              if (state?.sequence.isEmpty ?? true) {
                return const SizedBox.shrink();
              }
              final currentTrack = state!.currentSource!.tag as MediaItem;
              return ListTile(
                leading: 
                ImageItem(
                  imageLink: currentTrack.artUri.toString(),
                  height: 50,
                  width: 50,
                ),
                title: Text(
                  currentTrack.title,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: StreamBuilder<PositionData>(
                  stream: Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
                    audioPlayer.positionStream,
                    audioPlayer.bufferedPositionStream,
                    audioPlayer.durationStream,
                    (position, bufferedPosition, duration) => PositionData(
                      position,
                      bufferedPosition,
                      duration ?? Duration.zero,
                    ),
                  ),
                  builder: (context, snapshot) {
                    final positionData = snapshot.data;
                    return ProgressBar(
                      progress: positionData?.position ?? Duration.zero,
                      buffered: positionData?.bufferedPosition ?? Duration.zero,
                      total: positionData?.duration ?? Duration.zero,
                      progressBarColor: Colors.red,
                      thumbColor: Colors.red,
                      timeLabelTextStyle: const TextStyle(color: Colors.white),
                      onSeek: audioPlayer.seek,
                    );
                  },
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        audioPlayer.playing ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                      ),
                      onPressed: () async {
                        if (audioPlayer.playing) {
                          await audioPlayer.pause();
                        } else {
                          await audioPlayer.play();
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () async {
                        await _setSaveFalse();
                        await audioPlayer.stop();
                      },
                    ),
                  ],
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AudioPlayerScreen(
                        imageUrl: currentTrack.artUri.toString(),
                        title: currentTrack.title,
                        dateTime: currentTrack.displaySubtitle ?? '',
                        mp3Url: currentTrack.extras?['mp3Url'] ?? '',
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}


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
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
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
    _audioPlayer = Provider.of<AudioPlayerProvider>(context, listen: false).audioPlayer;
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

  Future<void> _init() async {
    try {
      // Check if the audio player already has an audio source set and it's playing the same audio.
      if (_audioPlayer.audioSource == null || (_audioPlayer.audioSource?.sequence.first.tag as MediaItem).id != '${extractEpisodeNumber(widget.title)}') {
        final UriAudioSource audioSource;

        if (File(widget.mp3Url).existsSync() && File(widget.imageUrl).existsSync()) {
          audioSource = AudioSource.uri(
            Uri.file(widget.mp3Url),
            tag: MediaItem(
              id: '${extractEpisodeNumber(widget.title)}',
              title: widget.title,
              artUri: Uri.file(widget.imageUrl),
              displayTitle: widget.title,
              displaySubtitle: widget.dateTime,
              extras: {
                'mp3Url': widget.mp3Url,
              },
            ),
          );
        } else {
          audioSource = AudioSource.uri(
            Uri.parse(widget.mp3Url),
            tag: MediaItem(
              id: '${extractEpisodeNumber(widget.title)}',
              title: widget.title,
              artUri: Uri.parse(widget.imageUrl),
              displayTitle: widget.title,
              displaySubtitle: widget.dateTime,
              extras: {
                'mp3Url': widget.mp3Url,
              },
            ),
          );
        }

        // Set the new audio source if needed
        await _audioPlayer.setAudioSource(audioSource);
        await _audioPlayer.play();
      } else {
        // If the audio source is already set, just resume playing
        await _audioPlayer.play();
      }
    } on SocketException catch (e) {
      _showErrorSnackBar('Network Error:$e');
    } on PlatformException catch (e) {
       _showErrorSnackBar('Error:$e');
    } catch (e) {
      _showErrorSnackBar('Something went wrong: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    if(mounted){
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
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
                          ),
                        ],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: ImageItem(
                          imageLink: widget.imageUrl,
                          height: 300,
                          width: 300,
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
    required this.audioPlayer,
  });

  void _showErrorSnackBar(BuildContext context, message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.0),
        ),
      ),
    );
  }

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
              onPressed: () async {
                try {
                  final newPosition = audioPlayer.position - const Duration(seconds: 10);
                  await audioPlayer.seek(newPosition < Duration.zero ? Duration.zero : newPosition);
                } on SocketException catch (e) {
                    if(context.mounted){
                      _showErrorSnackBar(context, 'Network Error:$e');
                    }
                  } on PlatformException catch (e) {
                    if(context.mounted){
                      _showErrorSnackBar(context, 'Error:$e');
                    }
                  } catch (e) {
                    if(context.mounted){
                      _showErrorSnackBar(context, 'Something went wrong:$e');
                    }
                  }
              },
              iconSize: 40,
              color: Colors.white,
              icon: const Icon(Icons.replay_10_rounded),
            ),
            if (!(playing ?? false)) ...[
              IconButton(
                onPressed: () async {
                  try {
                    await audioPlayer.play();
                  } on SocketException catch (e) {
                    if(context.mounted){
                      _showErrorSnackBar(context, 'Network Error:$e');
                    }
                  } on PlatformException catch (e) {
                    if(context.mounted){
                      _showErrorSnackBar(context, 'Error:$e');
                    }
                  } catch (e) {
                    if(context.mounted){
                      _showErrorSnackBar(context, 'Something went wrong:$e');
                    }
                  }
                },
                iconSize: 80,
                color: Colors.white,
                icon: const Icon(Icons.play_arrow_rounded),
              ),
            ] else if (processingState != ProcessingState.completed) ...[
              IconButton(
                onPressed: () async {
                  try {
                    await audioPlayer.pause();
                  } on SocketException catch (e) {
                    if(context.mounted){
                      _showErrorSnackBar(context, 'Network Error:$e');
                    }
                  } on PlatformException catch (e) {
                    if(context.mounted){
                      _showErrorSnackBar(context, 'Error:$e');
                    }
                  } catch (e) {
                    if(context.mounted){
                      _showErrorSnackBar(context, 'Something went wrong:$e');
                    }
                  }
                },
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
              onPressed: () async {
                try {
                  final newPosition = audioPlayer.position + const Duration(seconds: 10);
                  await audioPlayer.seek(newPosition);
                } on SocketException catch (e) {
                    if(context.mounted){
                      _showErrorSnackBar(context, 'Network Error:$e');
                    }
                  } on PlatformException catch (e) {
                    if(context.mounted){
                      _showErrorSnackBar(context, 'Error:$e');
                    }
                  } catch (e) {
                    if(context.mounted){
                      _showErrorSnackBar(context, 'Something went wrong:$e');
                    }
                  }
              },
              iconSize: 40,
              color: Colors.white,
              icon: const Icon(Icons.forward_10_rounded),
            ),
          ],
        );
      },
    );
  }

}
