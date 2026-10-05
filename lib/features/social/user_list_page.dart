import 'package:flutter/material.dart';
import '../social/post_model.dart';
import '../profile/user_profile_page.dart';
import '../social/social_service.dart';
import '../social/social_state.dart';
import '../../core/utils/profile_avatar.dart';
import '../../shared/themes/feed_palette.dart';
import '../../shared/widgets/common/smart_image.dart';

class UserListPage extends StatefulWidget {
  final String title;
  final String username;
  final Future<List<Map<String, dynamic>>> Function(String) fetchUsers;

  const UserListPage({
    super.key,
    required this.title,
    required this.username,
    required this.fetchUsers,
  });

  @override
  State<UserListPage> createState() => _UserListPageState();
}

class _UserListPageState extends State<UserListPage> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  final SocialService _socialService = SocialService();
  final SocialState _socialState = SocialState();

  @override
  void initState() {
    super.initState();
    _initData();
    _socialState.addListener(_onSocialStateChanged);
  }

  Future<void> _initData() async {
    await _syncFollowingIfNeeded();
    await _loadUsers();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    await _socialState.syncFollowing(_socialState.currentUser.username);
    await _loadUsers();
  }

  Future<void> _syncFollowingIfNeeded() async {
    final myUsername = _socialState.currentUser.username;
    // Always sync if not already synced to ensure correct button states
    if (!_socialState.isSynced) {
      await _socialState.syncFollowing(myUsername);
    }
  }

  @override
  void dispose() {
    _socialState.removeListener(_onSocialStateChanged);
    super.dispose();
  }

  void _onSocialStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadUsers() async {
    try {
      final users = await widget.fetchUsers(widget.username);
      if (mounted) {
        setState(() {
          _users = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFollow(String username, bool currentState) async {
    try {
      if (currentState) {
        await _socialService.unfollowUser(username);
        _socialState.updateFollowStatus(username, false);
      } else {
        await _socialService.followUser(username);
        _socialState.updateFollowStatus(username, true);
      }

      // If we are showing "Following" list, we might want to refresh or keep them with "Follow" button
      // For now we just update the button state via SocialState listener
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Error al cambiar estado de seguimiento')),
        );
      }
    }
  }

  UserProfile _buildUserProfile(Map<String, dynamic> user) {
    final username = user['username']?.toString() ?? '';
    final displayName =
        (user['name'] ?? user['displayName'] ?? username).toString().trim();
    final imagePath =
        (user['imagePath'] ?? user['userImage'] ?? '').toString().trim();
    final bio = (user['bio'] ?? '').toString();
    final sport = (user['sport'] ?? '').toString();

    return UserProfile(
      username: username.isEmpty ? 'usuario' : username,
      displayName: displayName.isEmpty
          ? (username.isEmpty ? 'Usuario' : username)
          : displayName,
      userImage: ProfileAvatar.forPath(
          imagePath, displayName.isEmpty ? username : displayName),
      bio: bio.trim().isEmpty ? 'Sin biografía disponible.' : bio,
      sport: sport.trim().isEmpty ? 'Fitness' : sport,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: TextStyle(
            color: FeedPalette.text,
            fontWeight: FontWeight.w900,
          ),
        ),
        backgroundColor: FeedPalette.background,
        elevation: 0,
        iconTheme: IconThemeData(color: FeedPalette.text),
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: FeedPalette.screenGradient),
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: FeedPalette.accent),
            )
          : _users.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 64,
                        color: FeedPalette.muted,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No hay usuarios para mostrar',
                        style:
                            TextStyle(color: FeedPalette.muted, fontSize: 16),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: FeedPalette.accent,
                  onRefresh: _refresh,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _users.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      color: FeedPalette.border,
                    ),
                    itemBuilder: (context, index) {
                      final user = _users[index];
                      final targetUsername =
                          (user['username'] ?? '').toString();
                      final profile = _buildUserProfile(user);
                      final bool isFollowing = _socialState.isFollowing(
                        targetUsername,
                      );

                      final buttonStyle = (isFollowing)
                          ? ElevatedButton.styleFrom(
                              backgroundColor: FeedPalette.surfaceSoft,
                              foregroundColor: FeedPalette.text,
                              elevation: 0,
                              minimumSize: const Size(104, 38),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: FeedPalette.border),
                              ),
                            )
                          : ElevatedButton.styleFrom(
                              backgroundColor: FeedPalette.accent,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              minimumSize: const Size(104, 38),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            );

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          radius: 28,
                          backgroundColor: FeedPalette.surfaceSoft,
                          child: ClipOval(
                            child: SmartImage(
                              imageUrl: profile.userImage,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              errorWidget: Icon(
                                Icons.person,
                                color: FeedPalette.muted,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          profile.displayName,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: FeedPalette.text,
                          ),
                        ),
                        subtitle: Text(
                          '@${profile.username}',
                          style: TextStyle(color: FeedPalette.muted),
                        ),
                        trailing: ElevatedButton(
                          onPressed: () =>
                              _toggleFollow(profile.username, isFollowing),
                          style: buttonStyle,
                          child: Text(
                            isFollowing ? 'Siguiendo' : 'Seguir',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserProfilePage(
                                user: profile,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
    );
  }
}
