# Ride Guardian: dual ride marshals

Status: specification only; no live tracking or emergency alert functionality is implemented.

## Roles
Every organised ride can appoint two independent guardians:
- **Lead Guardian (front / Road Captain)**: publishes route, sets stops, sees the riding group and receives incident notifications.
- **Tail Guardian (back / Sweep)**: monitors the rear of the formation, confirms riders passing checkpoints, and alerts if anyone drops out.

Both guardians have equal incident visibility and emergency alert privileges; neither can silently disable the other's alerts. A group administrator may assign replacements with an audit trail. Permissions are scoped to the specific ride, not permanent chapter administrator rights.

## Workflow
1. Ride Captain creates an event and nominates the two guardians; both must accept.
2. Each member opts in to time-limited position sharing when joining the live ride.
3. Lead and Tail see an ordered ride roster, current/last-known position, last fix age, connectivity, battery when permitted and rider's last check-in.
4. A stopped or missing rider is labelled **check-in needed** or **signal lost**, not automatically *crashed*.
5. On SOS, missed check-in or strongly suspected incident, both guardians are notified, together with designated responders. The tail rider normally checks physically when appropriate while lead coordinates stopping the group safely; no response is presumed.
6. Guardians can acknowledge, mark responding, request further assistance and resolve with a reason. Both see the same incident log.
7. Guardians can notify **All riders**, **Guardians only**, or an individual, without losing music ducking behaviour.
8. Riders press **I'm Home** to finish. Guardians see a safe-arrival receipt without exposing home address. If a rider forgets, initiate a check-in/escalation according to a configured window; live sharing must have a clear maximum expiry and user revocation.

## Resilience
- If one guardian is offline, the other still gets incident reports. If both are offline, notify pre-consented designated safety contacts where possible.
- Indicate timestamps prominently: never present stale GPS as live. Cache reports locally during signal gaps, with delivery status.
- Where permitted, provide a third **deputy guardian** who can be promoted with recorded action; normal rides still have two active guardians.
- Ride closure requires a clear roster: home, left ride safely, being assisted, or unresolved. A guardian cannot suppress a member's SOS.
- Prioritise emergency voice/audio over normal intercom and music.

## Privacy and safety
Only consented riders and designated ride responders can see live locations; other members see at most coarse safety status by default. Do not expose private home coordinates. Retain ride histories for a configurable minimum period and purge according to policy. Never imply emergency services have been contacted unless a phone call or other verified action occurred. Motion sensor alerts are indicative and must be tested to avoid false positives.

## Acceptance tests
- Both guardians receive SOS and acknowledge independently.
- Lead disappears from network; Tail receives incident; vice versa.
- Rider off-route: check-in, not automatic accident declaration.
- One member finishes at home; sharing stops; both guardians receive completion.
- One guardian leaves ride; authorised deputy can take over.
- Ride ends with an unresolved rider; an explicit escalation is required.
