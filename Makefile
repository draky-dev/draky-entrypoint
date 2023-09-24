.ONESHELL:
.PHONY: $(MAKECMDGOALS)
SHELL = /bin/bash

SHORT_NAME = draky

ifndef VERSION
	override VERSION = local-build
endif

# Version processed.
VER = $(shell echo ${VERSION} | sed 's/^v//g')

ROOT = $(shell pwd -P)
DIST_PATH = ${ROOT}/dist
TEMPLATE_RENDERER_SCRIPT = ${ROOT}/template-renderer.sh

build:
	[ ! -d "${DIST_PATH}" ] || rm -r "${DIST_PATH}"
	mkdir -p ${DIST_PATH}
	TEMPLATE_VERSION=${VER} ${TEMPLATE_RENDERER_SCRIPT} -t ${ROOT}/draky-entrypoint.addon.dk.yml.template -o ${DIST_PATH}/draky-entrypoint.addon.dk.yml
	cp ${ROOT}/src/* ${DIST_PATH}/
	find ${DIST_PATH} -type f -name "*.sh" -exec chmod 755 {} \;
