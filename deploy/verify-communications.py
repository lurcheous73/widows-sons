#!/usr/bin/env python3
"""Root-only, disposable two-client voice verification on Canada VM20000.

Requires the optional `livekit==1.1.21` RTC test package. No human microphone or
recording is used. Temporary members, messages, sessions and grants are removed
in finally blocks. Never substitute real chapter member identities.
"""
import asyncio
import array
import importlib.util
import json
import logging
import math
import os
from pathlib import Path
import secrets
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

from livekit import api, rtc

spec = importlib.util.spec_from_file_location('verify_mobile', Path(__file__).with_name('verify-mobile.py'))
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
logging.basicConfig(level=logging.ERROR)


async def main():
    assert os.geteuid() == 0
    marker = Path('/etc/widows-sons-environment').read_text()
    assert 'VMID=20000' in marker and 'PROJECT=widows-sons' in marker
    for attempt in range(20):
        try:
            with urllib.request.urlopen('http://127.0.0.1:8009/health', timeout=1) as response:
                assert response.status == 200
            break
        except (OSError, AssertionError):
            if attempt == 19:
                raise
            await asyncio.sleep(.5)
    org = v.db("SELECT id FROM organisations WHERE slug='lr'", fetch=True)[0][0]
    env = dict(line.split('=', 1) for line in Path('/etc/widows-sons/voice-api.env').read_text().splitlines() if '=' in line)
    members, tokens, grants, tasks = [], [], [], []
    rooms = [rtc.Room(), rtc.Room()]
    received, sender_removed, receiver_removed = asyncio.Event(), asyncio.Event(), asyncio.Event()
    stats = {'frames': 0, 'nonzero_samples': 0}

    async def consume(track):
        stream = rtc.AudioStream(track, sample_rate=48000, num_channels=1)
        try:
            async for event in stream:
                stats['frames'] += 1
                stats['nonzero_samples'] += sum(1 for sample in event.frame.data if abs(sample) > 100)
                if stats['frames'] >= 10 and stats['nonzero_samples'] > 100:
                    received.set()
                    break
        finally:
            await stream.aclose()

    @rooms[1].on('track_subscribed')
    def track_subscribed(track, publication, participant):
        if track.kind == rtc.TrackKind.KIND_AUDIO:
            tasks.append(asyncio.create_task(consume(track)))

    @rooms[0].on('disconnected')
    def sender_disconnected(reason):
        sender_removed.set()

    @rooms[1].on('disconnected')
    def receiver_disconnected(reason):
        receiver_removed.set()

    try:
        for index, room in enumerate(rooms):
            code = 'wsi_' + secrets.token_urlsafe(32)
            member = v.db('INSERT INTO members(organisation_id,email,display_name) VALUES(%s,%s,%s) RETURNING id',
                          (org, 'comms-verify-' + secrets.token_hex(8) + '@example.invalid', 'Temporary communications verification fixture'), True)[0][0]
            members.append(member)
            v.db('INSERT INTO mobile_invites(token_hash,organisation_id,member_id,expires_at) VALUES(%s,%s,%s,%s)',
                 (v.digest(code), org, member, datetime.now(timezone.utc) + timedelta(hours=1)))
            status, session = v.request('lr/activate', 'POST', {'code': code})
            assert status == 200, 'Temporary invitation could not activate'
            tokens.append(session['token'])
            status, grant = v.request('lr/voice', 'POST', {}, tokens[-1])
            assert status == 200, 'Temporary voice grant could not be issued'
            grants.append(grant)
            await room.connect('ws://127.0.0.1:8080', grant['token'])
        source = rtc.AudioSource(48000, 1)
        track = rtc.LocalAudioTrack.create_audio_track('Synthetic QA tone', source)
        await rooms[0].local_participant.publish_track(track, rtc.TrackPublishOptions(source=rtc.TrackSource.SOURCE_MICROPHONE))

        async def publish():
            for frame in range(250):
                pcm = array.array('h', (int(2500 * math.sin(2 * math.pi * 440 * (frame * 480 + sample) / 48000)) for sample in range(480)))
                await source.capture_frame(rtc.AudioFrame(data=pcm.tobytes(), sample_rate=48000, num_channels=1, samples_per_channel=480))
                await asyncio.sleep(.01)

        tasks.append(asyncio.create_task(publish()))
        await asyncio.wait_for(received.wait(), 15)
        assert v.request('lr/voice/' + grants[1]['grant_id'], 'DELETE', token=tokens[1])[0] == 204
        await asyncio.wait_for(receiver_removed.wait(), 30)
        try:
            urllib.request.urlopen('http://127.0.0.1:8080/rtc/validate?access_token=' + grants[1]['token'], timeout=5)
            raise AssertionError('Revoked voice JWT was accepted by Nginx')
        except urllib.error.HTTPError as error:
            assert error.code == 401
        # Account deletion cascades grant records; the active-participant sweep
        # must still remove this already connected sender from the SFU.
        v.db('DELETE FROM members WHERE organisation_id=%s AND id=%s', (org, members[0]))
        await asyncio.wait_for(sender_removed.wait(), 30)
    finally:
        for task in tasks:
            task.cancel()
        for room in rooms:
            await room.disconnect()
        try:
            async with api.LiveKitAPI('http://127.0.0.1:7880', env['WIDOWS_SONS_VOICE_KEY'], env['WIDOWS_SONS_VOICE_SECRET']) as client:
                for member, grant in zip(members, grants):
                    try:
                        await client.room.remove_participant(api.RoomParticipantIdentity(room=grant['room_name'], identity=member + ':' + grant['grant_id']))
                    except api.TwirpError as error:
                        if error.code != 'not_found':
                            raise
        finally:
            for member in members:
                v.db('DELETE FROM audit_events WHERE organisation_id=%s AND (actor_id=%s OR target_id=%s)', (org, member, member))
                v.db('DELETE FROM members WHERE organisation_id=%s AND id=%s', (org, member))
    assert all(v.db('SELECT count(*) FROM members WHERE id=%s', (member,), True)[0][0] == 0 for member in members)
    print(json.dumps({'webrtc_clients_connected': 2, 'synthetic_audio_received': True, **stats,
                      'revoked_participant_disconnected': True, 'revoked_reconnect_rejected': True,
                      'deleted_member_disconnected': True, 'temporary_fixtures_removed': True,
                      'human_microphone_used': False, 'audio_recorded': False}))


if __name__ == '__main__':
    asyncio.run(main())
