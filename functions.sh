#!/bin/bash

# set up error handling
set -eET
trap 'echo "ERROR in $0 file at line $LINENO (code $?)"' ERR

# source env vars
source .env 1>/dev/null 2>&1 || true
if [ -z "${TAG_VERSION+x}" ]; then TAG_VERSION="latest"; fi # provide default value if var is unset

# check required dependencies
for x in mvn docker git sed awk; do
  [[ "$(which $x)" == "" ]] && echo "ERROR: '$x' is a required dependency and should be installed." && exit 1
done

folder=$1

###
# functions
###

_is_java() { # 0=true, 1=false
  if [ "${PWD##*/}" == "$folder" ]; then
    if [ -f "pom.xml" ]; then return 0; fi
  else
    if [ -f "$folder/pom.xml" ]; then return 0; fi
  fi
  return 1;
}

_build_image_base_name(){
	echo "$folder" | sed s/\\//-/g # replace "/" per "-" to handle nested folders
}

_build_image_name(){
  echo "$(_build_image_base_name):$TAG_VERSION"
}

_build_image_full_name(){
  echo "$REGISTRY/$(_build_image_name)"
}

_build_module_name(){
  echo "$folder" | grep -oE "[^/]+$" # get last occurrence after "/"
}

_is_multi_branch(){
  local branch=$1

  local branch_array=($(_split_branch_name $branch))
  local svc_major_minor=${branch_array[1]}
  if [[ $svc_major_minor =~ "/" ]]; then # handle multi repo (branch pattern: release*/service/major.minor )
    return 0 # true
  else # handle mono repo (branch pattern: release*/major.minor)
    return 1 # false
  fi
}

_build_git_tag_name(){
  local branch=$1
  if _is_multi_branch "$branch"; then # handle multi repo (branch pattern: release*/service/major.minor )
    echo "$(_build_image_base_name)/$TAG_VERSION"
  else # handle mono repo (branch pattern: release*/major.minor)
    echo "$TAG_VERSION"
  fi
}

_check_image_tag_already_exists(){
  docker manifest inspect "$(_build_image_full_name)" 1>/dev/null 2>&1
}

_check_git_tag_already_exists(){
  local tag_name=$1
  git show "$tag_name" 1>/dev/null 2>&1
}

_split_branch_name(){
  local branch=$1 # supported patterns: release*/service_name/major.minor, release*/major.minor
  echo "$branch" | sed s/\\//" "/ # replace first occurrence of "/" per " " to split in array
}

_discovery_tag_version(){
  local branch=$1
  local branch_array=($(_split_branch_name $branch))
  local svc_major_minor=${branch_array[1]}

  local patch="0"
  # list remote tags | get second column | cleanup string | filter by version | remove non digits or dot | order numerically
  local tags_array=($(git ls-remote --tags origin | awk '{print $2}' | sed s/"refs\\/tags\\/"//g | grep -v "\\^{}" | grep "^$svc_major_minor" | sed 's/[^0-9\\.]//g' | sort -n || true))

  if [[ ${#tags_array[@]} -gt 0 ]]; then # tags is not empty
    local last_tag=${tags_array[-1]} # get last tag
    local last_tag_array=($(echo "$last_tag" | sed s/\\./" "/g)) # replace "." per " " to split in array

    local patch=${last_tag_array[-1]}
    local git_tag="$svc_major_minor.$patch"

    # check if the current commit is different from the last tag commit
    local current_commit=$(git rev-parse HEAD)
    if [[ "$(git describe --exact-match $current_commit 2>&1)" != "$git_tag" ]]; then
      patch="$(( $patch + 1 ))" # arithmetic expansion and increment last patch
    fi
  fi

  local major_minor=$(echo "$svc_major_minor" | grep -oE "[^/]+$") # get last occurrence after "/"
  echo "$major_minor.$patch"
}

_validate_release_branch(){
  local type="$1"
  local branch=$(git rev-parse --abbrev-ref HEAD)

  validate_folder
  if [[ "$branch" == release* ]]; then # is release branch

    image_base_name="$(_build_image_base_name)/"
    if _is_multi_branch "$branch" && ! [[ "$branch" =~ $image_base_name ]]; then
      echo "🚫 invalid usage when working on a release branch '$branch' from folder '$folder'" && exit 1
    fi

    export TAG_VERSION="$(_discovery_tag_version $branch)"
    read -p "⚠️ working on branch '$branch', automatically detected version '$TAG_VERSION' (press Enter to continue)";

    if _is_java; then
      mvn -U clean test -pl :$(_build_module_name) -am -s .mvn/settings.xml || exit 1
      mvn versions:set -DnewVersion=$TAG_VERSION
      git add "*pom.xml"
      git commit "*pom.xml" -m "release: bump pom version (automatic)" 1>/dev/null 2>&1 || true
    fi

    local git_tag_name=$(_build_git_tag_name "$branch")
    if ! _check_git_tag_already_exists "$git_tag_name"; then
      read -p "⚠️ git tag '$git_tag_name' doesn't exists and will be created/pushed (press Enter to continue)"
      git tag "$git_tag_name" -m ""
      git push origin "$git_tag_name"
    fi

    if [ "$type" == "container" ] && _check_image_tag_already_exists; then
      echo "🚫 the image tag '$(_build_image_full_name)' already exists and SHOULD NOT be overwritten";
      exit 1
    fi

  else # is regular branch

    if [ "$type" == "container" ] && _check_image_tag_already_exists; then
      read -p "⚠️ the image tag '$(_build_image_full_name)' already exists and will be overwritten (press Enter to continue)";
    else
      read -p "working on branch '$branch', detected version '$TAG_VERSION' (press Enter to continue)";
    fi
  fi
}

_confirm_maven_deploy(){
  local confirm=""
  while [[ "$confirm" != "y" && "$confirm" != "n" ]]; do
    read -r -e -p "Are you sure to deploy the artifact '$(_build_module_name):$TAG_VERSION'? (y/n): " confirm
  done
  if [[ "$confirm" == "n" ]]; then exit 0; fi
}

###

validate_folder(){
  if [ "$folder" == "" ]; then echo "ERROR: folder is required"; exit 1; fi
  if [ ! -d "$folder" ]; then echo "ERROR: folder '$folder' doesn't exists" && exit 1; fi

  if [[ "$folder" == "$(pwd)" ]]; then
    folder=$(echo "$folder" | grep -oE "[^/]+$") # get last occurrence after "/"
  else
    folder=${folder#$(pwd)}; # remove a substring from the beginning
  fi

  if [[ "${folder:0:1}" == "/" ]]; then folder="${folder:1}"; fi # if folder starts with "/", remove it
  if [[ "${folder: -1}" == "/" ]]; then folder="${folder%"/"}"; fi # if folder ends with "/", remove it
}

maven_build(){
  mvn -U clean install -pl :$(_build_module_name) -am -DskipTests -s .mvn/settings.xml || exit 1
}

run_spring_boot(){
  pushd "$folder" || exit 1 # go to folder
  mvn spring-boot:run -Dspring-boot.run.profiles=dev -s .mvn/settings.xml || exit 1
  popd || exit 1 # pop last folder
}

docker_build(){
  if _is_java; then
    maven_build
  fi

  docker compose build "$(_build_image_base_name)" || exit 1
}

docker_full_build(){
  if _is_java; then
    mvn -U clean install -pl :$(_build_module_name) -am -DskipTests -s .mvn/settings.xml || exit 1
  fi

  # build image without cache
  docker compose build "$(_build_image_base_name)" --no-cache || exit 1
}

docker_native_build(){
  if ! _is_java; then
    echo "not supported for $folder"
    exit 1;
  fi

  local origin_path="$(pwd)"
  pushd "$folder" || exit 1 # go to folder
  mvn -U clean spring-boot:build-image -Pnative -DskipTests -s $origin_path/.mvn/settings.xml
  popd || exit 1 # pop last folder

  # rename image generate by spring-boot to point to our private registry
  docker image tag "$(_build_image_name)" "$(_build_image_full_name)" || exit 1
}

docker_start(){
  local image_base_name=$(_build_image_base_name)

  docker compose up -d "$image_base_name" || exit 1

  while [[ "$confirm" != "y" && "$confirm" != "n" ]]; do
    read -r -e -p "follow $image_base_name container logs? (y/n): " confirm
  done
  [[ "$confirm" == "n" ]] && exit 0

  docker compose logs "$image_base_name" -f
}

docker_push(){
  local confirm=""
  while [[ "$confirm" != "y" && "$confirm" != "n" ]]; do
    read -r -e -p "Are you sure to push image tag $(_build_image_full_name)? (y/n): " confirm
  done
  [[ "$confirm" == "n" ]] && exit 0

  docker compose push "$(_build_image_base_name)" || exit 1
}

validate_container_release_branch(){
  _validate_release_branch "container"
}

docker_stop_all(){
  docker compose --profile dev stop || exit 1
}

docker_down_all(){
  docker compose --profile dev down -v || exit 1
}

validate_sdk_release_branch(){
  _validate_release_branch "sdk"
}

maven_deploy_am(){
  _confirm_maven_deploy
  mvn clean source:jar deploy -pl :$(_build_module_name) -am -DskipTests -s .mvn/settings.xml || exit 1
}

maven_deploy(){
  _confirm_maven_deploy
  mvn clean source:jar deploy -pl :$(_build_module_name) -DskipTests -s .mvn/settings.xml || exit 1
}