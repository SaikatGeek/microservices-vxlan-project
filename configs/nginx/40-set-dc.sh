#!/bin/sh
# Runs inside the container when it starts. The nginx image runs every
# script in /docker-entrypoint.d/ before nginx itself.
#
# It swaps __DC__ for the value of $DC in the response files, so one image
# answers "DC1" when started in DC1 and "DC3" when started in DC3.
# Start the container with:  -e DC=DC1
set -eu

DC="${DC:-UNKNOWN}"

for f in /usr/share/nginx/html/*; do
    [ -f "$f" ] && sed -i "s/__DC__/$DC/g" "$f"
done

echo "datacenter set to $DC"
