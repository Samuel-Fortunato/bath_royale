"""Separate USB-only TLS gateway for fictional development fixtures."""
import argparse
import json
import os
from pathlib import Path
from auth_device_proxy import Gateway, prepare, serve

class DevelopmentGateway(Gateway):
    auth_port = 55501
    rest_port = 55502

if __name__ == '__main__':
    os.umask(0o077)
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['prepare','serve'])
    parser.add_argument('directory',type=Path)
    args=parser.parse_args()
    if args.action=='prepare':
        prepare(args.directory)
        path=args.directory/'defines.json'
        config=json.loads(path.read_text())
        config.update(SUPABASE_URL='https://localhost:55504',SUPABASE_PUBLISHABLE_KEY='local-development-client')
        path.write_text(json.dumps(config))
    else:
        serve(args.directory,port=55504,handler=DevelopmentGateway)
