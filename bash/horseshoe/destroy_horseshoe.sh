#!/usr/bin/env bash

./stop_horseshoe.sh
docker container rm mysql1 mysql2 mysql3 mysql4
