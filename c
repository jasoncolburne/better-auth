#!/bin/bash

# Start with the base command
cmd=(claude)

# Add all matching directories
for dir in ../better-auth-*; do
    if [ -d "$dir" ]; then
        cmd+=(--add-dir "$dir")
    fi
done

# Add any additional arguments passed to this script
cmd+=("$@")

# Execute the command
"${cmd[@]}"
