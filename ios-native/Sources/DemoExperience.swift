import AVFoundation
import Observation
import SwiftUI

private struct DemoChapterEnvironmentKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
  var isDemoChapter: Bool {
    get { self[DemoChapterEnvironmentKey.self] }
    set { self[DemoChapterEnvironmentKey.self] = newValue }
  }
}

enum DemoTourStep: String, CaseIterable, Identifiable {
  case chapter, ride, messages, tracking, guardians, sections, member
  var id: String { rawValue }
  var title: String {
    switch self {
    case .chapter: "Meet the chapter"
    case .ride: "Plan the Sunday ride"
    case .messages: "Send a chapter message"
    case .tracking: "Keep the ride together"
    case .guardians: "Handle a help request"
    case .sections: "Open the clubhouse"
    case .member: "Carry your membership"
    }
  }
  var detail: String {
    switch self {
    case .chapter: "Stories, upcoming rides and the Heritage & Road design."
    case .ride: "Change your RSVP, read the briefing and see the sample GPX route."
    case .messages: "Send a message. A clearly labelled demo reply follows."
    case .tracking: "See simulated riders on the map, opt in to sample sharing and check in."
    case .guardians: "Sam has a sample puncture. Acknowledge, respond and record the outcome."
    case .sections: "Read announcements, join a group, vote and add a comment."
    case .member: "A sample member card with your demo ride responses."
    }
  }
  var symbol: String {
    switch self {
    case .chapter: "house"
    case .ride: "point.topleft.down.to.point.bottomright.curvepath"
    case .messages: "bubble.left.and.bubble.right"
    case .tracking: "map"
    case .guardians: "checkmark.shield"
    case .sections: "person.3"
    case .member: "person.text.rectangle"
    }
  }
}

struct DemoControlBar: View {
  let tour: () -> Void
  let reset: () -> Void
  var body: some View {
    HStack(spacing: 8) {
      Label("DEMO · SAMPLE DATA", systemImage: "circle.inset.filled").font(.caption2.weight(.bold))
        .lineLimit(1).minimumScaleFactor(0.8)
      Spacer(minLength: 4)
      Button("Demo tour", systemImage: "play.circle", action: tour).font(.caption.weight(.semibold))
        .frame(minHeight: 44).accessibilityIdentifier("demo.tour")
      Button(action: reset) {
        Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44)
      }.accessibilityLabel("Reset demo").accessibilityIdentifier("demo.reset")
    }.foregroundStyle(Heritage.brass).padding(.horizontal, 16).background(Heritage.panel)
  }
}

struct DemoTourSheet: View {
  let open: (DemoTourStep) -> Void
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          ScreenHeading(
            eyebrow: "Widows Sons · product demo", title: "The chapter.\nReady to show.",
            message:
              "A populated, interactive Swift app. Pick a journey, make a change and reset whenever you want to start again."
          )
          ForEach(DemoTourStep.allCases) { step in
            Button {
              dismiss()
              open(step)
            } label: {
              ChapterCard {
                HStack(alignment: .top, spacing: 16) {
                  Image(systemName: step.symbol).font(.title2).foregroundStyle(Heritage.brass)
                    .frame(width: 30)
                  VStack(alignment: .leading, spacing: 8) {
                    Text(step.title).font(.headline).foregroundStyle(Heritage.paper)
                    Text(step.detail).font(.subheadline).foregroundStyle(Heritage.muted)
                  }
                  Spacer(minLength: 0)
                  Image(systemName: "chevron.right").foregroundStyle(Heritage.brass)
                }
              }
            }.buttonStyle(.plain).accessibilityIdentifier("demo.step.\(step.id)")
          }
          Text(
            "Names, messages, positions and help requests are fictional and stay inside this demo. The spoken briefing is an audio preview; live intercom and real CarPlay/headset tests use the connected build. No emergency, email or push is dispatched."
          ).font(.footnote).foregroundStyle(Heritage.muted)
        }.padding(24)
      }.background(Heritage.ink).navigationTitle("Demo tour").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
          Button("Back to the app") { dismiss() }.buttonStyle(BrassButtonStyle(outlined: true))
            .padding(16).frame(maxWidth: .infinity).background(Heritage.ink)
        }
    }.preferredColorScheme(.dark).tint(Heritage.brass)
  }
}

@MainActor @Observable
final class DemoBriefingAudio: NSObject, AVSpeechSynthesizerDelegate {
  private(set) var isPlaying = false
  private(set) var notice: String?
  @ObservationIgnored private let speech = AVSpeechSynthesizer()
  override init() {
    super.init()
    speech.delegate = self
  }
  func play() {
    stop()
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
      try session.setActive(true)
      let utterance = AVSpeechUtterance(
        string:
          "This is the Widows Sons demo ride briefing. Jamie is the Road Captain. Alex is the Sweep. We will regroup at the coffee stop. Keep a comfortable distance, and check in if you leave the group. This is an audio preview, not a live intercom call."
      )
      utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
      utterance.rate = AVSpeechUtteranceDefaultSpeechRate
      isPlaying = true
      notice = "Playing a sample briefing on this device. No microphone is used."
      speech.speak(utterance)
    } catch { notice = "Audio preview could not start. Check this device’s audio output." }
  }
  func stop() {
    speech.stopSpeaking(at: .immediate)
    isPlaying = false
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
  }
  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
  ) {
    Task { @MainActor [weak self] in
      guard let self, !self.speech.isSpeaking else { return }
      self.isPlaying = false
      try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
  }
}

struct DemoIntercomPreviewCard: View {
  @State private var audio = DemoBriefingAudio()
  var body: some View {
    ChapterCard {
      VStack(alignment: .leading, spacing: 16) {
        Eyebrow("A voice on the road")
        HStack {
          Text("Hear the ride briefing.").font(Heritage.cardTitle)
          Spacer()
          Image(systemName: audio.isPlaying ? "waveform" : "headphones").foregroundStyle(
            Heritage.brass)
        }
        Text("Spoken audio preview · no live call").font(.subheadline.weight(.semibold))
          .foregroundStyle(Heritage.brass)
        Text(
          "Play a sample briefing through this device or its paired audio output. Live group intercom is part of the connected app and needs two phones to demonstrate."
        ).font(.subheadline).foregroundStyle(Heritage.muted)
        Button(
          audio.isPlaying ? "Stop audio preview" : "Play briefing preview",
          systemImage: audio.isPlaying ? "stop.circle" : "play.circle"
        ) {
          if audio.isPlaying { audio.stop() } else { audio.play() }
        }.buttonStyle(BrassButtonStyle()).accessibilityIdentifier("demo.audio")
        if let notice = audio.notice {
          Text(notice).font(.footnote).foregroundStyle(Heritage.muted)
        }
        Label("CarPlay companion included in the connected build", systemImage: "carplay").font(
          .footnote
        ).foregroundStyle(Heritage.muted)
      }.foregroundStyle(Heritage.paper)
    }.onDisappear { audio.stop() }
  }
}

struct DemoCalendarPreview: View {
  let event: ChapterEvent
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      Form {
        Section("Sample calendar entry") {
          Text(event.title).font(.headline)
          Label(event.dateLabel, systemImage: "calendar")
          Label(event.location, systemImage: "mappin.and.ellipse")
          Text(event.description)
        }
        Section {
          Text(
            "This demo preview does not write to your calendar. The connected app opens Apple’s calendar editor so you can review and save a real ride."
          )
        }
      }.navigationTitle("Calendar preview").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
          Button("Done") { dismiss() }.buttonStyle(BrassButtonStyle()).padding(16)
        }
    }.preferredColorScheme(.dark).tint(Heritage.brass)
  }
}
