import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'chapter_state.dart';
import 'data.dart';

const ink = Color(0xff111820);
const panel = Color(0xff1b242d);
const brass = Color(0xffc5a365);
const paper = Color(0xfff4f0e8);
const muted = Color(0xffb8c0c5);
const line = Color(0xff35404a);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = ChapterState(ChapterApi(), DeviceStorage());
  runApp(WidowsSonsApp(state: state));
  unawaited(state.initialize());
}

Color chapterAccent(ChapterFeed? feed) {
  final raw = (feed?.chapter['theme'] as Map?)?['accent'];
  if (raw is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(raw)) {
    return Color(int.parse('ff${raw.substring(1)}', radix: 16));
  }
  return brass;
}

class WidowsSonsApp extends StatelessWidget {
  final ChapterState state;
  const WidowsSonsApp({super.key, required this.state});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      final accent = chapterAccent(state.feed);
      return MaterialApp(
        title: 'Widows Sons',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: ink,
          colorScheme: ColorScheme.fromSeed(
            seedColor: accent,
            brightness: Brightness.dark,
            primary: accent,
            onPrimary: ink,
            surface: ink,
            onSurface: paper,
          ),
          textTheme: const TextTheme(
            headlineLarge: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 38,
              height: 1.1,
              color: paper,
            ),
            headlineMedium: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 30,
              height: 1.2,
              color: paper,
            ),
            headlineSmall: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 24,
              height: 1.25,
              color: paper,
            ),
            titleLarge: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: paper,
            ),
            bodyLarge: TextStyle(fontSize: 17, height: 1.6, color: paper),
            bodyMedium: TextStyle(fontSize: 15, height: 1.55, color: muted),
            labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: ink,
            foregroundColor: paper,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 52),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 50),
              side: const BorderSide(color: line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: panel,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.all(18),
          ),
          dividerColor: line,
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: ink,
            indicatorColor: accent.withValues(alpha: .16),
            labelTextStyle: const WidgetStatePropertyAll(
              TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        home: ChapterShell(state: state),
      );
    },
  );
}

class ChapterShell extends StatefulWidget {
  final ChapterState state;
  const ChapterShell({super.key, required this.state});
  @override
  State<ChapterShell> createState() => _ChapterShellState();
}

class _ChapterShellState extends State<ChapterShell>
    with WidgetsBindingObserver {
  int tab = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !widget.state.loading) {
      unawaited(widget.state.refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final pages = [
      HomePage(state: state, selectTab: (value) => setState(() => tab = value)),
      RidesPage(state: state),
      NewsPage(state: state),
      MemberPage(state: state),
    ];
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 78,
        titleSpacing: 24,
        title: Row(
          children: [
            Semantics(
              label: 'Widows Sons',
              image: true,
              child: Container(
                width: 43,
                height: 43,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  'WS',
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 19,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'WIDOWS SONS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      letterSpacing: 2.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    state.feed?.name.replaceFirst('Widows Sons ', '') ??
                        'Leicestershire & Rutland',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'About the chapter',
            onPressed: () => openAbout(context, state),
            icon: const Icon(Icons.info_outline),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            if (state.loading) const LinearProgressIndicator(minHeight: 2),
            if (state.offline && state.feed != null)
              Container(
                width: double.infinity,
                color: panel,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 9,
                ),
                child: Text(
                  'Offline reading · saved ${dateLabel(state.feed!.updatedAt, time: true)}',
                  style: const TextStyle(fontSize: 12, color: brass),
                ),
              ),
            Expanded(child: pages[tab]),
          ],
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: line)),
        ),
        child: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (value) => setState(() => tab = value),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Chapter',
            ),
            NavigationDestination(
              icon: Icon(Icons.route_outlined),
              selectedIcon: Icon(Icons.route),
              label: 'Rides',
            ),
            NavigationDestination(
              icon: Icon(Icons.article_outlined),
              selectedIcon: Icon(Icons.article),
              label: 'News',
            ),
            NavigationDestination(
              icon: Icon(Icons.badge_outlined),
              selectedIcon: Icon(Icons.badge),
              label: 'Member',
            ),
          ],
        ),
      ),
    );
  }
}

class PageList extends StatelessWidget {
  final ChapterState state;
  final List<Widget> children;
  const PageList({super.key, required this.state, required this.children});
  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: state.refresh,
    child: LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: constraints.maxWidth > 760
              ? (constraints.maxWidth - 712) / 2
              : 24,
          vertical: 14,
        ),
        children: [
          if (state.feed == null && state.feedError != null)
            Notice(
              text: state.feedError!,
              action: 'Try again',
              onAction: state.refresh,
            ),
          ...children,
          if (kDebugMode)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'WIDOWS SONS  /  DEVELOPMENT BUILD',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  color: muted,
                ),
              ),
            ),
          const SizedBox(height: 20),
        ],
      ),
    ),
  );
}

class HomePage extends StatelessWidget {
  final ChapterState state;
  final ValueChanged<int> selectTab;
  const HomePage({super.key, required this.state, required this.selectTab});
  @override
  Widget build(BuildContext context) {
    final news = state.feed?.news ?? [];
    final events = state.feed?.events ?? [];
    return PageList(
      state: state,
      children: [
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: line),
          ),
          child: Stack(
            children: [
              const Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: RoadPainter()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(25),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('LEICESTERSHIRE & RUTLAND'),
                    const SizedBox(height: 22),
                    Text(
                      'Good roads.\nBetter company.',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Your chapter, together.\nOn the road and beyond.',
                      style: TextStyle(fontSize: 16, color: muted, height: 1.6),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => selectTab(1),
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.arrow_forward, size: 19),
                      label: const Text('Find your next ride'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 27),
        SectionTitle(
          'From the chapter',
          action: 'All news',
          onAction: () => selectTab(2),
        ),
        const SizedBox(height: 12),
        if (news.isNotEmpty)
          NewsCard(article: news.first)
        else
          const EmptyCard(
            icon: Icons.article_outlined,
            title: 'Stories from the road.',
            body: 'Chapter news will appear here as updates are published.',
          ),
        const SizedBox(height: 27),
        SectionTitle(
          'Coming up',
          action: 'View rides',
          onAction: () => selectTab(1),
        ),
        const SizedBox(height: 12),
        if (events.isNotEmpty)
          EventCard(event: events.first, state: state)
        else
          const EmptyCard(
            icon: Icons.route_outlined,
            title: 'The next ride starts here.',
            body: 'Confirmed rides and public events will appear here. Pull down to check for updates.',
          ),
        const SizedBox(height: 22),
        CardBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('PART OF SOMETHING'),
              const SizedBox(height: 12),
              Text(
                state.verified
                    ? 'Welcome back, ${state.member!['display_name']}.'
                    : 'Your chapter in your pocket.',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              Text(
                state.verified ? 'Your member card and ride RSVPs are ready.' : 'Already a member? Use your chapter invitation to activate your member card and RSVP to rides.',
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => selectTab(3),
                icon: const Icon(Icons.badge_outlined),
                label: Text(
                  state.verified
                      ? 'Open your member card'
                      : 'I have an invitation',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class NewsPage extends StatefulWidget {
  final ChapterState state;
  const NewsPage({super.key, required this.state});
  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final articles = (widget.state.feed?.news ?? [])
        .where(
          (e) => '${e['title']} ${e['body']}'.toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();
    return PageList(
      state: widget.state,
      children: [
        const Eyebrow('THE CHAPTER JOURNAL'),
        const SizedBox(height: 10),
        Text(
          'News & stories.',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 10),
        const Text(
          'The people, places and good causes that bring us together.',
        ),
        const SizedBox(height: 22),
        TextField(
          onChanged: (value) => setState(() => query = value),
          decoration: const InputDecoration(
            labelText: 'Search chapter news',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 20),
        if (articles.isEmpty)
          EmptyCard(
            icon: Icons.article_outlined,
            title: query.isEmpty
                ? 'A new chapter awaits.'
                : 'No matching stories.',
            body: query.isEmpty
                ? 'Published news will appear here automatically.'
                : 'Try a different word or clear your search.',
          ),
        for (final article in articles)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: NewsCard(article: article),
          ),
      ],
    );
  }
}

class NewsCard extends StatelessWidget {
  final Map<String, dynamic> article;
  const NewsCard({super.key, required this.article});
  @override
  Widget build(BuildContext context) => CardBox(
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReadingPage(
          title: article['title'],
          body: article['body'],
          eyebrow: dateLabel(DateTime.parse(article['published_at'])),
          url: article['url'],
        ),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(
          dateLabel(DateTime.parse(article['published_at'])).toUpperCase(),
        ),
        const SizedBox(height: 12),
        Text(
          article['title'],
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        Text(article['excerpt'], maxLines: 3, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 20),
        const Row(
          children: [
            Expanded(
              child: Text(
                'Read the story',
                style: TextStyle(color: brass, fontWeight: FontWeight.w600),
              ),
            ),
            Icon(Icons.arrow_forward, color: brass, size: 20),
          ],
        ),
      ],
    ),
  );
}

class RidesPage extends StatefulWidget {
  final ChapterState state;
  const RidesPage({super.key, required this.state});
  @override
  State<RidesPage> createState() => _RidesPageState();
}

class _RidesPageState extends State<RidesPage> {
  bool mine = false;
  @override
  Widget build(BuildContext context) {
    final responses = Map<String, dynamic>.from(
      widget.state.member?['rsvps'] ?? {},
    );
    final events = (widget.state.feed?.events ?? [])
        .where(
          (event) =>
              !mine || ['going', 'interested'].contains(responses[event['id']]),
        )
        .toList();
    return PageList(
      state: widget.state,
      children: [
        const Eyebrow('THE ROAD AHEAD'),
        const SizedBox(height: 10),
        Text(
          'Rides & events.',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 10),
        const Text(
          'Find a ride, make a plan and let the chapter know you’re coming.',
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          children: [
            ChoiceChip(
              label: const Text('Upcoming'),
              selected: !mine,
              onSelected: (_) => setState(() => mine = false),
            ),
            if (widget.state.verified)
              ChoiceChip(
                label: const Text('My rides'),
                selected: mine,
                onSelected: (_) => setState(() => mine = true),
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (events.isEmpty)
          EmptyCard(
            icon: Icons.route_outlined,
            title: mine
                ? 'Your next ride is waiting.'
                : 'See you on the next one.',
            body: mine
                ? 'Choose Going or Interested on a ride to see it here.'
                : 'The chapter hasn’t published its next dates yet. Confirmed rides and events will appear here.',
          ),
        for (final event in events)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: EventCard(event: event, state: widget.state),
          ),
        const SizedBox(height: 22),
        const Text(
          'Times are shown in the chapter’s local time. Check the latest details before setting off.',
          style: TextStyle(fontSize: 13, color: muted),
        ),
      ],
    );
  }
}

class EventCard extends StatelessWidget {
  final Map<String, dynamic> event;
  final ChapterState state;
  const EventCard({super.key, required this.event, required this.state});
  @override
  Widget build(BuildContext context) => CardBox(
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventPage(event: event, state: state),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(eventDate(event['starts_at']).toUpperCase()),
        const SizedBox(height: 12),
        Text(event['title'], style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        if ((event['location'] as String? ?? '').isNotEmpty)
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 18, color: muted),
              const SizedBox(width: 6),
              Expanded(child: Text(event['location'])),
            ],
          ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                responseLabel(state.member?['rsvps']?[event['id']]) ??
                    'Ride details',
                style: const TextStyle(
                  color: brass,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.arrow_forward, color: brass, size: 20),
          ],
        ),
      ],
    ),
  );
}

class EventPage extends StatelessWidget {
  final Map<String, dynamic> event;
  final ChapterState state;
  const EventPage({super.key, required this.event, required this.state});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      final current = state.member?['rsvps']?[event['id']];
      return Scaffold(
        appBar: AppBar(title: const Text('Ride details')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Eyebrow('RIDE TOGETHER'),
              const SizedBox(height: 14),
              Text(
                event['title'],
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 24),
              InfoRow(
                icon: Icons.calendar_today_outlined,
                text: eventDate(event['starts_at']),
              ),
              if ((event['location'] as String? ?? '').isNotEmpty)
                InfoRow(icon: Icons.place_outlined, text: event['location']),
              const SizedBox(height: 22),
              SelectableText(
                event['description'] ?? '',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 28),
              CardBox(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Coming along?',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 10),
                    if (state.verified) ...[
                      Text(
                        current == null
                            ? 'Let the chapter know your plans.'
                            : 'Your response: ${responseLabel(current)}',
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final value in [
                            'going',
                            'interested',
                            'not_going',
                          ])
                            ChoiceChip(
                              label: Text(responseLabel(value)!),
                              selected: current == value,
                              onSelected: state.busy
                                  ? null
                                  : (_) async {
                                      final error = await state.respond(
                                        event['id'],
                                        value,
                                      );
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              error ??
                                                  'Your RSVP has been saved.',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                            ),
                        ],
                      ),
                      if (state.busy)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: LinearProgressIndicator(),
                        ),
                    ] else
                      const Text(
                        'Activate your membership in the Member tab to RSVP. Your sign-in must be verified online.',
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: () => openWebsite(context, event['url']),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('View on the chapter website'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class MemberPage extends StatefulWidget {
  final ChapterState state;
  const MemberPage({super.key, required this.state});
  @override
  State<MemberPage> createState() => _MemberPageState();
}

class _MemberPageState extends State<MemberPage> {
  final code = TextEditingController();
  final form = GlobalKey<FormState>();
  bool hidden = true;
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final member = state.member;
    return PageList(
      key: ValueKey(state.verified),
      state: state,
      children: [
        const Eyebrow('THE CLUBHOUSE'),
        const SizedBox(height: 10),
        Text(
          member == null ? 'You belong here.' : 'Your membership.',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 12),
        if (member != null) ...[
          const Text('Your chapter card, connected to your membership.'),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xff30363b), panel],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: brass),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.two_wheeler, color: brass, size: 29),
                    SizedBox(width: 16),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Eyebrow('MEMBER CARD'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                Text(
                  member['display_name'],
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(member['chapter'], style: const TextStyle(color: muted)),
                const SizedBox(height: 25),
                Row(
                  children: [
                    const Icon(Icons.verified_outlined, color: brass, size: 19),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Active ${member['membership_type']}',
                        style: const TextStyle(
                          color: brass,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Member ID  ${member['id'].toString().substring(0, 8).toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.3,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Verified online ${dateLabel(DateTime.parse(member['verified_at']), time: true)}. This card shows your chapter record; it is not a payment receipt.',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 26),
          CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your ride plans',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(
                  '${Map<String, dynamic>.from(member['rsvps']).values.where((v) => v == 'going').length} going · ${Map<String, dynamic>.from(member['rsvps']).values.where((v) => v == 'interested').length} interested',
                ),
                const SizedBox(height: 10),
                const Text(
                  'You can update your response from any ride’s details.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: state.busy
                ? null
                : () async {
                    final error = await state.signOut();
                    if (error != null && context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(error)));
                    }
                  },
            icon: const Icon(Icons.logout, size: 19),
            label: const Text('Sign out of this device'),
          ),
        ] else if (state.signedIn) ...[
          const SizedBox(height: 16),
          Notice(
            text:
                state.memberError ??
                'Connect to the chapter to verify your membership.',
            action: 'Verify membership',
            onAction: state.refreshMember,
          ),
          const SizedBox(height: 16),
          const Text(
            'Your member card is shown only after your membership is checked online.',
          ),
        ] else ...[
          const Text(
            'A little closer to the chapter. Activate your membership to carry your card and join the next ride.',
          ),
          const SizedBox(height: 25),
          CardBox(
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.mark_email_read_outlined,
                    size: 32,
                    color: brass,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Your invitation starts it.',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Paste the single-use invitation supplied privately by your chapter. New to the chapter? Get in touch first.',
                  ),
                  const SizedBox(height: 22),
                  TextFormField(
                    controller: code,
                    obscureText: hidden,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.none,
                    keyboardType: TextInputType.visiblePassword,
                    maxLength: 150,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    decoration: InputDecoration(
                      labelText: 'Chapter invitation',
                      hintText: 'wsi_…',
                      counterText: '',
                      suffixIcon: IconButton(
                        tooltip: hidden ? 'Show invitation' : 'Hide invitation',
                        onPressed: () => setState(() => hidden = !hidden),
                        icon: Icon(
                          hidden
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) =>
                        RegExp(r'^wsi_[A-Za-z0-9_-]{43}$')
                            .hasMatch(value?.trim() ?? '')
                        ? null
                        : 'Paste the complete invitation from your chapter.',
                  ),
                  if (state.memberError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(
                        state.memberError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: state.busy
                          ? null
                          : () async {
                              if (form.currentState!.validate()) {
                                FocusScope.of(context).unfocus();
                                await state.activate(code.text);
                                if (state.signedIn) code.clear();
                              }
                            },
                      child: Text(
                        state.busy
                            ? 'Checking invitation…'
                            : 'Activate my membership',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () =>
                openWebsite(context, 'https://wsmba.the-grange.uk/contact/'),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Speak to the chapter'),
          ),
          const SizedBox(height: 20),
          const Text(
            'Invitations expire after seven days. Your sign-in lasts up to 30 days; ask the chapter for a new invitation when it ends. An invitation for another device ends the previous sign-in.',
            style: TextStyle(fontSize: 13),
          ),
        ],
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const PrivacyPage())),
          icon: const Icon(Icons.shield_outlined, size: 18),
          label: const Text('Your privacy & app information'),
        ),
      ],
    );
  }
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});
  @override
  Widget build(BuildContext context) => const ReadingPage(
    title: 'Your chapter. Your privacy.',
    eyebrow: 'APP INFORMATION',
    body:
        'Public news and ride details are saved on this device for offline reading. Pull down on a page to refresh them. Saved information can be out of date.\n\n'
        'Your sign-in secret is kept in the device’s secure storage. Your member card and RSVP record are fetched from the chapter server and are not saved in the public offline cache.\n\n'
        'The chapter holds the name, email and membership details used to issue your invitation, plus your ride responses and an audit of account actions. Only your own membership and responses are available in this app.\n\n'
        'This development build does not collect location, microphone, contact or fitness data. Ride Guardian, SOS, intercom and private welfare services are not available in this build.\n\n'
        'To correct your details, request account deletion or discuss how long the chapter keeps records, contact the chapter using its website. Sign out to revoke this device’s access.\n\n'
        'Development version 0.3.0. This build is for chapter review; it has not been released through the App Store.',
    url: 'https://wsmba.the-grange.uk/contact/',
  );
}

void openAbout(BuildContext context, ChapterState state) {
  final about = state.feed?.pages
      .where((e) => e['slug'] == 'about')
      .firstOrNull;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ReadingPage(
        title: about?['title'] ?? 'A shared road ahead.',
        eyebrow: 'LEICESTERSHIRE & RUTLAND',
        body: about?['body'] ?? 'Motorcycling, friendship and the fellowship of Freemasonry. Connect to read more about the chapter.',
        url: about?['url'] ?? 'https://wsmba.the-grange.uk/about/',
      ),
    ),
  );
}

class ReadingPage extends StatelessWidget {
  final String title;
  final String body;
  final String eyebrow;
  final String? url;
  const ReadingPage({
    super.key,
    required this.title,
    required this.body,
    required this.eyebrow,
    this.url,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => ListView(
          padding: EdgeInsets.symmetric(
            horizontal: constraints.maxWidth > 760
                ? (constraints.maxWidth - 712) / 2
                : 26,
            vertical: 12,
          ),
          children: [
            Eyebrow(eyebrow.toUpperCase()),
            const SizedBox(height: 18),
            Text(title, style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 24),
            const Divider(color: brass),
            const SizedBox(height: 22),
            SelectableText(body, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 30),
            if (url != null)
              OutlinedButton.icon(
                onPressed: () => openWebsite(context, url!),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open chapter website'),
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    ),
  );
}

Future<void> openWebsite(BuildContext context, String value) async {
  final uri = Uri.tryParse(value);
  final valid =
      uri != null &&
      uri.scheme == 'https' &&
      uri.host == 'wsmba.the-grange.uk' &&
      uri.userInfo.isEmpty;
  try {
    if (!valid || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw const FormatException();
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The chapter website could not be opened. Please try again later.',
          ),
        ),
      );
    }
  }
}

String dateLabel(DateTime date, {bool time = false}) =>
    DateFormat(time ? 'd MMM, HH:mm' : 'd MMMM yyyy').format(date.toLocal());

String eventDate(String value) {
  // Preserve the published chapter wall-clock time and its explicit UTC offset.
  // Parsing directly to the device timezone would mislead members travelling abroad.
  final wallClock = DateTime.parse(value.substring(0, 19));
  final offset =
      RegExp(r'(Z|[+-]\d\d:\d\d)$').firstMatch(value)?.group(0) ?? '';
  return '${DateFormat('EEE d MMM yyyy · HH:mm').format(wallClock)} ${offset == 'Z' || offset == '+00:00' ? 'GMT' : 'UTC$offset'}';
}

String? responseLabel(dynamic value) => switch (value) {
  'going' => 'Going',
  'interested' => 'Interested',
  'not_going' => 'Not going',
  _ => null,
};

class CardBox extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const CardBox({super.key, required this.child, this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: panel,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: line),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(22), child: child),
    ),
  );
}

class Eyebrow extends StatelessWidget {
  final String text;
  const Eyebrow(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: Theme.of(context).colorScheme.primary,
      fontSize: 10,
      letterSpacing: 1.7,
      fontWeight: FontWeight.w700,
      height: 1.5,
    ),
  );
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String action;
  final VoidCallback onAction;
  const SectionTitle(
    this.title, {
    super.key,
    required this.action,
    required this.onAction,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      TextButton(onPressed: onAction, child: Text(action)),
    ],
  );
}

class EmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const EmptyCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });
  @override
  Widget build(BuildContext context) => CardBox(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: brass, size: 30),
        const SizedBox(height: 15),
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 10),
        Text(body),
      ],
    ),
  );
}

class Notice extends StatelessWidget {
  final String text;
  final String action;
  final VoidCallback onAction;
  const Notice({
    super.key,
    required this.text,
    required this.action,
    required this.onAction,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    ),
  );
}

class InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const InfoRow({super.key, required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: brass, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: const TextStyle(color: paper, fontSize: 16)),
        ),
      ],
    ),
  );
}

class RoadPainter extends CustomPainter {
  const RoadPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 1.12, -25)
      ..cubicTo(
        size.width * .48,
        size.height * .26,
        size.width * 1.2,
        size.height * .50,
        size.width * .80,
        size.height * .86,
      )
      ..quadraticBezierTo(
        size.width * .70,
        size.height * .98,
        size.width * .94,
        size.height * 1.2,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = brass.withValues(alpha: .07)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 70,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = brass.withValues(alpha: .17)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    for (final metric in path.computeMetrics()) {
      for (double distance = 0; distance < metric.length; distance += 22) {
        canvas.drawPath(
          metric.extractPath(distance, distance + 10),
          Paint()
            ..color = brass.withValues(alpha: .22)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
