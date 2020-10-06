#!/usr/bin/env bash
#set -x

function asd() {
  echo "$USER"
  asd3
}

function aa() {
  echo asd3
}

if [[ "$(type -t load_given_variable)" == function ]]; then
  load_given_variable
else
  echo 'aaa'
fi

echo "$SUDO_USER"
