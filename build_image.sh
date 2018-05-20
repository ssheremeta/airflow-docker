#!/usr/bin/env bash

docker build --network="host" -t local/airflow-base:1.9.0 .
