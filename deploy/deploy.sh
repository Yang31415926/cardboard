#!/bin/bash

if [ "$TRAVIS_PULL_REQUEST" == 'false' ]; then
  set -e
  target_env=$1;
  docker_image_label=$2

  if [ -n "$TARGET_NAME" ]; then
    echo "Deploying to $TARGET_NAME"
  fi

  # These are all supposed to come from Travis repo settings
  for variable in PGHOST \
                  PGPORT \
                  PGUSER \
                  PGPASSWORD \
                  EMBER_DEPLOY_AWS_ACCESS_KEY_ID \
                  EMBER_DEPLOY_AWS_SECRET_ACCESS_KEY \
                  GITHUB_CLIENT_ID \
                  GITHUB_CLIENT_SECRET \
                  GITHUB_TOKEN \
                  PUBLIC_HUB_URL \
                  SWARM_CONTROLLER \
                  S3_IMAGE_BUCKET \
                  S3_IMAGE_UPLOAD_ACCESS_KEY_ID \
                  S3_IMAGE_UPLOAD_SECRET_ACCESS_KEY \
                  LOG_LEVELS \
                  GIT_PRIVATE_KEY \
                  GIT_BRANCH_PREFIX \
                  CARDSTACK_SESSIONS_KEY; do
      command="export ${variable}=\$${target_env}_${variable}"
      eval $command
  done

  #env agnostic env vars
  for variable in TRAVIS_BRANCH ; do
      command="export ${variable}=\$${variable}"
      eval $command
  done

  export TARGET_ENV="cardboard-$target_env"

  # This needs to be exported because our docker-compose.yml below is interpolating it
  export CONTAINER_REPO=680542703984.dkr.ecr.us-east-1.amazonaws.com/cardboard

  export INITIAL_DATA_DIR=/srv/hub/cardboard/cardstack

  docker tag cardboard $CONTAINER_REPO:$docker_image_label

  # This needs to be exported because our docker-compose.yml below is interpolating it
  # We are authorized to push because earlier in our .travis.yml we logged in via "aws ecr"
  export DIGEST=`docker push $CONTAINER_REPO:$docker_image_label | grep digest: | cut -d " " -f 3`

  echo "Published digest $DIGEST for $CONTAINER_REPO:$docker_image_label"

  export HUB_ENVIRONMENT="production" # all builds that we deploy are prod builds

  cat >> ~/.ssh/known_hosts < deploy/known_hosts
  socat "UNIX-LISTEN:/tmp/cardstack-remote-docker-$target_env,reuseaddr,fork" EXEC:"ssh -T docker-control@$SWARM_CONTROLLER" &
  remote=unix:///tmp/cardstack-remote-docker-$target_env
  docker -H $remote stack deploy --with-registry-auth -c deploy/docker-compose.yml hub

  DOCKER_HOST=$remote node deploy/watch-docker.js $TRAVIS_BUILD_ID

  # only include env vars necessary for ember deploy
  docker run --rm --network cardstack \
            --env HUB_URL=$PUBLIC_HUB_URL \
            --env AWS_SECRET_ACCESS_KEY=$EMBER_DEPLOY_AWS_SECRET_ACCESS_KEY \
            --env AWS_ACCESS_KEY_ID=$EMBER_DEPLOY_AWS_ACCESS_KEY_ID \
            --env TRAVIS_COMMIT \
            --env TARGET_NAME \
            --workdir /srv/hub/cardboard \
            tests ./node_modules/.bin/ember deploy $target_env --verbose
fi