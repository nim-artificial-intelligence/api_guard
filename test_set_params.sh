#!/usr/bin/env bash

AUTH_TOKEN=${AUTH_TOKEN:-renerocksai}

curl \
    -X POST                                             \
    -d '{"new_limit":100, "new_delay":50}'              \
    -H "Authorization: $AUTH_TOKEN"                     \
    -H "Content-Type: application/json"                 \
    http://localhost:5500/api_guard/set_rate_limit

