#!/bin/bash -eu

if [[ "$#" -lt 2 ]]; then
  echo "Usage: query.sh <command> <graph JSON> [argument]" 1>&2
  exit 1
fi

COMMAND="$1"
GRAPH="$2"

if [[ "$#" -gt 2 ]]; then
  ARG="$3"
else
  ARG=""
fi

LIBDIR="$(dirname "$(readlink -f "$0")")"

jq -C -L "$LIBDIR" -f "$LIBDIR/$COMMAND".jq "$GRAPH" --arg arg "$ARG"
