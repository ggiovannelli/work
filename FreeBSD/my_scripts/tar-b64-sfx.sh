#!/bin/sh

if [ $# -lt 1 ]
then
      echo
      echo "Syntax: $0 files1 files2 ..."
      echo
      exit
fi

tar cpPf - $@ | gzip -9 | base64 | awk 'BEGIN {printf("( base64 -d | tar zwxPpvf - ) <<EOF\n")} {print} END {printf("EOF\n")}'