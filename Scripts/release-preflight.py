#!/usr/bin/env python3
import os,sys,subprocess,urllib.parse
origin=urllib.parse.urlparse(os.environ.get('TERO_WEBSITE_URL',''))
identity=os.environ.get('TERO_DEVELOPER_ID','')
if origin.scheme!='https' or not origin.hostname or origin.username or origin.password or origin.query or origin.fragment or origin.path not in ('','/'):
 sys.exit('Set TERO_WEBSITE_URL to the public HTTPS sign-in origin before exporting a test release.')
if not identity.startswith('Developer ID Application:'):
 sys.exit('A Developer ID Application certificate is required. Development/ad-hoc signing cannot be distributed.')
identities=subprocess.run(['security','find-identity','-v','-p','codesigning'],capture_output=True,text=True,check=True).stdout
if identity not in identities:sys.exit('The selected Developer ID certificate is not installed in Keychain.')
print('PASS: explicit HTTPS origin and installed Developer ID signing identity')
