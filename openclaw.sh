#!/bin/bash

cd /app
# exec xvfb-run -a node dist/index.js "$@"
exec node openclaw.mjs "$@"
