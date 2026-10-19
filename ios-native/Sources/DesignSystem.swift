import SwiftUI

enum Heritage {
  static let ink = Color(hex: "111820")
  static let panel = Color(hex: "1b242d")
  static let brass = Color(hex: "c49a59")
  static let paper = Color(hex: "f4f0e8")
  static let muted = Color(hex: "b8c0c5")
  static let line = Color(hex: "35404a")
  static let hero = Font.custom("Georgia", size: 38, relativeTo: .largeTitle)
  static let title = Font.custom("Georgia", size: 30, relativeTo: .title)
  static let cardTitle = Font.custom("Georgia", size: 24, relativeTo: .title2)
}

extension Color {
  init(hex: String) {
    let value =
      UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xc49a59
    self.init(
      .sRGB, red: Double((value >> 16) & 255) / 255,
      green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
  }
}

struct Eyebrow: View {
  let title: String
  init(_ title: String) { self.title = title }
  var body: some View {
    Text(title.uppercased()).font(.caption2.weight(.bold)).tracking(1.8)
      .foregroundStyle(Heritage.brass).fixedSize(horizontal: false, vertical: true)
  }
}

struct ChapterCard<Content: View>: View {
  let content: Content
  init(@ViewBuilder content: () -> Content) { self.content = content() }
  var body: some View {
    content.frame(maxWidth: .infinity, alignment: .leading).padding(22)
      .background(Heritage.panel, in: RoundedRectangle(cornerRadius: 20))
      .overlay(RoundedRectangle(cornerRadius: 20).stroke(Heritage.line, lineWidth: 1))
  }
}

struct ChapterScroll<Content: View>: View {
  let content: Content
  let refresh: @MainActor () async -> Void
  init(refresh: @escaping @MainActor () async -> Void, @ViewBuilder content: () -> Content) {
    self.refresh = refresh
    self.content = content()
  }
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 24) { content }
        .frame(maxWidth: 712, alignment: .leading).padding(.horizontal, 24).padding(.top, 12)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity)
    }
    .refreshable { await refresh() }
    .background(Heritage.ink)
  }
}

struct BrassButtonStyle: ButtonStyle {
  var outlined = false
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.subheadline.weight(.semibold))
      .foregroundStyle(outlined ? Heritage.brass : Heritage.ink)
      .frame(minHeight: 24).padding(.horizontal, 20).padding(.vertical, 14)
      .background(
        outlined ? Heritage.panel : Heritage.brass, in: RoundedRectangle(cornerRadius: 12)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12).stroke(
          outlined ? Heritage.line : Heritage.brass, lineWidth: 1)
      )
      .opacity(configuration.isPressed ? 0.7 : 1)
  }
}

struct EmptyChapterCard: View {
  let symbol: String
  let title: String
  let message: String
  var body: some View {
    ChapterCard {
      VStack(alignment: .leading, spacing: 14) {
        Image(systemName: symbol).font(.title).foregroundStyle(Heritage.brass).accessibilityHidden(
          true)
        Text(title).font(Heritage.cardTitle).foregroundStyle(Heritage.paper)
        Text(message).font(.body).foregroundStyle(Heritage.muted).lineSpacing(4)
      }
    }
  }
}

struct SectionHeading: View {
  let title: String
  let actionTitle: String
  let action: () -> Void
  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 16) {
      Text(title).font(.title3.weight(.semibold)).foregroundStyle(Heritage.paper)
      Spacer(minLength: 0)
      Button(actionTitle, action: action).font(.subheadline.weight(.semibold))
        .foregroundStyle(Heritage.brass).frame(minHeight: 44)
    }
  }
}

struct ConnectionNotice: View {
  let message: String
  let retry: () -> Void
  var body: some View {
    ChapterCard {
      VStack(alignment: .leading, spacing: 14) {
        Text(message).foregroundStyle(Heritage.muted)
        Button("Try again", action: retry).buttonStyle(BrassButtonStyle(outlined: true))
      }
    }
  }
}

struct RoadRibbon: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.width * 1.1, y: -30))
    path.addCurve(
      to: CGPoint(x: rect.width * 0.82, y: rect.height * 0.86),
      control1: CGPoint(x: rect.width * 0.5, y: rect.height * 0.26),
      control2: CGPoint(x: rect.width * 1.2, y: rect.height * 0.5))
    path.addQuadCurve(
      to: CGPoint(x: rect.width, y: rect.height * 1.2),
      control: CGPoint(x: rect.width * 0.7, y: rect.height))
    return path
  }
}

struct ChapterHero: View {
  let showRides: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      Eyebrow("Leicestershire & Rutland")
      Text("Good roads.\nBetter company.").font(Heritage.hero).foregroundStyle(Heritage.paper)
        .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
      Text("Motorcycling · Friendship · Charity")
        .font(.subheadline).foregroundStyle(Heritage.muted).lineSpacing(4)
      Button(action: showRides) {
        Label("See our rides", systemImage: "arrow.right")
      }.buttonStyle(BrassButtonStyle())
    }
    .frame(maxWidth: .infinity, alignment: .leading).padding(26)
    .background {
      ZStack {
        Heritage.panel
        RoadRibbon().stroke(Heritage.brass.opacity(0.07), lineWidth: 65)
        RoadRibbon().stroke(
          Heritage.brass.opacity(0.28), style: StrokeStyle(lineWidth: 1.5, dash: [8, 12]))
      }.accessibilityHidden(true)
    }
    .clipShape(RoundedRectangle(cornerRadius: 24))
    .overlay(RoundedRectangle(cornerRadius: 24).stroke(Heritage.line, lineWidth: 1))
  }
}
