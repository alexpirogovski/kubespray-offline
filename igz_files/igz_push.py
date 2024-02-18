import os
import ast
import sys
import yaml
import logging
import argparse
import subprocess


def get_image_name_from_tarball(tarball):
    image_name_from_file = os.path.basename(tarball).replace('.tar.gz', '').replace('.tar', '')
    image_name = ''
    if 'kubespray' in tarball:
        # Strip repo name
        for repo in ['registry.k8s.io', 'k8s.gcr.io', 'gcr.io', 'docker.io', 'quay.io']:
            if repo in image_name_from_file:
                image_name = image_name_from_file.replace(f'{repo}_', '').replace('_', '/')
                break
        # Kubespray guys assume that image tags will never have a dash in it. So do we
        last_dash = image_name.rfind('-', 1)
        if last_dash != -1:
            image_name = image_name[:last_dash] + ':' + image_name[last_dash + 1:]
        logging.debug(f'Processed kubespray image {image_name}')
    elif 'bootstrap_apps' not in tarball:  # bootstrap_apps goes directly to app nodes
        image_name = image_name_from_file.replace("__", "/").replace("--", ":")
        logging.debug(f'Processed iguazio image {image_name}')
    else:
        image_name = None
    return image_name


def get_hashes_and_version(hash_file):
    with open(hash_file, 'r') as hf:
        packaging = yaml.safe_load(hf)

    version = packaging['version']

    components = ['BigData',
                  'BigDataCuda',
                  'Engine',
                  'FlexFuse']
    hashes = []
    for component in components:
        hashes.append(packaging['hashes'][component])

    return hashes, version


def retag_if_needed(image, hashes, version):
    image_name, tag = image.split(':')
    if tag in hashes:
        logging.debug(f'Retagging {image_name} with {version}')
        return image_name + ':' + version
    else:
        return image


def set_dest(image, dest_url):
    return f'docker://{dest_url}/{image}'


def get_src(tarball):
    return f'docker-archive:{tarball}'


def build_skopeo_cmd(src, dest):
    command = '/usr/bin/skopeo copy --dest-no-creds --dest-tls-verify=false --insecure-policy'
    return f'{command} {src} {dest}'


def _parse_cli():
    parser = argparse.ArgumentParser(description='Skopeo copy script')
    parser.add_argument('-sl', '--source-list', dest='source_list', help='List of full paths to archived images'
                        , required=True)
    parser.add_argument('-hf', '--hashes-file',  help='Component hashes file', required=True)
    parser.add_argument('-dr', '--dest-repo', help='Destination repo', required=True)
    return parser.parse_args()


def main():
    logging.basicConfig(
        filename='/var/log/skopeo.log',
        level=logging.DEBUG,
        format='%(asctime)s:%(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )

    args = _parse_cli()

    source_list = ast.literal_eval(args.source_list)
    hashes, version = get_hashes_and_version(args.hashes_file)
    dest_repo = args.dest_repo
    for tarball in source_list:
        processing_image = get_image_name_from_tarball(tarball)

        if processing_image:
            processing_image = retag_if_needed(processing_image, hashes, version)
            src = get_src(tarball)
            dest = set_dest(processing_image, dest_repo)
            skopeo_command = build_skopeo_cmd(src, dest)
            logging.debug(f'Skopeo command: {skopeo_command}')
            subprocess.check_output(skopeo_command.split(' '))


if __name__ == '__main__':
    sys.exit(main())
