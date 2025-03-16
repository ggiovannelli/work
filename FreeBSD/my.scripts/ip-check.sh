#!/bin/sh
#

args=`getopt aon: $*`
if [ $? -ne 0 ]; then
    echo "Usage: $0 -n network/mask [-a|-o]"
    exit 2
fi
set -- $args

while :; do
    case "$1" in
                   -a)
                           aflag="${1}"
                           shift
                           ;;
                   -o)
                           oflag="${1}"
                           shift
                           ;;
                   -n)
                           narg="$2"
                           shift; shift
                           ;;
                   --)
                           shift; break
                           ;;
   esac
done

NMAP=$(which nmap)
if [ ! -x ${NMAP} ]
then
    echo Install pkg nmap
    exit
fi

if [ -z "$narg" ]
then
    echo "Usage: $0 -n network/mask [-a|-o]"
    exit 2
fi

if ([ ! -z "$aflag" ] && [ ! -z "$oflag" ])
then
    echo "Usage: $0 -n network/mask [-a|-o]"
    exit 2
fi

if ([ -z "$aflag" ] && [ -z "$oflag" ])
then
    aflag="-a"
fi

if [ "$aflag" = "-a" ]
then
    echo IP alive:
    nmap -n -v -sn $narg -oG - | awk '/Up$/{print $2}' | sort -t"." -k1,1n -k2,2n -k3,3n -k4,4n
    exit
fi

if [ "$oflag" = "-o" ]
then
    echo IP not answered:
    nmap -n -v -sn $narg -oG - | awk '/Down$/{print $2}' | sort -t"." -k1,1n -k2,2n -k3,3n -k4,4n
    exit
fi
