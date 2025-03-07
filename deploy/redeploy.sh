#!/bin/sh

docker rm -f ${DOCKER_IMAGE_NAME}
docker rmi ${DOCKER_IMAGE}
docker pull ${DOCKER_IMAGE}
docker run -d --restart unless-stopped -p 80:8000 --name=${DOCKER_IMAGE_NAME} ${DOCKER_IMAGE}

docker rm -f ${DOCKER_IMAGE_NAME_CONTAINER}
docker rmi ${DOCKER_IMAGE_CONTAINER}
docker pull ${DOCKER_IMAGE_CONTAINER}
docker run -d --restart unless-stopped -p 81:8000 --name=${DOCKER_IMAGE_NAME_CONTAINER} ${DOCKER_IMAGE_CONTAINER}

