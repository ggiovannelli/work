#!/bin/sh
#
# Random string generator for FreeBSD
# Usage: randstr [-n|-a|-A|-s|-x|-h] [length]

# Default values
LENGTH=8
CHARSET="[:alnum:]"

# Function to display usage
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [length]

Generate random strings with various character sets.

OPTIONS:
    -n          Numeric only [:digit:]
    -l          Lowercase alphanumeric [:lower:][:digit:]
    -a          Alphabetic only [:alpha:]
    -A          Alphanumeric [:alnum:] (default)
    -s          All printable [:print:]
    -x          Hexadecimal [:xdigit:]
    -u          Uppercase alphanumeric [:upper:][:digit:]
    -h          Display this help message

ARGUMENTS:
    length      String length (default: 8)

EXAMPLES:
    $(basename "$0")              # 8-char alphanumeric string
    $(basename "$0") 16           # 16-char alphanumeric string
    $(basename "$0") -n 6         # 6-digit number
    $(basename "$0") -s 12        # 12-char printable string
    $(basename "$0") -x 32        # 32-char hex string

EOF
    exit 0
}

# Parse options using getopts
while getopts "nlAasxuh" opt; do
    case $opt in
        n)
            CHARSET="[:digit:]"
            ;;
        l)
            CHARSET="[:lower:][:digit:]"
            ;;
        a)
            CHARSET="[:alpha:]"
            ;;
        A)
            CHARSET="[:alnum:]"
            ;;
        s)
            CHARSET="[:print:]"
            ;;
        x)
            CHARSET="[:xdigit:]"
            ;;
        u)
            CHARSET="[:upper:][:digit:]"
            ;;
        h)
            usage
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
    esac
done

# Shift past the options
shift $((OPTIND - 1))

# Get length from remaining argument
if [ -n "$1" ]; then
    LENGTH="$1"
    # Validate length is a positive integer
    case "$LENGTH" in
        ''|*[!0-9]*)
            echo "Error: Length must be a positive integer" >&2
            exit 1
            ;;
        0)
            echo "Error: Length must be greater than 0" >&2
            exit 1
            ;;
    esac
fi

# Generate random string using /dev/random or /dev/urandom
# FreeBSD has both, /dev/urandom is non-blocking
if [ -c /dev/urandom ]; then
    RANDOM_SOURCE="/dev/urandom"
elif [ -c /dev/random ]; then
    RANDOM_SOURCE="/dev/random"
else
    echo "Error: No random device found" >&2
    exit 1
fi

# Generate the random string
LC_ALL=C tr -dc "$CHARSET" < "$RANDOM_SOURCE" | dd bs=1 count="$LENGTH" 2>/dev/null
echo
