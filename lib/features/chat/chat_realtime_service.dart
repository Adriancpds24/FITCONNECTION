import 'dart:async';

import 'package:rms/core/constants/api_constants.dart';
import 'package:rms/features/auth/auth_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class ChatPresenceEvent {
  final String username;
  final bool isOnline;

  const ChatPresenceEvent({
    required this.username,
    required this.isOnline,
  });
}

class ChatTypingEvent {
  final String senderUsername;
  final String targetUsername;
  final bool isTyping;

  const ChatTypingEvent({
    required this.senderUsername,
    required this.targetUsername,
    required this.isTyping,
  });
}

class ChatMessageEvent {
  final Map<String, dynamic> message;

  const ChatMessageEvent(this.message);
}

class ChatRealtimeService {
  ChatRealtimeService._();

  static final ChatRealtimeService instance = ChatRealtimeService._();

  final Set<String> _onlineUsernames = <String>{};
  final StreamController<Set<String>> _onlineUsersController =
      StreamController<Set<String>>.broadcast();
  final StreamController<ChatPresenceEvent> _presenceController =
      StreamController<ChatPresenceEvent>.broadcast();
  final StreamController<ChatTypingEvent> _typingController =
      StreamController<ChatTypingEvent>.broadcast();
  final StreamController<ChatMessageEvent> _messageController =
      StreamController<ChatMessageEvent>.broadcast();

  io.Socket? _socket;

  Stream<Set<String>> get onlineUsers => _onlineUsersController.stream;
  Stream<ChatPresenceEvent> get presenceEvents => _presenceController.stream;
  Stream<ChatTypingEvent> get typingEvents => _typingController.stream;
  Stream<ChatMessageEvent> get messageEvents => _messageController.stream;
  Set<String> get currentOnlineUsernames =>
      Set<String>.unmodifiable(_onlineUsernames);

  bool get isConnected => _socket?.connected == true;

  bool isOnline(String username) {
    return _onlineUsernames.contains(_normalizeUsername(username));
  }

  Future<void> connect() async {
    final token = AuthService().token;
    if (token == null || token.isEmpty) return;

    final existing = _socket;
    if (existing != null && existing.connected) return;

    existing?.dispose();
    final origin = ApiConstants.apiHost.replaceFirst(RegExp(r'/api$'), '');
    final socket = io.io(
      origin,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .setPath('/socket.io')
          .enableReconnection()
          .setReconnectionAttempts(5)
          .disableAutoConnect()
          .setAuth({
            'token': token,
            'username': AuthService().username ?? '',
          })
          .build(),
    );

    _socket = socket;
    _bindSocket(socket);
    socket.connect();
  }

  void disconnect() {
    final socket = _socket;
    _socket = null;
    socket?.disconnect();
    socket?.dispose();
    _onlineUsernames.clear();
    _emitOnlineUsers();
  }

  void joinChat(String targetUsername) {
    _socket?.emit('chat:join', {'targetUsername': targetUsername});
  }

  void leaveChat(String targetUsername) {
    _socket?.emit('chat:leave', {'targetUsername': targetUsername});
  }

  void sendTyping({
    required String targetUsername,
    required bool isTyping,
  }) {
    _socket?.emit('chat:typing', {
      'targetUsername': targetUsername,
      'isTyping': isTyping,
    });
  }

  void _bindSocket(io.Socket socket) {
    socket.onConnect((_) {
      final username = AuthService().username;
      if (username != null && username.isNotEmpty) {
        _onlineUsernames.add(_normalizeUsername(username));
        _emitOnlineUsers();
      }
    });

    socket.onDisconnect((_) {
      _onlineUsernames.clear();
      _emitOnlineUsers();
    });

    socket.on('presence:snapshot', (data) {
      _onlineUsernames
        ..clear()
        ..addAll(_parseOnlineSnapshot(data));
      _emitOnlineUsers();
    });

    socket.on('presence:changed', (data) {
      final payload = _asMap(data);
      final username = payload['username']?.toString() ?? '';
      if (username.isEmpty) return;

      final normalized = _normalizeUsername(username);
      final isOnline = payload['isOnline'] == true;
      if (isOnline) {
        _onlineUsernames.add(normalized);
      } else {
        _onlineUsernames.remove(normalized);
      }

      _presenceController.add(
        ChatPresenceEvent(username: username, isOnline: isOnline),
      );
      _emitOnlineUsers();
    });

    socket.on('chat:typing', (data) {
      final payload = _asMap(data);
      final senderUsername = payload['senderUsername']?.toString() ?? '';
      final targetUsername = payload['targetUsername']?.toString() ?? '';
      if (senderUsername.isEmpty || targetUsername.isEmpty) return;

      _typingController.add(
        ChatTypingEvent(
          senderUsername: senderUsername,
          targetUsername: targetUsername,
          isTyping: payload['isTyping'] == true,
        ),
      );
    });

    socket.on('chat:message', (data) {
      final message = _asMap(data);
      if (message.isEmpty) return;
      _messageController.add(ChatMessageEvent(message));
    });
  }

  Set<String> _parseOnlineSnapshot(dynamic data) {
    if (data is! List) return <String>{};

    return data
        .map(_asMap)
        .where((item) => item['isOnline'] == true)
        .map((item) => _normalizeUsername(item['username']?.toString() ?? ''))
        .where((username) => username.isNotEmpty)
        .toSet();
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  String _normalizeUsername(String username) => username.trim().toLowerCase();

  void _emitOnlineUsers() {
    _onlineUsersController.add(Set<String>.unmodifiable(_onlineUsernames));
  }
}
