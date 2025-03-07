#!/bin/sh

docker rm -f ${DOCKER_IMAGE_NAME}
docker rmi ${DOCKER_IMAGE}
docker pull ${DOCKER_IMAGE}
docker run -d --restart unless-stopped -p 80:8000 --name=${DOCKER_IMAGE_NAME} ${DOCKER_IMAGE}

docker rm -f ${DOCKER_IMAGE_NAME}_2
docker rmi ${DOCKER_IMAGE}_2
docker pull ${DOCKER_IMAGE}_2
docker run -d --restart unless-stopped -p 81:8000 --name=${DOCKER_IMAGE_NAME}_2 ${DOCKER_IMAGE}_2

