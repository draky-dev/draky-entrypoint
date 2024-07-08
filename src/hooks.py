"""This file contains hooks that modify draky's behavior.
"""

import re
from subprocess import run

def alter_service(name: str, service: dict, utils: object, addon: dict):
    """Change services to use an entry
    """
    if 'image' not in service:
        return

    image = utils.substitute_variables(service['image'])

    __ensure_image(image)

    # Override entrypoint.
    service['entrypoint'] =(
            ['/draky-entrypoint.sh'] + __extract_from_image(image, 'ENTRYPOINT'))

    # CMD needs to be redeclared if entrypoint has been overriden.
    # See: https://github.com/docker/docs/issues/6142
    service['command'] = __extract_from_image(image, 'CMD')

    if 'volumes' not in service:
        service['volumes'] = []

    service['volumes'].append(
        f"${{DRAKY_PROJECT_CONFIG_ROOT}}/"
        f"{addon.dirpath}/draky-entrypoint.sh:/draky-entrypoint.sh:cached"
    )

def __extract_from_image(image: str, target: str) -> list[str]:
    command = [
        'docker',
        'history',
        '--no-trunc',
        image,
    ]
    result = run(command, check=False, capture_output=True)
    match = re.search(target + r" \[(.+)\]", result.stdout.decode(encoding='utf8'))
    if not match or not match.groups():
        return []

    return re.findall(r"\"(.+?)\"", match.group(1))

def __ensure_image(image: str):
    """Make sure that the image is available.
    """
    command = [
        'docker',
        'inspect',
        '--type=image',
        image,
    ]
    result = run(command, check=False, capture_output=True)
    if result.returncode != 0:
        command = [
            'docker',
            'pull',
            image,
        ]
        result = run(command, check=False, capture_output=True)
        if result.returncode != 0:
            raise ValueError(f"'{image}' image is not available.")
