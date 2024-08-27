import 'dart:convert';
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
import 'package:sliding_up_panel/sliding_up_panel.dart';

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


class LastPlayedData {
  final String mp3Url;
  final String imageUrl;
  final String title;
  final String dateTime;
  final int position;

  LastPlayedData({
    required this.mp3Url,
    required this.imageUrl,
    required this.title,
    required this.dateTime,
    required this.position,
  });

  Map<String, dynamic> toJson() => {
    'mp3Url': mp3Url,
    'imageUrl': imageUrl,
    'title': title,
    'dateTime': dateTime,
    'position': position,
  };

  factory LastPlayedData.fromJson(Map<String, dynamic> json) {
    return LastPlayedData(
      mp3Url: json['mp3Url'],
      imageUrl: json['imageUrl'],
      title: json['title'],
      dateTime: json['dateTime'],
      position: json['position'],
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

    _audioPlayer.positionStream.listen((position) {
      //print("MINI ${audioPlayer.currentIndex != null} and ${!audioPlayer.playing} and ${audioPlayer.processingState == ProcessingState.idle}");
      if (_audioPlayer.playing) {
        _savePosition(position);
      }
    });

    _audioPlayer.playerStateStream.listen((playerState) {
      if (playerState.processingState != ProcessingState.idle) {
        _savePosition(_audioPlayer.position);
      }
    });
  }

  void _notifySafely() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners(); // Notify listeners after the frame is rendered
    });
  }  
  
  
  Future<void> handleOfflineEpisodeDeletion(String title, String imagePath, String audioPath) async {
    final sequenceState = await _audioPlayer.sequenceStateStream.first;
    if (sequenceState != null) {
      final currentSource = sequenceState.currentSource;
      if (currentSource != null) {
        final mediaItem = currentSource.tag as MediaItem;
        String currentMp3Url = mediaItem.extras?['mp3Url'].toString() ?? '';
        final currentTitle = mediaItem.title;
        if(!currentMp3Url.startsWith('http') && title == currentTitle){
          var currentImageUrl = mediaItem.artUri?.toString() ?? '';
          if (currentImageUrl.startsWith('file://')) {
            currentImageUrl = currentImageUrl.replaceFirst('file://', '');
          }
          if (currentMp3Url.startsWith('file://')) {
            currentMp3Url = currentMp3Url.replaceFirst('file://', '');
          }
          if(currentImageUrl == imagePath && currentMp3Url == audioPath){
            SharedPreferences prefs = await SharedPreferences.getInstance();
            await prefs.setBool('save', false);
            await _audioPlayer.stop();
            notifyListeners(); // Notify listeners to update UI (like MiniPlayer)
          }
        }
      }
    }
    
  }



  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||  
        state == AppLifecycleState.resumed) {
      return;
    }
    if (state == AppLifecycleState.detached || state == AppLifecycleState.paused) {
      saveCurrentPosition(); 
    }
  }


  AudioPlayer get audioPlayer => _audioPlayer;

  Future<void> _savePosition(Duration position) async {
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getBool('save') ?? false)) {
      final sequenceState = await _audioPlayer.sequenceStateStream.first;
      if (sequenceState != null) {
        final currentSource = sequenceState.currentSource;
        if (currentSource != null) {
          final mediaItem = currentSource.tag as MediaItem;
          final lastPlayedData = LastPlayedData(
            mp3Url: mediaItem.extras?['mp3Url'] ?? '',
            imageUrl: mediaItem.artUri?.toString() ?? '',
            title: mediaItem.title,
            dateTime: mediaItem.displaySubtitle ?? '',
            position: position.inMilliseconds,
          );
          await prefs.setString('lastPlayedData', jsonEncode(lastPlayedData.toJson()));
        }
      }
    }
  }


  Future<void> saveCurrentPosition() async {
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getBool('save') ?? false)) {
      final sequenceState = await _audioPlayer.sequenceStateStream.first;
      if (sequenceState != null) {
        final currentSource = sequenceState.currentSource;
        if (currentSource != null) {
          final mediaItem = currentSource.tag as MediaItem;
          final lastPlayedData = LastPlayedData(
            mp3Url: mediaItem.extras?['mp3Url'] ?? '',
            imageUrl: mediaItem.artUri?.toString() ?? '',
            title: mediaItem.title,
            dateTime: mediaItem.displaySubtitle ?? '',
            position: _audioPlayer.position.inMilliseconds,
          );
          await prefs.setString('lastPlayedData', jsonEncode(lastPlayedData.toJson()));
        }
      }
    }
  }

  @override
  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _audioPlayer.dispose();
    super.dispose();
  }
}


class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  late AudioPlayer _audioPlayer;
  final PanelController _panelController = PanelController();
  bool _isPanelOpen = false; // State variable to track if the panel is open

  @override
  void initState() {
    super.initState();
    _audioPlayer =
        Provider.of<AudioPlayerProvider>(context, listen: false).audioPlayer;
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
    return SlidingUpPanel(
      controller: _panelController,
      minHeight: 100,
      maxHeight: 280,
      panel: _buildExpandedPanel(),
      // collapsed: _buildMiniPlayer(),
      collapsed: AbsorbPointer(
        absorbing: _isPanelOpen, // Absorbs pointer events when panel is open
        child: _buildMiniPlayer(),
      ),
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(18.0),
        topRight: Radius.circular(18.0),
      ),
      onPanelSlide: (position) {
        setState(() {
          _isPanelOpen = position > 0.3; // Update based on slide position
        });
      },
      onPanelOpened: () {
        setState(() {
          _isPanelOpen = true; // Set to true when panel fully opens
        });
      },
      onPanelClosed: () {
        setState(() {
          _isPanelOpen = false; // Set to false when panel closes
        });
      },
    );
  }

  Widget _buildMiniPlayer() {
    return Container(
      decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.fromARGB(255, 9, 1, 0),
              Color.fromARGB(255, 52, 6, 0),
              Color.fromARGB(255, 136, 6, 6),
            ],
          ),
        ),
      child: StreamBuilder<SequenceState?>(
        stream: _audioPlayer.sequenceStateStream,
        builder: (context, snapshot) {
          final state = snapshot.data;
          if (state?.sequence.isEmpty ?? true) {
            return const SizedBox.shrink();
          }
          final currentTrack = state!.currentSource!.tag as MediaItem;
          return ListTile(
            leading: ImageItem(
              imageLink: currentTrack.artUri.toString(),
              height: 55,
              width: 55,
            ),
            title: 
            SizedBox(
                height: 48, // Adjust based on the font size and desired padding
                child: Text(
                  currentTrack.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16, // Adjust the font size as needed
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                  textAlign: TextAlign.left, // Optional: Ensure text is left-aligned
                ),
              ),
            subtitle: StreamBuilder<PositionData>(
              stream: Rx.combineLatest3<Duration, Duration, Duration?,
                  PositionData>(
                _audioPlayer.positionStream,
                _audioPlayer.bufferedPositionStream,
                _audioPlayer.durationStream,
                (position, bufferedPosition, duration) => PositionData(
                  position,
                  bufferedPosition,
                  duration ?? Duration.zero,
                ),
              ),
              builder: (context, snapshot) {
                final positionData = snapshot.data;
                if (positionData == null) {
                  return const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.red,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.red),
                        strokeWidth: 3,
                      ),
                    ),
                  );
                }
                return ProgressBar(
                  progress: positionData.position,
                  buffered: positionData.bufferedPosition,
                  total: positionData.duration,
                  progressBarColor: Colors.red,
                  thumbColor: Colors.red,
                  timeLabelTextStyle: const TextStyle(color: Colors.white),
                  onSeek: _audioPlayer.seek,
                );
              },
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StreamBuilder<bool>(
                  stream: _audioPlayer.playingStream,
                  builder: (context, snapshot) {
                    final isPlaying = snapshot.data ?? false;
                    return IconButton(
                      icon: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                      ),
                      onPressed: () async {
                        if (isPlaying) {
                          await _audioPlayer.pause();
                        } else {
                          await _audioPlayer.play();
                        }
                      },
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () async {
                    await _setSaveFalse();
                    await _audioPlayer.stop();
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
    );
  }

  Widget _buildExpandedPanel() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.fromARGB(255, 9, 1, 0),
            Color.fromARGB(255, 52, 6, 0),
            Color.fromARGB(255, 90, 16, 6),
            Color.fromARGB(255, 136, 6, 6),
          ],
        ),
      ),
      child: Column(
        children: [
          const Icon(Icons.keyboard_arrow_down, color: Colors.white),
          StreamBuilder<SequenceState?>(
            stream: _audioPlayer.sequenceStateStream,
            builder: (context, snapshot) {
              final state = snapshot.data;
              if (state?.sequence.isEmpty ?? true) {
                return const SizedBox.shrink(); // Handle no track playing
              }
              final currentTrack = state!.currentSource!.tag as MediaItem;

              return Column(
                children: [
                  // First Part: Image and Title with Subtitle wrapped with GestureDetector
                  GestureDetector(
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
                    child: Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ImageItem(
                            imageLink: currentTrack.artUri.toString(),
                            height: 100,
                            width: 100,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentTrack.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  currentTrack.displaySubtitle ?? '',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Second Part: Progress Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                    child: StreamBuilder<PositionData>(
                      stream: Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
                        _audioPlayer.positionStream,
                        _audioPlayer.bufferedPositionStream,
                        _audioPlayer.durationStream,
                        (position, bufferedPosition, duration) => PositionData(
                          position,
                          bufferedPosition,
                          duration ?? Duration.zero,
                        ),
                      ),
                      builder: (context, snapshot) {
                        final positionData = snapshot.data;
                        if (positionData == null) {
                          return const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.red,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                                strokeWidth: 3,
                              ),
                            ),
                          );
                        }
                        return ProgressBar(
                          progress: positionData.position,
                          buffered: positionData.bufferedPosition,
                          total: positionData.duration,
                          progressBarColor: Colors.red,
                          thumbColor: Colors.red,
                          timeLabelTextStyle: const TextStyle(color: Colors.white),
                          onSeek: _audioPlayer.seek,
                        );
                      },
                    ),
                  ),

                  // Third Part: Playback Controls
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                iconSize: 40, // Double the size of the icons
                                icon: const Icon(Icons.replay_10, color: Colors.white),
                                onPressed: () {
                                  final currentPosition = _audioPlayer.position;
                                  final newPosition =
                                      Duration(seconds: currentPosition.inSeconds - 10);
                                  _audioPlayer.seek(newPosition);
                                },
                              ),
                              StreamBuilder<bool>(
                                stream: _audioPlayer.playingStream,
                                builder: (context, snapshot) {
                                  final isPlaying = snapshot.data ?? false;
                                  return IconButton(
                                    iconSize: 68, // Double the size of the icons
                                    icon: Icon(
                                      isPlaying ? Icons.pause : Icons.play_arrow,
                                      color: Colors.white,
                                    ),
                                    onPressed: () async {
                                      if (isPlaying) {
                                        await _audioPlayer.pause();
                                      } else {
                                        await _audioPlayer.play();
                                      }
                                    },
                                  );
                                },
                              ),
                              IconButton(
                                iconSize: 40, // Double the size of the icons
                                icon: const Icon(Icons.forward_10, color: Colors.white),
                                onPressed: () {
                                  final currentPosition = _audioPlayer.position;
                                  final newPosition =
                                      Duration(seconds: currentPosition.inSeconds + 10);
                                  _audioPlayer.seek(newPosition);
                                },
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          iconSize: 48, // Double the size of the icons
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () async {
                            await _setSaveFalse();
                            await _audioPlayer.stop();
                          },
                        ),
                      ],
                    ),
                  ),
                ],
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
