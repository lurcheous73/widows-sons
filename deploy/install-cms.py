#!/usr/bin/env python3
"""Install this project's CMS and services inside its dedicated Debian VM only."""
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import urllib.request

ROOT = Path('/srv/widows-sons')
SOURCE = ROOT / 'source'
WEB = ROOT / 'wordpress'
SECRET = Path('/etc/widows-sons')
DOMAIN = 'wsmba.the-grange.uk'

def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)

def write(path, text, mode=0o644):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(mode)

marker = Path('/etc/widows-sons-environment').read_text().splitlines()
assert 'VMID=20000' in marker and 'PROJECT=widows-sons' in marker and socket.gethostname() == 'can-widows-sons-dev', 'Wrong VM'
assert not (SECRET / 'credentials.json').exists(), 'CMS already installed; use a deliberate update rather than rerunning installation'
SECRET.mkdir(mode=0o750, exist_ok=True)
credentials = {'site': 'https://' + DOMAIN, 'admin_username': 'ws_site_admin', 'admin_password': secrets.token_urlsafe(30), 'editor_username': 'chapter-editor', 'editor_password': secrets.token_urlsafe(30), 'database_password': secrets.token_urlsafe(40)}
write(SECRET / 'credentials.json', json.dumps(credentials, indent=2), 0o600)
sql = "CREATE DATABASE widows_sons_cms CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; CREATE USER 'widows_cms'@'localhost' IDENTIFIED BY '" + credentials['database_password'] + "'; GRANT ALL PRIVILEGES ON widows_sons_cms.* TO 'widows_cms'@'localhost';"
run(['mariadb'], input=sql, text=True, capture_output=True)
cli_url = 'https://github.com/wp-cli/wp-cli/releases/download/v2.12.0/wp-cli-2.12.0.phar'
cli = ROOT / 'wp-cli.phar'
cli.write_bytes(urllib.request.urlopen(cli_url, timeout=60).read())
expected = urllib.request.urlopen(cli_url + '.sha512', timeout=30).read().decode().split()[0]
assert hashlib.sha512(cli.read_bytes()).hexdigest() == expected, 'WP-CLI checksum mismatch'
write(ROOT / 'migration/wp-cli-sha512.txt', expected + '\n')
WEB.mkdir(exist_ok=True)
wp = ['php', str(cli), '--allow-root', '--path=' + str(WEB)]
run(wp + ['core', 'download', '--locale=en_GB', '--skip-content'])
salt_names = ['AUTH_KEY', 'SECURE_AUTH_KEY', 'LOGGED_IN_KEY', 'NONCE_KEY', 'AUTH_SALT', 'SECURE_AUTH_SALT', 'LOGGED_IN_SALT', 'NONCE_SALT']
config = "<?php\n"
for key, value in {'DB_NAME': 'widows_sons_cms', 'DB_USER': 'widows_cms', 'DB_PASSWORD': credentials['database_password'], 'DB_HOST': 'localhost', 'DB_CHARSET': 'utf8mb4', 'DB_COLLATE': ''}.items():
    config += f"define({key!r}, {value!r});\n"
for key in salt_names:
    config += f"define({key!r}, {secrets.token_urlsafe(64)!r});\n"
config += """$table_prefix = 'ws_';
define('WP_HOME', 'https://wsmba.the-grange.uk');
define('WP_SITEURL', 'https://wsmba.the-grange.uk');
define('FORCE_SSL_ADMIN', true);
define('DISALLOW_FILE_EDIT', true);
define('WP_AUTO_UPDATE_CORE', 'minor');
define('WP_DEBUG', false);
define('WP_ENVIRONMENT_TYPE', 'development');
define('DISABLE_WP_CRON', true);
if (!defined('ABSPATH')) { define('ABSPATH', __DIR__ . '/'); }
require_once ABSPATH . 'wp-settings.php';
"""
write(WEB / 'wp-config.php', config, 0o640)
run(wp + ['core', 'install', '--url=https://' + DOMAIN, '--title=Widows Sons L&R', '--admin_user=' + credentials['admin_username'], '--admin_email=site-admin@example.invalid', '--skip-email', '--prompt=admin_password'], input=credentials['admin_password'] + '\n', text=True, capture_output=True)
shutil.copytree(SOURCE / 'cms/theme', WEB / 'wp-content/themes/widows-sons')
shutil.copytree(SOURCE / 'cms/mu-plugins', WEB / 'wp-content/mu-plugins', dirs_exist_ok=True)
run(wp + ['theme', 'activate', 'widows-sons'])
run(wp + ['user', 'create', credentials['editor_username'], 'chapter-editor@example.invalid', '--role=ws_chapter_editor', '--display_name=Chapter editor', '--prompt=user_pass'], input=credentials['editor_password'] + '\n', text=True, capture_output=True)
run(wp + ['eval-file', str(SOURCE / 'cms/seed.php')])
run(wp + ['core', 'verify-checksums', '--locale=en_GB'])
run(['chown', '-R', 'widowsweb:widowsweb', str(WEB)])
run(['chown', 'root:widowsweb', str(WEB / 'wp-config.php')])
version = subprocess.check_output(['php', '-r', 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;'], text=True)
write(f'/etc/php/{version}/fpm/pool.d/widows-sons.conf', '''[widows-sons]
user = widowsweb
group = widowsweb
listen = /run/php/widows-sons.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = ondemand
pm.max_children = 8
pm.process_idle_timeout = 20s
pm.max_requests = 500
php_admin_value[upload_max_filesize] = 20M
php_admin_value[post_max_size] = 24M
php_admin_value[memory_limit] = 256M
php_admin_flag[log_errors] = on
security.limit_extensions = .php
''')
write('/etc/nginx/sites-available/widows-sons', '''map $http_x_forwarded_proto $widows_https { default off; https on; }
server {
    listen 127.0.0.1:8080;
    listen 10.44.0.200:8080;
    server_name wsmba.the-grange.uk;
    root /srv/widows-sons/wordpress;
    index index.php;
    client_max_body_size 24m;
    set_real_ip_from 10.44.0.12;
    real_ip_header X-Forwarded-For;
    real_ip_recursive on;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Widows-Sons-Environment "Canada-VM20000" always;
    add_header X-Robots-Tag "noindex, nofollow" always;
    location = /healthz { access_log off; default_type application/json; return 200 '{"project":"widows-sons","vmid":20000,"status":"ok"}'; }
    location /api/ { proxy_pass http://127.0.0.1:8008/api/; proxy_set_header Host $host; }
    location = /api-health { proxy_pass http://127.0.0.1:8008/health; }
    location /prototype/ { alias /srv/widows-sons/source/site/; index index.html; }
    location / { try_files $uri $uri/ /index.php?$args; }
    location ~* ^/wp-content/uploads/.*\\.php$ { deny all; }
    location ~ /\\. { deny all; }
    location ~* /(wp-config\\.php|readme\\.html|license\\.txt)$ { deny all; }
    location = /xmlrpc.php { deny all; }
    location ~ \\.php$ {
        try_files $uri =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param HTTPS $widows_https;
        fastcgi_pass unix:/run/php/widows-sons.sock;
    }
}
''')
default = Path('/etc/nginx/sites-enabled/default')
if default.is_symlink(): default.unlink()
Path('/etc/nginx/sites-enabled/widows-sons').symlink_to('/etc/nginx/sites-available/widows-sons')
write('/etc/systemd/system/widows-sons-api.service', '''[Unit]
Description=Widows Sons VM20000 chapter API
After=network.target postgresql.service
[Service]
User=widowsapi
Group=widowsapi
WorkingDirectory=/srv/widows-sons/source/backend
Environment="WIDOWS_SONS_DATABASE_DSN=dbname=widowssons user=widowsapi host=/var/run/postgresql"
Environment=PYTHONDONTWRITEBYTECODE=1
ExecStart=/srv/widows-sons/venv/bin/uvicorn app:app --host 127.0.0.1 --port 8008
Restart=on-failure
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
MemoryMax=768M
[Install]
WantedBy=multi-user.target
''')
write('/etc/systemd/system/widows-sons-cms-cron.service', '''[Unit]
Description=Widows Sons CMS scheduled housekeeping
[Service]
Type=oneshot
User=widowsweb
ExecStart=/usr/bin/php /srv/widows-sons/wordpress/wp-cron.php
''')
write('/etc/systemd/system/widows-sons-cms-cron.timer', '''[Unit]
Description=Widows Sons CMS housekeeping timer
[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
RandomizedDelaySec=30
[Install]
WantedBy=timers.target
''')
run(['systemctl', 'daemon-reload'])
run(['nginx', '-t'])
run(['systemctl', 'restart', f'php{version}-fpm', 'nginx'])
run(['systemctl', 'enable', '--now', 'widows-sons-api', 'widows-sons-cms-cron.timer'])
run(['systemctl', 'is-active', 'widows-sons-api', 'nginx', f'php{version}-fpm', 'postgresql', 'mariadb'])
receipt = {'site': credentials['site'], 'wordpress_version': subprocess.check_output(wp + ['core', 'version'], text=True).strip(), 'php_version': version, 'source_commit': '68c6cd357ff6bf5005bc30f73e78a8d0a831a159', 'vmid': 20000, 'environment': 'development', 'email_delivery': 'disabled; enquiries retained in CMS', 'credential_file': str(SECRET / 'credentials.json')}
write(ROOT / 'migration/cms-install-receipt.json', json.dumps(receipt, indent=2))
print(json.dumps(receipt), flush=True)
