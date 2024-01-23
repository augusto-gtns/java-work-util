# https://www.gnu.org/software/make/manual/make.html

SHELL=/bin/bash

CURRENT_DIR=$(shell pwd)
FUNCTION_DIR=.. # set relative path to functions.sh

# build maven module
maven-build:
	@cd $(FUNCTION_DIR) && source functions.sh "$(CURRENT_DIR)" && \
	validate_folder && \
	maven_build

# run spring app
run-spring:
	@cd $(FUNCTION_DIR) && source functions.sh "$(CURRENT_DIR)" && \
	validate_folder && \
	maven_build && \
	run_spring_boot

# build docker image
docker-build:
	@cd $(FUNCTION_DIR) && source functions.sh "$(CURRENT_DIR)" && \
    validate_folder && \
	docker_build

# start docker service
docker-start:
	@cd $(FUNCTION_DIR) && source functions.sh "$(CURRENT_DIR)" && \
	validate_folder && \
	docker_start

# push docker image to registry
docker-push:
	@cd $(FUNCTION_DIR) && source functions.sh "$(CURRENT_DIR)" && \
	validate_container_release_branch && \
	docker_push

# build docker image and start service
docker-build-start: 
	@cd $(FUNCTION_DIR) && source functions.sh "$(CURRENT_DIR)" && \
	validate_folder && \
	docker_build && \
	docker_start

# build docker image and push to registry
docker-build-push:
	@cd $(FUNCTION_DIR) && source functions.sh "$(CURRENT_DIR)" && \
	validate_container_release_branch && \
	docker_full_build && \
	docker_push

# stop all services from compose
docker-stop-all:
	@cd $(FUNCTION_DIR) && source functions.sh "$(CURRENT_DIR)" && \
	docker_stop_all

# remove all services from compose
docker-down-all: 
	@cd $(FUNCTION_DIR) && source functions.sh "$(CURRENT_DIR)" && \
	docker_down_all

# build docker native image
docker-native-build:
	@cd $(FUNCTION_DIR) && source functions.sh "$(CURRENT_DIR)" && \
	validate_folder && \
	docker_native_build_simple

# build docker native image and start service
docker-native-build-start: 
	@cd $(FUNCTION_DIR) && source functions.sh "$(CURRENT_DIR)" && \
	validate_folder && \
	docker_native_build_simple && \
	docker_start

# build docker native image and push to registry
docker-native-build-push:
	@cd $(FUNCTION_DIR) && source functions.sh "$(CURRENT_DIR)" && \
	validate_container_release_branch && \
	docker_native_build_full && \
	docker_push

# deploy java artifact to registry
deploy-artifact:
	@cd $(FUNCTION_DIR) && source functions.sh "$(CURRENT_DIR)" && \
	validate_sdk_release_branch && \
	maven_deploy