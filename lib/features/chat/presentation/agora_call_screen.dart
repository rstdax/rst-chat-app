import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
// ---> 1. ADD THE RINGTONE PLAYER <---
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

class AgoraCallScreen extends StatefulWidget {
  final String channelName;
  final bool isOutgoing; // Tells us if we should play the ringtone

  const AgoraCallScreen({
    super.key,
    required this.channelName,
    required this.isOutgoing,
  });

  @override
  State<AgoraCallScreen> createState() => _AgoraCallScreenState();
}

class _AgoraCallScreenState extends State<AgoraCallScreen> {
  final String appId =
      "e8fb5921255f4215a0994e9620e77466"; // Keep your App ID here

  final List<int> _remoteUids = [];
  bool _localUserJoined = false;
  bool _muted = false;
  bool _videoDisabled = false;

  // ---> 2. TRACK RINGING STATE <---
  bool _isRinging = false;

  late RtcEngine _engine;

  @override
  void initState() {
    super.initState();
    initAgora();

    // ---> 3. START THE CUSTOM RINGTONE <---
    if (widget.isOutgoing) {
      _isRinging = true;

      FlutterRingtonePlayer().play(
        fromAsset: "assets/sounds/ringtone.mp3", // Exact path to your file
        looping: true, // Keep ringing until they answer
        volume: 1.0, // Full volume
      );
    }
  }

  Future<void> initAgora() async {
    await [Permission.microphone, Permission.camera].request();

    _engine = createAgoraRtcEngine();
    await _engine.initialize(
      RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );

    await _engine.enableVideo();
    await _engine.startPreview();

    _engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          debugPrint("Local user joined");
          setState(() => _localUserJoined = true);
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          debugPrint("Remote user joined: $remoteUid");
          setState(() {
            _remoteUids.add(remoteUid);
          });

          // ---> 4. STOP RINGING WHEN SOMEONE ANSWERS <---
          if (_isRinging) {
            FlutterRingtonePlayer().stop();
            setState(() => _isRinging = false);
          }
        },
        onUserOffline:
            (
              RtcConnection connection,
              int remoteUid,
              UserOfflineReasonType reason,
            ) {
              debugPrint("Remote user left: $remoteUid");
              setState(() {
                _remoteUids.remove(remoteUid);
              });
            },
      ),
    );

    await _engine.joinChannel(
      token: '',
      channelId: widget.channelName,
      uid: 0,
      options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );
  }

  @override
  void dispose() {
    // ---> 5. ALWAYS STOP RINGTONE ON HANGUP <---
    FlutterRingtonePlayer().stop();
    _engine.leaveChannel();
    _engine.release();
    super.dispose();
  }

  void _onToggleMute() {
    setState(() => _muted = !_muted);
    _engine.muteLocalAudioStream(_muted);
  }

  void _onToggleVideo() {
    setState(() => _videoDisabled = !_videoDisabled);
    _engine.muteLocalVideoStream(_videoDisabled);
  }

  void _onSwitchCamera() {
    _engine.switchCamera();
  }

  void _onCallEnd(BuildContext context) {
    Navigator.pop(context);
  }

  Widget _viewRows() {
    final List<Widget> list = [];

    if (_localUserJoined) {
      list.add(
        _videoDisabled
            ? Container(
                color: Colors.grey.shade900,
                child: const Center(
                  child: Icon(
                    Icons.videocam_off,
                    color: Colors.white,
                    size: 60,
                  ),
                ),
              )
            : AgoraVideoView(
                controller: VideoViewController(
                  rtcEngine: _engine,
                  canvas: const VideoCanvas(uid: 0),
                ),
              ),
      );
    }

    for (var uid in _remoteUids) {
      list.add(
        AgoraVideoView(
          controller: VideoViewController.remote(
            rtcEngine: _engine,
            canvas: VideoCanvas(uid: uid),
            connection: RtcConnection(channelId: widget.channelName),
          ),
        ),
      );
    }

    if (list.isEmpty) {
      return const Center(
        child: Text('Loading...', style: TextStyle(color: Colors.white)),
      );
    } else if (list.length == 1) {
      return list[0];
    } else if (list.length == 2) {
      return Column(
        children: [
          Expanded(child: list[0]),
          Expanded(child: list[1]),
        ],
      );
    } else {
      return GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.0,
        ),
        itemCount: list.length,
        itemBuilder: (context, index) => list[index],
      );
    }
  }

  Widget _toolbar() {
    return Container(
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RawMaterialButton(
            onPressed: _onToggleMute,
            shape: const CircleBorder(),
            elevation: 2.0,
            fillColor: _muted ? Colors.blueAccent : Colors.white,
            padding: const EdgeInsets.all(12.0),
            child: Icon(
              _muted ? Icons.mic_off : Icons.mic,
              color: _muted ? Colors.white : Colors.blueAccent,
              size: 24.0,
            ),
          ),
          RawMaterialButton(
            onPressed: () => _onCallEnd(context),
            shape: const CircleBorder(),
            elevation: 2.0,
            fillColor: Colors.redAccent,
            padding: const EdgeInsets.all(15.0),
            child: const Icon(Icons.call_end, color: Colors.white, size: 35.0),
          ),
          RawMaterialButton(
            onPressed: _onToggleVideo,
            shape: const CircleBorder(),
            elevation: 2.0,
            fillColor: _videoDisabled ? Colors.blueAccent : Colors.white,
            padding: const EdgeInsets.all(12.0),
            child: Icon(
              _videoDisabled ? Icons.videocam_off : Icons.videocam,
              color: _videoDisabled ? Colors.white : Colors.blueAccent,
              size: 24.0,
            ),
          ),
          RawMaterialButton(
            onPressed: _onSwitchCamera,
            shape: const CircleBorder(),
            elevation: 2.0,
            fillColor: Colors.white,
            padding: const EdgeInsets.all(12.0),
            child: const Icon(
              Icons.switch_camera,
              color: Colors.blueAccent,
              size: 24.0,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _viewRows(),

          // ---> 6. THE "RINGING..." UI OVERLAY <---
          if (_isRinging && _remoteUids.isEmpty)
            Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  const Text(
                    'Calling...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 10)],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Waiting for others to join',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
                      shadows: const [
                        Shadow(color: Colors.black54, blurRadius: 8),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          _toolbar(),
        ],
      ),
    );
  }
}
