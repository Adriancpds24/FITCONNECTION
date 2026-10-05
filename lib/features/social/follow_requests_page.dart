import 'package:flutter/material.dart';
import '../../shared/themes/feed_palette.dart';
import 'social_state.dart';

class FollowRequestsPage extends StatelessWidget {
  const FollowRequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SocialState(),
      builder: (context, _) {
        final requests = SocialState().followRequests;

        return Scaffold(
          backgroundColor: FeedPalette.background,
          appBar: AppBar(
            title: Text(
              'Solicitudes de seguimiento',
              style: TextStyle(
                  color: FeedPalette.text, fontWeight: FontWeight.bold),
            ),
            backgroundColor: FeedPalette.background,
            elevation: 0,
            iconTheme: IconThemeData(color: FeedPalette.text),
          ),
          body: requests.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_add_disabled_outlined,
                          size: 64, color: FeedPalette.muted),
                      const SizedBox(height: 16),
                      Text(
                        'No tienes solicitudes pendientes',
                        style:
                            TextStyle(color: FeedPalette.muted, fontSize: 16),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    final r = requests[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: FeedPalette.panelDecoration(radius: 20),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundImage: NetworkImage(r['image']),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r['username'],
                                  style: TextStyle(
                                      color: FeedPalette.text,
                                      fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Quiere seguirte',
                                  style: TextStyle(
                                      color: FeedPalette.muted, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check_circle,
                                    color: Colors.green),
                                onPressed: () => SocialState()
                                    .acceptFollowRequest(r['username']),
                              ),
                              IconButton(
                                icon:
                                    const Icon(Icons.cancel, color: Colors.red),
                                onPressed: () => SocialState()
                                    .rejectFollowRequest(r['username']),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
