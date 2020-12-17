#!/bin/bash

set -o errexit -o pipefail -o noclobber -o nounset

# -allow a command to fail with !’s side effect on errexit
# -use return value from ${PIPESTATUS[0]}, because ! hosed $?
! getopt --test > /dev/null
if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
    echo 'I’m sorry, `getopt --test` failed in this environment.'
    exit 1
fi

OPTIONS=p:u:h?
LONGOPTS=password:,user:,help

# -regarding ! and PIPESTATUS see above
# -temporarily store output to be able to check for errors
# -activate quoting/enhanced mode (e.g. by writing out “--options”)
# -pass arguments only via   -- "$@"   to separate them correctly
! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    # e.g. return value is 1
    #  then getopt has complained about wrong arguments to stdout
    exit 2
fi
# read getopt’s output this way to handle the quoting right:
eval set -- "$PARSED"

USERNAME=''
PASSWORD=''
FILENAME=''

function printHelp() {
    me="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")";
    echo "usage: $me";
}

while true; do
    case "$1" in
        -u|--user)
            USERNAME="$2"
            shift 2
            ;;
        -p|--password)
            PASSWORD="$2"
            shift 2
            ;;
        --help|h|?)
            printHelp
            shift 2
            ;;
        --)
            shift
            break
            ;;
    esac
done

# handle non-option arguments
if [[ $# -ne 1 ]]; then
    echo "$0: A single input file is required."
    exit 4
fi

if [ -z "$USERNAME" ]
then
        echo -n "Username:"
        read USERNAME
fi

if [ -z "$PASSWORD" ]
then
        echo -n "Password:"
        read -s PASSWORD
fi

SALT="$(openssl rand 3)"
SHA1="$(printf "%s%s" "$PASSWORD" "$SALT" | openssl dgst -binary -sha1)"


UH=$(printf "${USERNAME}:{SSHA}%s\n" "$(printf "%s%s" "$SHA1" "$SALT" | base64)")

echo "$UH" >> "$1"