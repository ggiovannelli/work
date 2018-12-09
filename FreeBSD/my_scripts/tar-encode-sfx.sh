#!/bin/sh

if [ $# -lt 1 ]
then
      echo
      echo "Sintassi: $0 files1 files2 ..."
      echo
      exit
fi

tar -cpPf - $@ | gzip -9 | xxd -p -c 40 | awk 'BEGIN {printf("(xxd -p -r | tar -zxPpvf -) <<EOF\n")} {print} END { printf("EOF\n")}'
