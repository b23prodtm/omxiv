#!/usr/bin/env bash
set -e
scriptd=$(dirname ${BASH_SOURCE[0]})
setMARKERS(){
  export MARK_BEGIN="$1"
  export MARK_END="$2"
}
comment() {
  [ "$#" -eq 0 ] && echo "missing file input" && exit 0
  sed -i.old -E -e "s/[# ]*(${MARK_BEGIN})/# \\1/g" -e "s/[# ]*(${MARK_END})/# \\1/g" $1;
}
uncomment() {
  [ "$#" -eq 0 ] && echo "missing file input" && exit 0
  sed -i.old -E -e "s/[# ]+(${MARK_BEGIN})/\\1/g" -e "s/[# ]+(${MARK_END})/\\1/g" $1;
}
setMARKERS "RUN \[ \"cross-build-start\" \]" "RUN \[ \"cross-build-end\" \]"
usage="Usage ${BASH_SOURCE[0]} <arch> [--local|--balena|--nobuild]"
arch=$1
target=$2
while [ true ]; do
  case $arch in
    1|arm32*|armv7l|armhf)
      arch="arm32v7"
      break;;
    2|arm64*|aarch64)
      arch="arm64v8"
      break;;
    3|amd64|x86_64)
      arch="amd64"
      break;;
    *)
      echo $usage
      read -p "Set docker machine architecture ARM32, ARM64 bits or X86-64 (choose 1, 2 or 3) ? " arch
      ;;
  esac
done
ln -vsf $scriptd/${arch}.env .env
eval $(cat $scriptd/${arch}.env)
function setArch() {
  [ ! -f $1 ] && printf "no such file $1" && return
  while [ "$#" -gt 1 ]; do
    cp -f $1 $1.old
    sed -E -e "s/%%BALENA_MACHINE_NAME%%/${BALENA_MACHINE_NAME}/g" \
    -e "s/(Dockerfile\.)[^\.]*/\\1${DKR_ARCH}/g" \
    -e "s/(DKR_ARCH[=:-]+)[^\$ }]+/\\1${DKR_ARCH}/g" \
    -e "s/(IMG_TAG[=:-]+)[^\$ }]+/\\1${IMG_TAG}/g" \
    -e "s/(PHP_OWNER[=:-]+)[^\$ }]+/\\1${PHP_OWNER}/g" \
    $1 | tee $2 > /dev/null
  shift; shift; done
}
setArch $scriptd/docker-compose.yml $scriptd/docker-compose.${DKR_ARCH}
declare -a projects=(".")
for d in ${projects[@]}; do
  setArch $scriptd/$d/Dockerfile.template $scriptd/$d/Dockerfile.${DKR_ARCH}
  pwd=`pwd` && cd $scriptd/$d
  git commit -a -m "${DKR_ARCH} pushed to balena.io" || true
  cd $pwd
done
eval $(cat $scriptd/${arch}.env | grep BALENA_MACHINE_NAME)
while [ true ]; do
  eval $(ssh-agent)
  ssh-add ~/.ssh/*id_rsa
  case $target in
    1|--local)
      echo "Allow cross-build"
      for d in ${projects[@]}; do
        [ "$arch" != "amd64" ] && uncomment $scriptd/$d/Dockerfile.${DKR_ARCH} || comment $scriptd/$d/Dockerfile.${DKR_ARCH}
      done
      [ $(which balena) > /dev/null ] && declare -a apps=($(sudo balena scan | awk '/address:/{print $2}'))
      i="1..${#apps}"; echo "$i: ${apps[@]}"
      read -p "Where do you want to push [1-${#apps}] ? " appName
      if [ $(which balena) > /dev/null ]; then
        sudo balena push ${apps[$appName-1]}
      else
        git push -uf balena ${apps[$appName-1]}
      fi
      break;;
    4|--docker)
      echo "Allow cross-build"
      for d in ${projects[@]}; do
        [ "$arch" != "amd64" ] && uncomment $scriptd/$d/Dockerfile.${DKR_ARCH} || comment $scriptd/$d/Dockerfile.${DKR_ARCH}
      done
      file=docker-compose.${DKR_ARCH}
      if [ -f $file ]; then
        bash -c "docker-compose -f $file --host ${DOCKER_HOST:-''} build"
      else
        bash -c "docker build -f Dockerfile.${DKR_ARCH} . && docker ps"
      fi
      break;;
    2|--balena)
      echo "Deny cross-build"
      for d in ${projects[@]}; do
        comment $scriptd/$d/Dockerfile.template
      done
      [ $(which balena) > /dev/null ] && declare -a apps=($(sudo balena apps | awk '{if (NR>1) print $2}'))
      i=0
      for app in ${apps[@]}; do
        i=$(($i + 1))
        printf "[%s]: %s " "${i}" "${app}"
      done
      read -p "Where do you want to push [1-${#apps}] ? " appName
      printf "%s was selected\n" "${apps[$appName-1]}"
      file=docker-compose.${DKR_ARCH}
      if [ -f $file ]; then
        cp -f $scriptd/docker-compose.yml $scriptd/docker-compose.yml.old
        cp -f $scriptd/docker-compose.${DKR_ARCH} $scriptd/docker-compose.yml
      fi
      if [ $(sudo which balena) > /dev/null ]; then
        sudo balena push ${apps[$appName-1]} || true
      else
        git push -uf balena ${apps[$appName-1]} || true
      fi
      if [ -f $file ]; then
        cp -f $scriptd/docker-compose.yml.old $scriptd/docker-compose.yml
      fi
      break;;
    3|--nobuild)
      break;;
    *)
      read -p "What target docker's going to use (1:local-balena, 2:balena, 3:nobuilt, 4:docker) ?" target
      ;;
  esac
done
