#!/usr/bin/env python3
"""Integration checks against the running CMS and restored chapter API."""
import http.cookiejar
import json
from pathlib import Path
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request

WP = ['php', '/srv/widows-sons/wp-cli.phar', '--allow-root', '--path=/srv/widows-sons/wordpress']
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs): return None
opener = urllib.request.build_opener(NoRedirect)
checks = []
def check(name, condition):
    if not condition: raise AssertionError(name)
    checks.append(name)
    print('PASS ' + name, flush=True)
def php(code):
    return subprocess.check_output(WP + ['eval', code], text=True).strip()
def request(path, method='GET', data=None, auth=None, form=False):
    headers = {'Host': 'wsmba.the-grange.uk', 'X-Forwarded-Proto': 'https'}
    if auth:
        headers['Cookie'] = auth['name'] + '=' + auth['cookie']
        headers['X-WP-Nonce'] = auth['nonce']
    if data is not None:
        headers['Content-Type'] = 'application/x-www-form-urlencoded' if form else 'application/json'
        data = (urllib.parse.urlencode(data) if form else json.dumps(data)).encode()
    req = urllib.request.Request('http://127.0.0.1:8080' + path, data=data, method=method, headers=headers)
    try: response = opener.open(req, timeout=20)
    except urllib.error.HTTPError as error: response = error
    body = response.read().decode()
    return response.code, dict(response.headers), body

subprocess.run(['runuser', '-u', 'widowsapi', '--', '/srv/widows-sons/venv/bin/python', '-m', 'pytest', '-q', '-p', 'no:cacheprovider'], cwd='/srv/widows-sons/source/backend', check=True)
check('existing backend regression suite', True)
status, headers, body = request('/')
check('homepage and custom chapter theme', status == 200 and 'Good roads.' in body and 'Better company.' in body and 'widows-sons' in body)
check('environment is labelled VM20000', headers.get('X-Widows-Sons-Environment') == 'Canada-VM20000')
for path in ('/about/', '/rides/', '/charity/', '/news/', '/gallery/', '/contact/'):
    check('page ' + path, request(path)[0] == 200)
check('restored public chapter profile', json.loads(request('/api/v1/public/lr/profile')[2])['slug'] == 'lr')
check('unknown chapter remains isolated', request('/api/v1/public/unknown/profile')[0] == 404)
check('private enquiries have no public REST collection', request('/wp-json/wp/v2/ws_enquiry')[0] == 404)
check('anonymous CMS writes rejected', request('/wp-json/wp/v2/pages', 'POST', {'title': 'Unauthorised integration test'})[0] == 401)

auth = json.loads(php("$u=get_user_by('login','chapter-editor');$expiry=time()+600;$token=WP_Session_Tokens::get_instance($u->ID)->create($expiry);$cookie=wp_generate_auth_cookie($u->ID,$expiry,'logged_in',$token);$_COOKIE[LOGGED_IN_COOKIE]=$cookie;wp_set_current_user($u->ID);echo json_encode(['name'=>LOGGED_IN_COOKIE,'cookie'=>$cookie,'nonce'=>wp_create_nonce('wp_rest')]);"))
capabilities = json.loads(php("$u=get_user_by('login','chapter-editor');wp_set_current_user($u->ID);echo json_encode(['pages'=>current_user_can('publish_pages'),'posts'=>current_user_can('publish_posts'),'design'=>current_user_can('edit_theme_options'),'users'=>current_user_can('edit_users'),'plugins'=>current_user_can('install_plugins'),'options'=>current_user_can('manage_options')]);"))
check('chapter editor can publish and edit design without system administration', capabilities == {'pages': True, 'posts': True, 'design': True, 'users': False, 'plugins': False, 'options': False})
created = []
try:
    code, _, payload = request('/wp-json/wp/v2/pages', 'POST', {'title': 'Integration QA page', 'status': 'draft', 'content': '<!-- wp:paragraph --><p>Initial content.</p><!-- /wp:paragraph -->'}, auth)
    page = json.loads(payload)
    check('editor creates a page through authenticated CMS REST API', code == 201)
    created.append(('pages', page['id']))
    code, _, payload = request('/wp-json/wp/v2/pages/' + str(page['id']), 'POST', {'content': '<!-- wp:paragraph --><p>Updated by chapter editor.</p><!-- /wp:paragraph -->'}, auth)
    check('editor updates page content', code == 200 and 'Updated by chapter editor.' in json.loads(payload)['content']['raw'])
    check('editor cannot create administrators', request('/wp-json/wp/v2/users', 'POST', {'username': 'qa-disallowed', 'email': 'qa@example.invalid', 'password': 'unused-test-value', 'roles': ['administrator']}, auth)[0] == 403)
    code, _, payload = request('/wp-json/wp/v2/ws_event', 'POST', {'title': 'Integration QA ride', 'content': 'Temporary verification event.', 'status': 'draft', 'meta': {'_ws_starts_at': '2099-11-07T10:00', '_ws_location': 'QA location'}}, auth)
    event = json.loads(payload)
    check('editor creates ride with date and location fields', code == 201 and event.get('meta', {}).get('_ws_starts_at') == '2099-11-07T10:00')
    created.append(('ws_event', event['id']))
    feed = json.loads(request('/wp-json/widows-sons/v1/events')[2])
    check('draft event excluded from public feed', all(e['id'] != 'cms-' + str(event['id']) for e in feed['events']))
    check('editor can publish event', request('/wp-json/wp/v2/ws_event/' + str(event['id']), 'POST', {'status': 'publish'}, auth)[0] == 200)
    feed = json.loads(request('/wp-json/widows-sons/v1/events')[2])
    check('published event appears with its date and location', any(e['id'] == 'cms-' + str(event['id']) and e['location'] == 'QA location' and e['starts_at'].startswith('2099-11-07T10:00') for e in feed['events']))
    check('published event renders on rides page', 'Integration QA ride' in request('/rides/')[2])
finally:
    for type_, id_ in created: request('/wp-json/wp/v2/' + type_ + '/' + str(id_), 'DELETE', auth=auth)

status, _, form = request('/contact/')
nonce = re.search(r'name="ws_nonce" value="([^"]+)"', form).group(1)
form_data = {'action': 'ws_enquiry', 'ws_nonce': nonce, 'name': 'Integration QA', 'email': 'qa@example.invalid', 'message': 'Temporary contact form integration verification.', 'consent': '1', 'company_website': ''}
check('invalid enquiry nonce rejected', request('/wp-admin/admin-post.php', 'POST', {**form_data, 'ws_nonce': 'invalid'}, form=True)[0] == 400)
status, headers, _ = request('/wp-admin/admin-post.php', 'POST', form_data, form=True)
check('valid enquiry saved and acknowledged', status == 302 and 'received=1' in headers.get('Location', ''))
count = int(php("$p=get_posts(['post_type'=>'ws_enquiry','post_status'=>'private','meta_key'=>'_ws_email','meta_value'=>'qa@example.invalid']);echo count($p);foreach($p as $x){wp_trash_post($x->ID);}"))
check('enquiry stored privately for editors', count == 1)
counts = subprocess.check_output(['runuser', '-u', 'postgres', '--', 'psql', '-d', 'widowssons', '-Atc', 'SELECT (SELECT count(*) FROM organisations),(SELECT count(*) FROM members),(SELECT count(*) FROM chapter_events)'], text=True).strip()
check('migrated database row counts preserved', counts == '1|0|0')
denied = subprocess.run(['runuser', '-u', 'widowsapi', '--', 'psql', '-d', 'widowssons', '-Atc', 'SELECT count(*) FROM members'], capture_output=True, text=True)
check('public API account cannot read member records', denied.returncode != 0 and 'permission denied' in denied.stderr)
receipt = {'status': 'PASS', 'checks': checks, 'count': len(checks), 'database_counts': counts, 'environment': 'canada-vm20000', 'public_dns_and_trusted_tls': 'pending user Cloudflare/DNS setup'}
Path('/srv/widows-sons/migration/integration-receipt.json').write_text(json.dumps(receipt, indent=2))
print(json.dumps({'status': 'PASS', 'count': len(checks)}), flush=True)
