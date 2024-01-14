FROM ubuntu:noble

ARG REPOSITORY_URL="https://github.com/robjackstewart/home-media-server"
ARG RUNNER_VERSION=2.311.0
ARG TOKEN=""

RUN if [ -z "$TOKEN" ]; then echo "Error: TOKEN is empty, build failed" && exit 1; fi

# Create a folder
RUN mkdir actions-runner && cd actions-runner

RUN apt update && \
    apt upgrade -y && \
    apt install curl sudo -y

# Download the latest runner package
RUN curl -o actions-runner-linux-x64-2.311.0.tar.gz -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

RUN mkdir /actions-runner-linux-x64-${RUNNER_VERSION}

# Extract the installer
RUN tar xzf ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -C /actions-runner-linux-x64-${RUNNER_VERSION}

WORKDIR /actions-runner-linux-x64-${RUNNER_VERSION}

RUN ./bin/installdependencies.sh

RUN useradd -rm -d /home/githubrunner -s /bin/bash -g root -G sudo -u 1001 githubrunner

USER githubrunner

# Create the runner and start the configuration experience
RUN ./config.sh --url "$REPOSITORY_URL" --token $TOKEN

# Last step, run it!
ENTRYPOINT ./run.sh