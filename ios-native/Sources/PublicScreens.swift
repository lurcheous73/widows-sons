import SwiftUI

struct ChapterHome: View {
  let store: ChapterStore
  @Binding var selection: ChapterTab
  var body: some View {
    ChapterScroll(refresh: store.refresh) {
      ChapterHero { selection = .rides }
      if store.feed?.chapter.features.membership != false {
        ChapterCard {
          VStack(alignment: .leading, spacing: 16) {
            Eyebrow("Ride together. Stay connected.")
            Text("The chapter, within reach.").font(Heritage.cardTitle).foregroundStyle(
              Heritage.paper)
            Text("Member messages, the intercom and your live ride, together in one place.")
              .foregroundStyle(Heritage.muted)
            Button {
              selection = .comms
            } label: {
              Label("Open communications", systemImage: "bubble.left.and.bubble.right")
            }.buttonStyle(BrassButtonStyle(outlined: true)).accessibilityIdentifier("home.comms")
          }
        }
      }
      if store.feed?.chapter.features.news != false {
        VStack(spacing: 12) {
          SectionHeading(title: "From the chapter", actionTitle: "All news") { selection = .news }
          if let article = store.feed?.news.first {
            ArticleCard(article: article)
          } else {
            EmptyChapterCard(
              symbol: "newspaper", title: "Stories from the road.",
              message: "Chapter news will appear here as updates are published.")
          }
        }
      }
      if store.feed?.chapter.features.events != false {
        VStack(spacing: 12) {
          SectionHeading(title: "Coming up", actionTitle: "View rides") { selection = .rides }
          if let event = store.feed?.events.first {
            EventCard(event: event, response: store.member?.rsvps[event.id])
          } else {
            EmptyChapterCard(
              symbol: "road.lanes", title: "The next ride starts here.",
              message:
                "Confirmed rides and public events will appear here. Pull down to check for updates."
            )
          }
        }
      }
      if store.feed?.chapter.features.membership != false {
        ChapterCard {
          VStack(alignment: .leading, spacing: 16) {
            Eyebrow("Part of something")
            Text("Your chapter in your pocket.").font(Heritage.cardTitle).foregroundStyle(
              Heritage.paper)
            Text("Your member card, chapter news and the next ride, together in one place.")
              .foregroundStyle(Heritage.muted)
            Button {
              selection = .member
            } label: {
              Label(
                store.isSignedIn ? "Your membership" : "I have an invitation",
                systemImage: "person.text.rectangle")
            }
            .buttonStyle(BrassButtonStyle(outlined: true))
          }
        }
      }
      DevelopmentFooter()
    }
  }
}

struct ArticleCard: View {
  let article: ChapterArticle
  var body: some View {
    NavigationLink(value: ChapterRoute.article(article)) {
      ChapterCard {
        VStack(alignment: .leading, spacing: 14) {
          Eyebrow(article.publishedAt.formatted(.dateTime.day().month(.wide).year()))
          Text(article.title).font(Heritage.cardTitle).foregroundStyle(Heritage.paper).fixedSize(
            horizontal: false, vertical: true)
          Text(article.excerpt).font(.body).foregroundStyle(Heritage.muted).lineSpacing(4)
            .lineLimit(3)
          HStack {
            Text("Read the story").font(.subheadline.weight(.semibold))
            Spacer(minLength: 12)
            Image(systemName: "arrow.right").accessibilityHidden(true)
          }.foregroundStyle(Heritage.brass).padding(.top, 4)
        }
      }
    }.buttonStyle(.plain).accessibilityIdentifier("article.\(article.id)")
  }
}

struct NewsScreen: View {
  let store: ChapterStore
  @State private var query = ""
  private var articles: [ChapterArticle] {
    let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return (store.feed?.news ?? []).filter {
      search.isEmpty || "\($0.title) \($0.body)".localizedCaseInsensitiveContains(search)
    }
  }
  var body: some View {
    ChapterScroll(refresh: store.refresh) {
      ScreenHeading(
        eyebrow: "The chapter journal", title: "News & stories.",
        message: "The people, places and good causes that bring us together.")
      HStack(spacing: 12) {
        Image(systemName: "magnifyingglass").foregroundStyle(Heritage.muted).accessibilityHidden(
          true)
        TextField("Search chapter news", text: $query).textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .accessibilityIdentifier("news.search")
      }.padding(16).background(Heritage.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Heritage.line, lineWidth: 1))
      if articles.isEmpty {
        EmptyChapterCard(
          symbol: "newspaper",
          title: query.isEmpty ? "A new chapter awaits." : "No matching stories.",
          message: query.isEmpty
            ? "Published news will appear here automatically."
            : "Try another word or clear your search.")
      }
      ForEach(articles) { article in ArticleCard(article: article) }
      DevelopmentFooter()
    }
  }
}

struct RidesScreen: View {
  let store: ChapterStore
  @State private var onlyMyRides = false
  private var events: [ChapterEvent] {
    (store.feed?.events ?? []).filter {
      !onlyMyRides || [.going, .interested].contains(store.member?.rsvps[$0.id])
    }
  }
  var body: some View {
    ChapterScroll(refresh: store.refresh) {
      ScreenHeading(
        eyebrow: "The road ahead", title: "Rides & events.",
        message: "Find a ride, make a plan and let the chapter know you’re coming.")
      if store.member != nil {
        Picker("Rides", selection: $onlyMyRides) {
          Text("Upcoming").tag(false)
          Text("My rides").tag(true)
        }.pickerStyle(.segmented)
      }
      if events.isEmpty {
        EmptyChapterCard(
          symbol: "road.lanes",
          title: onlyMyRides ? "Your next ride is waiting." : "See you on the next one.",
          message: onlyMyRides
            ? "Choose Going or Interested on a ride to see it here."
            : "The chapter hasn’t published its next dates yet. Confirmed rides and events will appear here."
        )
      }
      ForEach(events) { event in EventCard(event: event, response: store.member?.rsvps[event.id]) }
      Text(
        "Times are shown in the chapter’s local time. Check the latest details before setting off."
      )
      .font(.footnote).foregroundStyle(Heritage.muted)
      DevelopmentFooter()
    }
  }
}

struct EventCard: View {
  let event: ChapterEvent
  let response: RSVPResponse?
  var body: some View {
    NavigationLink(value: ChapterRoute.event(event)) {
      ChapterCard {
        VStack(alignment: .leading, spacing: 14) {
          Eyebrow(event.dateLabel)
          Text(event.title).font(Heritage.cardTitle).foregroundStyle(Heritage.paper)
          if !event.location.isEmpty {
            Label(event.location, systemImage: "mappin.and.ellipse").font(.subheadline)
              .foregroundStyle(Heritage.muted)
          }
          HStack {
            Text(response?.title ?? "Ride details").font(.subheadline.weight(.semibold))
            Spacer(minLength: 12)
            Image(systemName: "arrow.right").accessibilityHidden(true)
          }.foregroundStyle(Heritage.brass)
        }
      }
    }.buttonStyle(.plain).accessibilityIdentifier("event.\(event.id)")
  }
}

struct ArticleScreen: View {
  let article: ChapterArticle
  var body: some View {
    ReadingScreen(
      title: article.title,
      eyebrow: article.publishedAt.formatted(.dateTime.day().month(.wide).year()),
      bodyText: article.body, website: article.url)
  }
}

struct ReadingScreen: View {
  let title: String
  let eyebrow: String
  let bodyText: String
  let website: URL?
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Eyebrow(eyebrow)
        Text(title).font(Heritage.hero).accessibilityAddTraits(.isHeader)
        Rectangle().fill(Heritage.brass).frame(height: 1)
        Text(bodyText).font(.body).lineSpacing(7).textSelection(.enabled)
        if let website = ApprovedWebsite.link(website) {
          Link(destination: website) {
            Label("Open chapter website", systemImage: "arrow.up.right.square")
          }
          .buttonStyle(BrassButtonStyle(outlined: true))
        }
      }.foregroundStyle(Heritage.paper).frame(maxWidth: 712, alignment: .leading).padding(26).frame(
        maxWidth: .infinity)
    }.background(Heritage.ink).toolbarBackground(Heritage.ink, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar).navigationBarTitleDisplayMode(.inline)
  }
}

struct ScreenHeading: View {
  let eyebrow: String
  let title: String
  let message: String
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Eyebrow(eyebrow)
      Text(title).font(Heritage.hero).foregroundStyle(Heritage.paper).accessibilityAddTraits(
        .isHeader)
      Text(message).foregroundStyle(Heritage.muted).lineSpacing(5)
    }
  }
}

enum ApprovedWebsite {
  static func link(_ url: URL?) -> URL? {
    guard let url, url.scheme == "https", url.host == "wsmba.the-grange.uk", url.user == nil,
      url.password == nil
    else { return nil }
    return url
  }
}

struct DevelopmentFooter: View {
  var body: some View {
    #if DEBUG
      Text("WIDOWS SONS  /  SWIFTUI DEVELOPMENT")
        .font(.caption2).tracking(1.4).foregroundStyle(Heritage.muted).frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    #endif
  }
}
