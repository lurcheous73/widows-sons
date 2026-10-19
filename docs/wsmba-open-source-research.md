# Public WSMBA source search — 19 October 2026

The owner requested suitable GitHub code from other WSMBA applications. Public
repository and Swift-language searches found chapter websites, but no native iOS
communications/tracking implementation suitable for this milestone. This does
not establish that no private or unindexed implementation exists. An App Store
feature list does not make an application's code available for reuse.

| Repository | Contents and licence evidence | Decision |
| --- | --- | --- |
| [alex-sashev/ws-europe-theme](https://github.com/alex-sashev/ws-europe-theme) | WordPress theme; README declares GPL-2.0-or-later | Potential CMS reference, no Swift communications component |
| [alex-sashev/ws-chapters](https://github.com/alex-sashev/ws-chapters) | WordPress chapter records; README declares GPL-2.0-or-later | Potential chapter-directory integration, no native tracking component |
| [JBFre/WidowsSons.github.io](https://github.com/JBFre/WidowsSons.github.io) | HTML website; no recognised licence in metadata | No code or artwork copied |
| [ChrisK1509/cobblestones-site](https://github.com/ChrisK1509/cobblestones-site) | Website; no licence in metadata or inspected README | No code or artwork copied |
| [ChrisK1509/cobblestones-website](https://github.com/ChrisK1509/cobblestones-website) | Website; no recognised licence in metadata | No code or artwork copied |
| [paxle1802/widowssonspasskeepers.website](https://github.com/paxle1802/widowssonspasskeepers.website) | Website/CSS, additional result | No native feature component selected |

GitHub licence metadata was insufficient: the two GPL declarations were confirmed
in their READMEs. No WSMBA proprietary app code or insignia was imported.

## Open source actually integrated

- [LiveKit Swift](https://github.com/livekit/client-sdk-swift) **2.18.0**, Apache-2.0,
  revision `93a7251057bdb6a80a7b1f6d11464d578ebdc09b`: native room, microphone,
  participant and connection state. SwiftPM pins its binary dependencies too.
- [LiveKit server](https://github.com/livekit/livekit/releases/tag/v1.13.10)
  **1.13.10**, Apache-2.0: self-hosted SFU on VM20000; checksum-verified release.
  This installation does not require LiveKit Cloud.
- [LiveKit Python API](https://github.com/livekit/python-sdks) **1.2.1**: scoped
  voice tokens and participant removal. Python RTC **1.1.21** was used separately
  for synthetic transport verification on the development VM.
- [KeychainAccess](https://github.com/kishikawakatsumi/KeychainAccess) **4.2.2**,
  MIT: device-only sign-in storage.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) **2.46.0**, MIT: build tool.

Full client licence/notices, including LiveKitWebRTC, LiveKitUniFFI and nanopb,
are bundled in `ios-native/ThirdPartyNotices.txt` and readable in the app. The
Swift screens, chapter messaging API and opt-in tracking were written for this
project. Own-project licence selection remains pending.
