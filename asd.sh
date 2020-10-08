#!/usr/bin/env bash
#set -x

function asd() {
  echo "$USER"
  asd3
}

function aa() {
  echo asd3
}


asd='

    ads
    asda


    aaa


'
asa=(5 6 a)
asdd=(5 6 a)
asddd=(5 6 a)
ccc="aaaa"
cccc=true


declare -p | pcregrep -M " cccc=((\(.*\))|(\"((\n|.)*?)\"))"
