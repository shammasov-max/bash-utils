#!/bin/bash
docker-compose down
docker-compose rm
docker rm -f $(docker ps -a -q)
docker volume rm $(docker volume ls -q)
rm -rf ./.volumes