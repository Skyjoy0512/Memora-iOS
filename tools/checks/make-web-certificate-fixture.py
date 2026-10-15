"""An ephemeral local test identity; never installs an OS/keychain certificate."""
import pathlib
import subprocess
import sys
import tempfile

destination = pathlib.Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='web-certificate-', dir=destination.parent) as directory:
    root = pathlib.Path(directory)
    config = root / 'certificate.cnf'
    config.write_text('''[req]
distinguished_name=dn
x509_extensions=extensions
prompt=no
[dn]
CN=trusted.example.com
[extensions]
subjectAltName=DNS:trusted.example.com
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
''')
    subprocess.run(['openssl', 'req', '-new', '-x509', '-sha256', '-days', '1', '-newkey', 'rsa:2048',
                    '-nodes', '-keyout', str(root / 'ephemeral.key'), '-outform', 'DER',
                    '-out', str(destination), '-config', str(config)],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
