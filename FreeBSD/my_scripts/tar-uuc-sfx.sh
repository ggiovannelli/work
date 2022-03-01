#!/bin/sh


DATA=`/bin/date "+%Y%m%d%H%M"`
HOSTNAME=`/bin/hostname`

if [ $# -lt 1 ]
then
      echo
      echo "Syntax: $0 files1 files2 ..."
      echo
      exit
fi

tar -cpPf - $@ | gzip -9 | uuencode -m ${DATA}-${HOSTNAME}-tar-encoded-sfx.tgz | awk 'BEGIN {printf("( uudecode -o /dev/stdout | tar zxwPpvf - ) <<EOF\n")} {print} END { printf("EOF\n")}'
