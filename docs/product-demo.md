# WS L&R Demo — 0.8.0

The owner requested a product to demonstrate, followed by polish. This is a
native Swift 6 / SwiftUI application using the proposed Heritage & Road design
and the same screen implementations as the connected Widows Sons app.

## Start

Open **WS L&R Demo**. It opens as **Alex · demo member** without an invitation.
Tap **Demo tour** at the top to jump into any of the seven journeys. The reset
icon returns all sample records to their starting state; confirm **Reset demo**.
Closing and relaunching the process also creates fresh sample content.

No real chapter sign-in, public DNS, Cloudflare or VM20000 connection is needed.
Apple MapKit backgrounds may need internet access; all chapter interactions use
the in-process demo store. This demo uses no real GPS or microphone capture.

## Five-minute presentation

1. **Meet the chapter.** Show the charcoal/brass welcome screen, news and rides.
2. **Plan the Sunday ride.** Change Going/Interested/Not going. Open the briefing,
   sample GPX route, coffee stop and accepted Road Captain/Sweep roles. Calendar
   opens a preview that does not write an actual event.
3. **Send a chapter message.** Send a short fictional message. A labelled
   **Demo reply** from Jamie follows after a few seconds. The text remains while
   you explore this run. Direct and ride conversations are also populated.
4. **Keep the ride together.** Open the sample rider map. Your sharing starts
   off; tap Share to show Alex's synthetic position, then Stop to remove it. Use
   Check in. No device-location permission is needed or requested.
5. **Handle a help request.** The tour generates Sam's sample puncture request.
   Open it, acknowledge as Alex/Sweep, and show Jamie's independent receipt.
   Record a resolution note. These are fictional records, not emergency dispatch.
6. **Open the clubhouse.** Read an announcement, open the coffee-stop poll,
   choose/change/withdraw a vote and add a comment. The directory also has an
   invited private group and an open group, so joining can be demonstrated.
7. **Carry your membership.** Show the sample card and updated RSVP summary.
   Guest preview and re-entering the demo are available from Member.

For audio, open Comms or the live ride and tap **Play briefing preview**. This
speaks a sample briefing through the device's selected audio output. It is
explicitly labelled as an audio preview and is not a live intercom call.

## Build and installation

Open `ios-native/WidowsSons.xcodeproj` in Xcode, select **WidowsSons-Demo** and
Run on an iOS 17+ Simulator or an appropriately provisioned physical iPhone.
The checked-in project includes the scheme. XcodeGen 2.46.0 can regenerate it
from `project.yml`. Dependencies remain pinned and their notices are bundled.

- Demo-Debug / Demo-Release: `uk.thegrange.widowsSons.demo`, **WS L&R Demo**.
- Debug / Release: the existing connected app and VM20000 configuration.
- CarPlay-Debug / CarPlay-Release: connected communication-category companion.

The packaged Simulator app needs a Mac with Xcode and a compatible iOS Simulator.
The development-signed IPA installs only on devices included in its Apple
provisioning profile, within that profile's validity. It is not an App Store or
TestFlight release. Signing credentials, device identifiers, provisioning
inventories and full build logs are kept out of the repository.

## Implementation and validation

`DemoChapter.swift` supplies fixtures and a stateful actor implementing the API
contract. `DemoExperience.swift` supplies the tour, sample audio and calendar
preview. Demo origin validation and transport guards reject live destinations.
The location driver creates synthetic fixes only in demo mode. Each tour jump
waits for sheet dismissal and starts a fresh navigation stack while retaining
the current demo store. Reset replaces that store and resets navigation.

The native suite contains 56 tests, including nine demo tests covering live-origin
rejection, populated launch, idempotent messages, RSVP/guest mode, synthetic
tracking, independent Guardian receipts and resolution, polls/comments, explicit
invitation acceptance and refused live intercom grants. The delivery receipt
records the final test/build, signing and installation results.

This milestone leaves live VM20000 services, website content, NPM and Cloudflare
unchanged. Live intercom, actual GPS, locked-phone/headset behaviour, Siri and
CarPlay require the connected build and physical acceptance. Membership/admin
workflows, documents/media, commerce/fundraising and confidential welfare remain
subsequent work; this demo does not claim the full consultation spec is finished.
