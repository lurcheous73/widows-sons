import SwiftUI

@main
struct WidowsSonsApp: App {
  private let configuration: Result<AppConfiguration, Error>
  init() { configuration = Result { try AppConfiguration.bundled() } }
  var body: some Scene {
    WindowGroup {
      switch configuration {
      case .success(let configuration): NativeAppRoot(configuration: configuration)
      case .failure:
        ContentUnavailableView(
          "Chapter connection unavailable", systemImage: "network.slash",
          description: Text("Check the app connection settings before running this build."))
      }
    }
  }
}

struct NativeAppRoot: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var store: ChapterStore

  init(configuration: AppConfiguration) {
    self.store = ChapterStore.live(configuration: configuration)
  }
  var body: some View {
    ChapterShell(store: store)
      .preferredColorScheme(.dark).tint(Heritage.brass)
      .task(id: scenePhase) {
        if scenePhase == .active {
          await store.loadOrRefresh()
        } else {
          store.invalidateVerification()
        }
      }
      .overlay {
        if scenePhase != .active && store.isSignedIn {
          Heritage.ink.ignoresSafeArea().overlay {
            Label("Widows Sons", systemImage: "lock.fill").foregroundStyle(Heritage.brass)
          }
        }
      }
  }
}

enum ChapterTab: String, CaseIterable, Identifiable {
  case chapter = "Chapter"
  case rides = "Rides"
  case news = "News"
  case member = "Member"
  var id: String { rawValue }
  var symbol: String {
    switch self {
    case .chapter: "house"
    case .rides: "point.topleft.down.to.point.bottomright.curvepath"
    case .news: "newspaper"
    case .member: "person.text.rectangle"
    }
  }
}

enum ChapterRoute: Hashable {
  case article(ChapterArticle)
  case event(ChapterEvent)
  case page(ChapterPage)
  case privacy, licences
}

struct ChapterShell: View {
  let store: ChapterStore
  @State private var selection = ChapterTab.chapter
  @State private var path: [ChapterRoute] = []

  private var tabs: [ChapterTab] {
    guard let features = store.feed?.chapter.features else { return ChapterTab.allCases }
    return ChapterTab.allCases.filter {
      switch $0 {
      case .chapter: true
      case .rides: features.events
      case .news: features.news
      case .member: features.membership
      }
    }
  }

  var body: some View {
    NavigationStack(path: $path) {
      VStack(spacing: 0) {
        ChapterHeader(name: store.feed?.chapter.displayName ?? "Widows Sons L&R") {
          if let page = store.feed?.pages.first(where: { $0.slug == "about" }) {
            path.append(.page(page))
          }
        }
        if store.isLoading { ProgressView().tint(Heritage.brass).padding(.bottom, 8) }
        if store.isReadingSavedContent, let date = store.feed?.updatedAt {
          HStack {
            Image(systemName: "wifi.slash").accessibilityHidden(true)
            Text("Saved reading · \(date.formatted(date: .abbreviated, time: .shortened))")
          }.font(.caption).foregroundStyle(Heritage.brass)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(
              .vertical, 10
            ).background(Heritage.panel)
        }
        if store.feed == nil, let error = store.feedError {
          ConnectionNotice(message: error) { Task { await store.refresh() } }.padding(24)
        }
        Group {
          switch selection {
          case .chapter: ChapterHome(store: store, selection: $selection)
          case .rides: RidesScreen(store: store)
          case .news: NewsScreen(store: store)
          case .member: MemberScreen(store: store)
          }
        }.frame(maxHeight: .infinity)
      }
      .background(Heritage.ink)
      .toolbar(.hidden, for: .navigationBar)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        ChapterTabBar(tabs: tabs, selection: $selection)
      }
      .navigationDestination(for: ChapterRoute.self) { route in
        switch route {
        case .article(let article): ArticleScreen(article: article)
        case .event(let event): EventScreen(event: event, store: store)
        case .page(let page):
          ReadingScreen(
            title: page.title, eyebrow: "Leicestershire & Rutland", bodyText: page.body,
            website: page.url)
        case .privacy: PrivacyScreen()
        case .licences: LicencesScreen()
        }
      }
      .onChange(of: tabs) { _, updated in
        if !updated.contains(selection) { selection = .chapter }
      }
    }
    .background(Heritage.ink)
  }
}

struct ChapterHeader: View {
  let name: String
  let about: () -> Void
  var body: some View {
    HStack(spacing: 12) {
      Text("WS").font(.custom("Georgia", fixedSize: 19)).foregroundStyle(Heritage.brass)
        .frame(width: 43, height: 43)
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Heritage.brass, lineWidth: 1))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text("WIDOWS SONS").font(.subheadline.weight(.bold)).tracking(2).lineLimit(1)
        Text(name.replacingOccurrences(of: "Widows Sons ", with: ""))
          .font(.caption).foregroundStyle(Heritage.muted).lineLimit(1)
      }
      Spacer(minLength: 4)
      Button(action: about) {
        Image(systemName: "info.circle").font(.title3).frame(width: 44, height: 44)
      }
      .accessibilityLabel("About the chapter")
    }.foregroundStyle(Heritage.paper).padding(.horizontal, 24).padding(.vertical, 14)
  }
}

struct ChapterTabBar: View {
  let tabs: [ChapterTab]
  @Binding var selection: ChapterTab
  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      ForEach(tabs) { tab in
        Button {
          selection = tab
        } label: {
          VStack(spacing: 7) {
            Image(systemName: tab.symbol).font(
              .system(size: 21, weight: selection == tab ? .semibold : .regular)
            )
            .frame(width: 54, height: 30)
            .background(selection == tab ? Heritage.brass.opacity(0.15) : .clear, in: Capsule())
            Text(tab.rawValue).font(.caption2.weight(.medium))
          }.foregroundStyle(selection == tab ? Heritage.brass : Heritage.muted).frame(
            maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.plain).accessibilityIdentifier("tab.\(tab.id)")
        .accessibilityLabel(tab.rawValue)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
      }
    }.padding(.horizontal, 12).padding(.vertical, 10).background(Heritage.ink)
      .overlay(alignment: .top) { Rectangle().fill(Heritage.line).frame(height: 0.5) }
  }
}
