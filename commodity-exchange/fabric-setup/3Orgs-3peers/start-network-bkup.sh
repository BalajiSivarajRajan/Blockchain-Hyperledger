#!/bin/bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

# This script extends the Hyperledger Fabric By Your First Network by
# adding a third organization to the network previously setup in the
# BYFN tutorial.
#

# Grab the current directory, and change to it
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
THIS_SCRIPT=`basename "$0"`
cd ${CURRENT_DIR}

# prepending $PWD/../bin to PATH to ensure we are picking up the correct binaries
# this may be commented out to resolve installed version of tools if desired
export FABRIC_CFG_PATH=${PWD}
export COMPOSE_PROJECT_NAME="biznet"
export TAG="latest"

# Organisation name, though can be read as calling parameter, is best to default to a value
# change this value, if other name is supposed to be used throughout
ORG_NAME="trader1"

# sed on MacOSX does not support -i flag with a null extension. We will use
# 't' for our back-up's extension and depete it at the end of the function
ARCH=`uname -s | grep Darwin`
if [ "$ARCH" == "Darwin" ]; then
  OPTS="-it"
else
  OPTS="-i"
fi


# Print the usage message
function printHelp () {
  echo "Usage: "
  echo "  eTradeNT.sh up|down|restart|generate [-c <channel name>] [-t <timeout>] [-d <delay>] [-f <docker-compose-file>] [-s <dbtype>]"
  echo "  eTradeNT.sh -h|--help (print this message)"
  echo "    <mode> - one of 'up', 'down', 'restart' or 'generate'"
  echo "      - 'up' - bring up the network with docker-compose up"
  echo "      - 'down' - clear the network with docker-compose down"
  echo "      - 'restart' - restart the network"
  echo "      - 'generate' - generate required certificates and genesis block"
  echo "    -c <channel name> - channel name to use (defaults to \"mychannel\")"
  echo "    -t <timeout> - CLI timeout duration in seconds (defaults to 10)"
  echo "    -d <delay> - delay duration in seconds (defaults to 3)"
  echo "    -f <docker-compose-file> - specify which docker-compose file use (defaults to docker-compose-cli.yaml)"
  echo "    -s <dbtype> - the database backend to use: goleveldb (default) or couchdb"
  echo "    -l <language> - the chaincode language: golang (default) or node"
  echo
  echo "Typically, one would first generate the required certificates and "
  echo "genesis block, then bring up the network. e.g.:"
  echo
  echo "	eTradeNT.sh generate -c mychannel"
  echo "	eTradeNT.sh up -c mychannel -s couchdb"
  echo "	eTradeNT.sh up -l node"
  echo "	eTradeNT.sh down -c mychannel"
  echo
  echo "Taking all defaults:"
  echo "	eTradeNT.sh generate"
  echo "	eTradeNT.sh up"
  echo "	eTradeNT.sh down"
}

# Ask user for confirmation to proceed
function askProceed () {
  read -p "Continue? [Y/n] " ans
  case "$ans" in
    y|Y|"" )
      echo "proceeding ..."
    ;;
    n|N )
      echo "exiting..."
      exit 1
    ;;
    * )
      echo "invalid response"
      askProceed
    ;;
  esac
}

# Obtain CONTAINER_IDS and remove them
# TODO Might want to make this optional - could clear other containers
function clearContainers () {
  CONTAINER_IDS=$(docker ps -aq)
  if [ -z "$CONTAINER_IDS" -o "$CONTAINER_IDS" == " " ]; then
    echo "---- No containers available for deletion ----"
  else
    docker rm -f $CONTAINER_IDS
  fi
}

# Delete any images that were generated as a part of this setup
# specifically the following images are often left behind:
# TODO list generated image naming patterns
function removeUnwantedImages() {
  DOCKER_IMAGE_IDS=$(docker images | grep "dev\|none\|test-vp\|peer[0-9]-" | awk '{print $3}')
  if [ -z "$DOCKER_IMAGE_IDS" -o "$DOCKER_IMAGE_IDS" == " " ]; then
    echo "---- No images available for deletion ----"
  else
    docker rmi -f $DOCKER_IMAGE_IDS
  fi
}

# Generate the needed certificates, the genesis block and start the network.
function networkUp () {
  # copy the docker-compose-Org-template.yaml to docker-compose-${ORG_NAME}.yaml
  cp docker-compose-Org-template.yaml docker-compose-${ORG_NAME}.yaml
  sed $OPTS "s/@ORG/"${ORG_NAME}"/g" ./docker-compose-${ORG_NAME}.yaml

  echo "Copying secret key from ${ORG_NAME}-artefacts/crypto-config/peerOrganizations/"${ORG_NAME}".tradent.com/ca/"
  (cd ${ORG_NAME}-artefacts/crypto-config/peerOrganizations/"${ORG_NAME}".tradent.com/ca/
  PRIV_KEY=$(ls *_sk)
  )
  echo "Secret key is: ${PRIV_KEY}"
  sed $OPTS "s/CA_PRIVATE_KEY/${PRIV_KEY}/g" docker-compose-${ORG_NAME}.yaml

  # generate artifacts if they don't exist, accendtly running up before generate
  if [ ! -d "${ORG_NAME}-artifacts/crypto-config" ]; then
    generateCerts
    generateChannelArtifacts
    createConfigTx
  fi
  # start ${ORG_NAME} peers
  if [ "${IF_COUCHDB}" == "couchdb" ]; then
      docker-compose -f $COMPOSE_FILE_ORG -f $COMPOSE_FILE_COUCH_ORG up -d 2>&1
  else
      docker-compose -f $COMPOSE_FILE_ORG up -d 2>&1
  fi
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Unable to start ${ORG_NAME} network"
    exit 1
  fi
  echo
  echo "################################################################"
  echo "############### Have ${ORG_NAME} peers join network ##################"
  echo "################################################################"
  docker exec ${ORG_NAME}cli ./scripts/step2Org.sh $CHANNEL_NAME $CLI_DELAY $LANGUAGE $CLI_TIMEOUT
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Unable to have ${ORG_NAME} peers join network"
    exit 1
  fi
  # echo
  # echo "################################################################"
  # echo "##### Upgrade chaincode to have ${ORG_NAME} peers on the network #####"
  # echo "################################################################"
  # docker exec cli ./scripts/step3Org.sh $CHANNEL_NAME $CLI_DELAY $LANGUAGE $CLI_TIMEOUT
  # if [ $? -ne 0 ]; then
  #   echo "ERROR !!!! Unable to add ${ORG_NAME} peers on network"
  #   exit 1
  # fi
  # # finish by running the test
  # docker exec ${ORG_NAME}cli ./scripts/testOrg.sh $CHANNEL_NAME $CLI_DELAY $LANGUAGE $CLI_TIMEOUT
  # if [ $? -ne 0 ]; then
  #   echo "ERROR !!!! Unable to run test"
  #   exit 1
  # fi
}

# Tear down running network
function networkDown () {
  # down ${ORG_NAME} peers
  if [ "${IF_COUCHDB}" == "couchdb" ]; then
      docker-compose -f $COMPOSE_FILE_ORG -f $COMPOSE_FILE_COUCH_ORG down
  else
      docker-compose -f $COMPOSE_FILE_ORG down
  fi
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Whilst bringing down ${ORG_NAME} network"
    # exit 1
  fi

  # Don't remove containers, images, etc if restarting
  if [ "$MODE" != "restart" ]; then
    #Cleanup the chaincode containers
    # clearContainers
    #Cleanup images
    # removeUnwantedImages
    # remove orderer block and other channel configuration transactions and certs
    rm -Rf channel-artifacts/${ORG_NAME}* ./${ORG_NAME}-artifacts/ 
    # remove the docker-compose yaml file that was customized to the example
    rm -f docker-compose-${ORG_NAME}.yaml
  fi
}

# Use the CLI container to create the configuration transaction needed to add
# ${ORG_NAME} to the network
function createConfigTx () {
  echo
  echo "################################################################"
  echo "####### Generate and submit config tx to add ${ORG_NAME} #############"
  echo "################################################################"
  docker exec cli scripts/step1Org.sh $CHANNEL_NAME $CLI_DELAY $LANGUAGE $CLI_TIMEOUT
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Unable to create config tx"
    exit 1
  fi
}

# We use the cryptogen tool to generate the cryptographic material
# (x509 certs) for the new org.  After we run the tool, the certs will
# be parked in the BYFN folder titled ``crypto-config``.

# Generates ${ORG_NAME} certs using cryptogen tool
function generateCerts (){
  if [ -d "${ORG_NAME}-artifacts" ]; then
    rm -Rf ${ORG_NAME}-artifacts
  fi
  mkdir ${ORG_NAME}-artifacts

  # Copy the template crypto-config to create an additional organisation config.yaml
  cp adding-Org/crypto-config-template.yaml ${ORG_NAME}-artifacts/crypto-config.yaml
  sed $OPTS "s/@ORG/"${ORG_NAME}"/g" ${ORG_NAME}-artifacts/crypto-config.yaml
 
  which cryptogen
  if [ "$?" -ne 0 ]; then
    echo "cryptogen tool not found. exiting"
    exit 1
  fi
  echo
  echo "###############################################################"
  echo "##### Generate ${ORG_NAME} certificates using cryptogen tool #########"
  echo "###############################################################"

  (cd ${ORG_NAME}-artifacts
   cryptogen generate --config=./crypto-config.yaml
   if [ "$?" -ne 0 ]; then
     echo "Failed to generate certificates..."
     exit 1
   fi
  )
  echo
}

# Generate channel configuration transaction
function generateChannelArtifacts() {
  # Copy the template crypto-config to create an additional organisation config.yaml
  cp adding-Org/configtx-template.yaml ${ORG_NAME}-artifacts/configtx.yaml
  sed $OPTS "s/@ORG/"${ORG_NAME}"/g" ${ORG_NAME}-artifacts/configtx.yaml

  which configtxgen
  if [ "$?" -ne 0 ]; then
    echo "configtxgen tool not found. exiting"
    exit 1
  fi
  echo "###########################################################"
  echo "#########  Generating ${ORG_NAME} config material ###############"
  echo "###########################################################"
  (cd ${ORG_NAME}-artifacts
   export FABRIC_CFG_PATH=$PWD
   configtxgen -printOrg ${ORG_NAME}MSP > ../channel-artifacts/${ORG_NAME}.json
   if [ "$?" -ne 0 ]; then
     echo "Failed to generate ${ORG_NAME} config material..."
     exit 1
   fi
  )
  cp -r crypto-config/ordererOrganizations ${ORG_NAME}-artifacts/crypto-config/
  echo
}


# If BYFN wasn't run abort
if [ ! -d crypto-config ]; then
  echo
  echo "ERROR: Please, run tradent.sh first."
  echo
  exit 1
fi

# Obtain the OS and Architecture string that will be used to select the correct
# native binaries for your platform
OS_ARCH=$(echo "$(uname -s|tr '[:upper:]' '[:lower:]'|sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')" | awk '{print tolower($0)}')

# timeout duration - the duration the CLI should wait for a response from
# another container before giving up
CLI_TIMEOUT=10
#default for delay
CLI_DELAY=3
# channel name defaults to "exch-channel"
CHANNEL_NAME="exch-channel"
# use this as the default docker-compose yaml definition
COMPOSE_FILE_ORG=docker-compose-${ORG_NAME}.yaml
# with standard couchdb for the new organisation (careful with port configuration)
COMPOSE_FILE_COUCH_ORG=docker-compose-couch-${ORG_NAME}.yaml
# use golang as the default language for chaincode
LANGUAGE=golang

# Parse commandline args
if [ "$1" = "-m" ];then	# supports old usage, muscle memory is powerful!
    shift
fi
MODE=$1;shift
# Determine whether starting, stopping, restarting or generating for announce
if [ "$MODE" == "up" ]; then
  EXPMODE="Starting,"
elif [ "$MODE" == "down" ]; then
  EXPMODE="Stopping,"
elif [ "$MODE" == "restart" ]; then
  EXPMODE="Restarting,"
elif [ "$MODE" == "generate" ]; then
  EXPMODE="Generating artefacts,"
else
  printHelp
  exit 1
fi
while getopts "h?c:t:d:f:s:l:" opt; do
  case "$opt" in
    h|\?)
      printHelp
      exit 0
    ;;
    c)  CHANNEL_NAME=$OPTARG
    ;;
    t)  CLI_TIMEOUT=$OPTARG
    ;;
    d)  CLI_DELAY=$OPTARG
    ;;
    f)  COMPOSE_FILE=$OPTARG
    ;;
    s)  IF_COUCHDB=$OPTARG
    ;;
    l)  LANGUAGE=$OPTARG
    ;;
  esac
done

# Announce what was requested

  if [ "${IF_COUCHDB}" == "couchdb" ]; then
        echo
        echo "${EXPMODE} with channel '${CHANNEL_NAME}' and CLI timeout of '${CLI_TIMEOUT}' seconds and CLI delay of '${CLI_DELAY}' seconds and using database '${IF_COUCHDB}'"
  else
        echo "${EXPMODE} with channel '${CHANNEL_NAME}' and CLI timeout of '${CLI_TIMEOUT}' seconds and CLI delay of '${CLI_DELAY}' seconds"
  fi
# ask for confirmation to proceed
askProceed

#Create the network using docker compose
if [ "${MODE}" == "up" ]; then
  networkUp
elif [ "${MODE}" == "down" ]; then ## Clear the network
  networkDown
elif [ "${MODE}" == "generate" ]; then ## Generate Artifacts
  generateCerts
  generateChannelArtifacts
  createConfigTx
elif [ "${MODE}" == "restart" ]; then ## Restart the network
  networkDown
  networkUp
else
  printHelp
  exit 1
fi
