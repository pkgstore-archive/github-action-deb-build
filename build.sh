#!/bin/bash -e

# -------------------------------------------------------------------------------------------------------------------- #
# INITIALIZATION.
# -------------------------------------------------------------------------------------------------------------------- #

init() {
  # Vars.
  GIT_REPO_SRC="${1}"
  GIT_REPO_DST="${2}"
  GIT_USER="${3}"
  GIT_EMAIL="${4}"
  GIT_TOKEN="${5}"
  OBS_USER="${6}"
  OBS_PASSWORD="${7}"
  OBS_TOKEN="${8}"
  OBS_PROJECT="${9}"
  OBS_PACKAGE="${10}"

  # Apps.
  curl="$( command -v curl )"
  date="$( command -v date )"
  dpkg_source="$( command -v dpkg-source )"
  git="$( command -v git )"
  mv="$( command -v mv )"
  rm="$( command -v rm )"
  sleep="$( command -v sleep )"
  tar="$( command -v tar )"
  tee="$( command -v tee )"
  ts="$( _timestamp )"

  # Dirs.
  d_src="/root/git/repo_src"
  d_dst="/root/git/repo_dst"

  # Git config.
  ${git} config --global user.name "${GIT_USER}"
  ${git} config --global user.email "${GIT_EMAIL}"
  ${git} config --global init.defaultBranch 'main'

  # Commands.
  cmd_src_build="${dpkg_source} -i --build _build/"

  # Run.
  git_clone \
    && ( ( pkg_orig_pack && pkg_src_build && pkg_src_move ) 2>&1 ) | ${tee} "${d_src}/build.log" \
    && git_push \
    && obs_upload \
    && obs_trigger
}

# -------------------------------------------------------------------------------------------------------------------- #
# GIT: CLONE REPOSITORIES.
# -------------------------------------------------------------------------------------------------------------------- #

git_clone() {
  echo "--- [GIT] CLONE: ${GIT_REPO_SRC#https://} & ${GIT_REPO_DST#https://}"

  SRC="https://${GIT_USER}:${GIT_TOKEN}@${GIT_REPO_SRC#https://}"
  DST="https://${GIT_USER}:${GIT_TOKEN}@${GIT_REPO_DST#https://}"

  ${git} clone "${SRC}" "${d_src}" \
    && ${git} clone "${DST}" "${d_dst}"

  echo "--- [GIT] LIST: '${d_src}'"
  ls -1 "${d_src}"

  echo "--- [GIT] LIST: '${d_dst}'"
  ls -1 "${d_dst}"
}

# -------------------------------------------------------------------------------------------------------------------- #
# PACKING: "*.ORIG" FILES.
# -------------------------------------------------------------------------------------------------------------------- #

pkg_orig_pack() {
  echo "--- [SYSTEM] PACK: '${OBS_PACKAGE}' (*.orig.tar.xz)"
  _pushd "${d_src}" || exit 1

  # Set package version.
  PKG_VER="1.0.0"
  for i in "${OBS_PACKAGE}-"*; do PKG_VER=${i##*-}; break; done;

  # Check '*.orig.tar.*' file.
  for i in *.orig.tar.*; do
    if [[ -f ${i} ]]; then
      echo "File '${i}' found!"
    else
      echo "File '*.orig.tar.*' not found! Creating..."
      SOURCE="${OBS_PACKAGE}-${PKG_VER}"
      TARGET="${OBS_PACKAGE}_${PKG_VER}.orig.tar.xz"
      ${tar} -cJf "${TARGET}" "${SOURCE}"
      echo "File '${TARGET}' created!"
    fi
    break
  done

  _popd || exit 1
}

# -------------------------------------------------------------------------------------------------------------------- #
# BUILD: PACKAGE.
# -------------------------------------------------------------------------------------------------------------------- #

pkg_src_build() {
  echo "--- [SYSTEM] BUILD: '${GIT_REPO_SRC#https://}'"
  _pushd "${d_src}" || exit 1

  # Run build.
  ${cmd_src_build}

  # Check build status.
  for i in *.dsc; do
    if [[ -f ${i} ]]; then
      echo "File '${i}' found!"
      echo "Build completed!"
    else
      echo "File '*.dsc' not found!"
      exit 1
    fi
    break
  done

  _popd || exit 1
}

# -------------------------------------------------------------------------------------------------------------------- #
# MOVE: PACKAGE TO DEBIAN PACKAGE STORE REPOSITORY.
# -------------------------------------------------------------------------------------------------------------------- #

pkg_src_move() {
  echo "--- [SYSTEM] MOVE: '${d_src}' -> '${d_dst}'"

  # Remove old files from 'd_dst'.
  echo "Removing old files from repository..."
  ${rm} -fv "${d_dst}"/*

  # Move new files from 'd_src' to 'd_dst'.
  echo "Moving new files to repository..."
  for i in _service _meta README.md LICENSE *.tar.* *.dsc *.log; do
    ${mv} -fv "${d_src}"/${i} "${d_dst}" || exit 1
  done
}

# -------------------------------------------------------------------------------------------------------------------- #
# GIT: PUSH PACKAGE TO DEBIAN PACKAGE STORE REPOSITORY.
# -------------------------------------------------------------------------------------------------------------------- #

git_push() {
  echo "--- [GIT] PUSH: '${d_dst}' -> '${GIT_REPO_DST#https://}'"
  _pushd "${d_dst}" || exit 1

  # Commit build files & push.
  echo "Commit build files & push..."
  ${git} add . && ${git} commit -a -m "BUILD: ${ts}" && ${git} push

  _popd || exit 1
}

# -------------------------------------------------------------------------------------------------------------------- #
# UPLOAD: "_META" & "_SERVICE" FILES TO OBS.
# -------------------------------------------------------------------------------------------------------------------- #

obs_upload() {
  echo "--- [OBS] UPLOAD: '${OBS_PROJECT}/${OBS_PACKAGE}'"

  # Upload '_meta'.
  echo "Uploading '${OBS_PROJECT}/${OBS_PACKAGE}/_meta'..."
  ${curl} -u "${OBS_USER}":"${OBS_PASSWORD}" -X PUT -T \
    "${d_dst}/_meta" "https://api.opensuse.org/source/${OBS_PROJECT}/${OBS_PACKAGE}/_meta"

  # Upload '_service'.
  echo "Uploading '${OBS_PROJECT}/${OBS_PACKAGE}/_service'..."
  ${curl} -u "${OBS_USER}":"${OBS_PASSWORD}" -X PUT -T \
    "${d_dst}/_service" "https://api.opensuse.org/source/${OBS_PROJECT}/${OBS_PACKAGE}/_service"

  ${sleep} 5
}

# -------------------------------------------------------------------------------------------------------------------- #
# RUN: BUILD PACKAGE IN OBS.
# -------------------------------------------------------------------------------------------------------------------- #

obs_trigger() {
  echo "--- [OBS] TRIGGER: '${OBS_PROJECT}/${OBS_PACKAGE}'"
  ${curl} -H "Authorization: Token ${OBS_TOKEN}" -X POST \
    "https://api.opensuse.org/trigger/runservice?project=${OBS_PROJECT}&package=${OBS_PACKAGE}"
}

# -------------------------------------------------------------------------------------------------------------------- #
# ------------------------------------------------< COMMON FUNCTIONS >------------------------------------------------ #
# -------------------------------------------------------------------------------------------------------------------- #

# Pushd.
_pushd() {
  command pushd "$@" > /dev/null || exit 1
}

# Popd.
_popd() {
  command popd > /dev/null || exit 1
}

# Timestamp.
_timestamp() {
  ${date} -u '+%Y-%m-%d %T'
}

# -------------------------------------------------------------------------------------------------------------------- #
# -------------------------------------------------< INIT FUNCTIONS >------------------------------------------------- #
# -------------------------------------------------------------------------------------------------------------------- #

init "$@"; exit 0
