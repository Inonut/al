#!/usr/bin/env bash
#set -x

function asd() {
  echo "$USER"
  asd3
}

function asd3() {
  echo asd3
}

eval 'asd'
