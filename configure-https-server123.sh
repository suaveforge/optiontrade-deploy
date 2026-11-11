#!/bin/sh
set -eu
DOCKER=/home/ggul-docker/bin/docker
SOCK=unix:///home/ggul-docker/run/docker.sock
"$DOCKER" -H "$SOCK" run --rm -i --network host \
  -v /home:/home:rw python:3.11-alpine python - <<'PY'
import os,subprocess,shutil,stat,tempfile,fcntl,secrets,urllib.request,json
from pathlib import Path

root=Path('/home/futures-options-trader')
deploy=root/'deploy'
priv=root/'secrets'
backups=root/'backups'
for d in (deploy,priv,backups):d.mkdir(parents=True,exist_ok=True)
os.chmod(priv,0o700)
os.chmod(backups,0o700)

config=Path('/home/gyeol/Caddyfile')
binary=Path('/home/gyeol/runtime/caddy/caddy')
snippet=deploy/'Caddyfile.optiontrade'
password_file=priv/'basic-auth-password.txt'
lock=deploy/'.caddy-optiontrade.lock'
import_line=f'import {snippet}'
hostname='optiontrade.suaveforge.com'
service='127.0.0.1:18765'

if not config.is_file() or not binary.is_file():
    raise RuntimeError('CADDY_CONFIG_OR_BINARY_MISSING')
try:
    with urllib.request.urlopen('http://127.0.0.1:2019/config/', timeout=5) as r:
        if r.status!=200:raise RuntimeError('CADDY_ADMIN_NOT_READY')
except Exception:
    raise RuntimeError('CADDY_ADMIN_NOT_READY')

fd=os.open(lock,os.O_CREAT|os.O_RDWR,0o600)
fcntl.flock(fd,fcntl.LOCK_EX)
try:
    if not password_file.exists():
        pwd=secrets.token_urlsafe(28)
        tmp=priv/'.basic-auth.tmp'
        with open(tmp,'w') as f:f.write(pwd+'\n')
        os.chmod(tmp,0o600)
        os.replace(tmp,password_file)
    else:
        pwd=password_file.read_text().strip()
    if len(pwd)<20:
        raise RuntimeError('BASIC_AUTH_PASSWORD_TOO_SHORT')
    h=subprocess.run([str(binary),'hash-password','--algorithm','bcrypt','--plaintext',pwd],
                     capture_output=True,text=True,timeout=25)
    if h.returncode!=0 or not h.stdout.strip().startswith('$2'):
        raise RuntimeError('CADDY_HASH_PASSWORD_FAILED')
    digest=h.stdout.strip()
    snippet_text=f'''# Private LS paper-trading dashboard. Never remove basic_auth.
{hostname} {{
    basic_auth bcrypt {{
        trader {digest}
    }}
    reverse_proxy {service}
    header {{
        Cache-Control "no-store"
        X-Content-Type-Options "nosniff"
        Referrer-Policy "no-referrer"
        X-Frame-Options "DENY"
    }}
}}
'''
    if snippet.exists() and snippet.read_text()==snippet_text and import_line in config.read_text():
        print('OPTIONTRADE_HTTPS_CONFIG=ALREADY_STAGED')
    else:
        stmp=deploy/'.Caddyfile.optiontrade.tmp'
        stmp.write_text(snippet_text)
        os.chmod(stmp,0o640)
        os.replace(stmp,snippet)
        original=config.read_bytes()
        if import_line.encode() in original:
            candidate=original
        else:
            candidate=original.rstrip()+b'\n\n'+import_line.encode()+b'\n'
        tmp_config=config.parent/'.Caddyfile.optiontrade.candidate'
        tmp_config.write_bytes(candidate)
        os.chmod(tmp_config,stat.S_IMODE(config.stat().st_mode))
        check=subprocess.run([str(binary),'adapt','--config',str(tmp_config),'--adapter','caddyfile'],
                             stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True,timeout=25)
        if check.returncode!=0:
            tmp_config.unlink(missing_ok=True)
            raise RuntimeError('CADDY_CONFIG_VALIDATION_FAILED')
        if candidate!=original:
            backup=backups/'Caddyfile.before-optiontrade-20261111'
            if not backup.exists():
                backup.write_bytes(original)
                os.chmod(backup,0o600)
            shutil.copymode(config,tmp_config)
            os.replace(tmp_config,config)
        else:tmp_config.unlink(missing_ok=True)
        reload=subprocess.run([str(binary),'reload','--config',str(config),'--adapter','caddyfile'],
                              stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True,timeout=35)
        if reload.returncode!=0:
            if candidate!=original:
                restore=config.parent/'.Caddyfile.optiontrade.rollback'
                restore.write_bytes(original)
                shutil.copymode(config,restore)
                os.replace(restore,config)
                subprocess.run([str(binary),'reload','--config',str(config),'--adapter','caddyfile'],
                               stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=35)
            raise RuntimeError('CADDY_RELOAD_FAILED_RESTORED_MAIN_CONFIG')
        print('OPTIONTRADE_HTTPS_CONFIG=RELOADED')
    print('OPTIONTRADE_BASIC_AUTH_USER=trader')
    print('OPTIONTRADE_BASIC_AUTH_PASSWORD_FILE=/home/futures-options-trader/secrets/basic-auth-password.txt')
    print('OPTIONTRADE_HTTPS_HOST=optiontrade.suaveforge.com')
finally:
    fcntl.flock(fd,fcntl.LOCK_UN)
    os.close(fd)
PY
