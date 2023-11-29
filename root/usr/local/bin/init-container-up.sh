#!/command/with-contenv bash

shopt -s globstar
for i in /usr/local/bin/init-container-up-*.sh; do # Whitespace-safe and recursive
    echo "*** Process file ""$i"" ***"
    bash -c "$i"
done
