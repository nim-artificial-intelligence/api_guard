#!/usr/bin/env bash

AUTH_TOKEN=renerocksai

curl -H "Authorization: $AUTH_TOKEN" http://localhost:5500/api_guard/request_access
