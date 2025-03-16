#!/bin/sh
#

args=`getopt nh $*`
if [ $? -ne 0 ]; then
    echo "Usage: $0 [-n|-h] len (def=8)"
    exit 2
fi
set -- $args

while :; do
    case "$1" in
         -n)
                  nflag="${1}"
                  shift
                  ;;
         -h)
                  echo "Usage: $0 [-n=numbers only |-h=this help] len=string length  (default=8)"
                  exit
                  ;;
         --)
                  shift; break
                  ;;
   esac
done

if [ -z "$1" ]
then
    LEN=8
else
    LEN=$1
fi

if [ -z $nflag ]
then
    # date | md5sum | ( head -c $LEN && echo )
    # openssl rand -hex $(($LEN/2))
    openssl rand -base64 200 | xargs | tr -d " "/=+ | cut -c -$LEN
else
    jot -r $LEN 0 9 | xargs | tr -d " "
fi
