#!/bin/bash

#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

# This script will orchestrate a sample end-to-end execution of the Hyperledger
# Fabric network.
#
# The end-to-end verification provisions a sample Fabric network consisting of
# two organizations, each maintaining two peers, and a “solo” ordering service.
#
# This verification makes use of two fundamental tools, which are necessary to
# create a functioning transactional network with digital signature validation
# and access control:
#
# * cryptogen - generates the x509 certificates used to identify and
#   authenticate the various components in the network.
# * configtxgen - generates the requisite configuration artifacts for orderer
#   bootstrap and channel creation.
#
# Each tool consumes a configuration yaml file, within which we specify the topology
# of our network (cryptogen) and the location of our certificates for various
# configuration operations (configtxgen).  Once the tools have been successfully run,
# we are able to launch our network.  More detail on the tools and the structure of
# the network will be provided later in this document.  For now, let's get going...

# Grab the current directory, and change to it
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
THIS_SCRIPT=`basename "$0"`
cd ${CURRENT_DIR}

# prepending $PWD/../bin to PATH to ensure we are picking up the correct binaries
# this may be commented out to resolve installed version of tools if desired
export FABRIC_CFG_PATH=${PWD}
export COMPOSE_PROJECT_NAME="biznet"
export TAG="latest"

# Declare an array of our Organisations, this should match with configtx.yaml & crypto-config.yaml
declare -a Orgs=("CommodityExchange" "trader2" "trader3")

# sed on MacOSX does not support -i flag with a null extension. We will use
# 't' for our back-up's extension and depete it at the end of the function
ARCH=`uname -s | grep Darwin`
if [ "$ARCH" == "Darwin" ]; then
  OPTS="-it"
else
  OPTS="-i"
fi


# Ask user for confirmation to proceed
function askProceed () {
  read -p "Continue (y/n)? " ans
  case "$ans" in
    y|Y )
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
  # generate artifacts if they don't exist
  if [ ! -d "crypto-config" ]; then
    generateCerts
    replacePrivateKey
    generateChannelArtifacts
  fi

  COMPOSE_FILE_ADDITIONS=""
  if [ "${IF_COUCHDB}" == "couchdb" ]; then
    COMPOSE_FILE_ADDITIONS="${COMPOSE_FILE_ADDITIONS} -f $COMPOSE_FILE_COUCH"
  fi
  if [ "${IF_CAS}" == "1" ]; then
    COMPOSE_FILE_ADDITIONS="${COMPOSE_FILE_ADDITIONS} -f $COMPOSE_FILE_CLI"
  fi

  docker-compose -f ${COMPOSE_FILE}${COMPOSE_FILE_ADDITIONS} up -d 2>&1
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Unable to start network"
    # docker logs -f cli
    exit 1
  fi
  # docker logs -f cli

  echo
  echo "###############################################################"
  echo "###############   Executing CLI Script.sh    ##################"
  echo "###############################################################"
  docker exec cli ./scripts/script.sh ${CHANNEL_NAME} ${CLI_DELAY} ${LANGUAGE}
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Something doesn't look quite right, whilst running ./scripts/script.sh"
    # docker logs -f cli
    askProceed
  fi
}

# Tear down running network
function networkDown () {
  # What goes up, should come down as-well
  COMPOSE_FILE_ADDITIONS=""
  if [ "${IF_COUCHDB}" == "couchdb" ]; then
    COMPOSE_FILE_ADDITIONS="${COMPOSE_FILE_ADDITIONS} -f $COMPOSE_FILE_COUCH"
  fi
  if [ "${IF_CAS}" == "1" ]; then
    COMPOSE_FILE_ADDITIONS="${COMPOSE_FILE_ADDITIONS} -f $COMPOSE_FILE_CLI"
  fi
  docker-compose -f ${COMPOSE_FILE}${COMPOSE_FILE_ADDITIONS} down
  
  #Cleanup the chaincode containers, or docker rm $(docker ps -aq)
  clearContainers
  #Cleanup images, or docker rmi $(docker images dev-* -q)
  removeUnwantedImages

  # Don't remove containers, images, etc if restarting
  if [ "$MODE" != "restart" ]; then
    # remove orderer block and other channel configuration transactions and certs
    rm -rf channel-artifacts/*.block channel-artifacts/*.tx crypto-config/ channel-artifacts/
    # remove the docker-compose yaml file that was customized to the example
    rm -f docker-compose-e2e.yaml docker-compose-cas.yaml docker-compose-cli.yaml \
    docker-compose-couch.yaml configtx.yaml crypto-config.yaml
  fi
}

# Using docker-compose-e2e-template.yaml and docker-compose-cas-template.yaml, replace
# constants with private key file names generated by the cryptogen tool and output a
# docker-compose.yaml specific to this configuration
function replacePrivateKey () {
  # Copy the template to the file that will be modified to add the private key
  cp docker-compose-e2e-template.yaml docker-compose-e2e.yaml
  cp docker-compose-cas-template.yaml docker-compose-cas.yaml
  cp docker-compose-cli-template.yaml docker-compose-cli.yaml
  cp docker-compose-couch-template.yaml docker-compose-couch.yaml

  # The next steps will replace the template's contents with the
  # actual values of the private key file names for the two CAs.
  CURRENT_DIR=$PWD

  for (( i=0; i < ${#Orgs[@]}; i++ ));
  do
   # Grab the secret key file for the corresponding Organisation's ca
   echo "Copying secret key from crypto-config/peerOrganizations/"${Orgs[$i]}".tradent.com/ca/"
   cd crypto-config/peerOrganizations/"${Orgs[$i]}".tradent.com/ca/
   PRIV_KEY=$(ls *_sk)
   cd "$CURRENT_DIR"
   sed $OPTS "s/CA${i}_PRIVATE_KEY/${PRIV_KEY}/g" docker-compose-e2e.yaml docker-compose-cas.yaml docker-compose-cli.yaml docker-compose-couch.yaml
   sed $OPTS "s/@ORG_${i}/"${Orgs[$i]}"/g" docker-compose-e2e.yaml docker-compose-cas.yaml docker-compose-cli.yaml docker-compose-couch.yaml
  done
  
  # If MacOSX, remove the temporary backup of the docker-compose file
  if [ "$ARCH" == "Darwin" ]; then
    rm docker-compose-e2e.yamlt docker-compose-cas.yamlt
  fi
}

# We will use the cryptogen tool to generate the cryptographic material (x509 certs)
# for our various network entities.  The certificates are based on a standard PKI
# implementation where validation is achieved by reaching a common trust anchor.
#
# Cryptogen consumes a file - ``crypto-config.yaml`` - that contains the network
# topology and allows us to generate a library of certificates for both the
# Organizations and the components that belong to those Organizations.  Each
# Organization is provisioned a unique root certificate (``ca-cert``), that binds
# specific components (peers and orderers) to that Org.  Transactions and communications
# within Fabric are signed by an entity's private key (``keystore``), and then verified
# by means of a public key (``signcerts``).  You will notice a "count" variable within
# this file.  We use this to specify the number of peers per Organization; in our
# case it's two peers per Org.  The rest of this template is extremely
# self-explanatory.
#
# After we run the tool, the certs will be parked in a folder titled ``crypto-config``.

# Generates Org certs using cryptogen tool
function generateCerts (){
  which cryptogen
  if [ "$?" -ne 0 ]; then
    echo "cryptogen tool not found. exiting"
    exit 1
  fi

  # Copy the template crypto-config to create an actual three organisation config.yaml
  cp crypto-config-template.yaml crypto-config.yaml
  for (( i=0; i < ${#Orgs[@]}; i++ )); do
    # Connection profile for all Organisations, for instantiate chaincode
    sed $OPTS "s/@ORG_${i}/"${Orgs[$i]}"/g" ./crypto-config.yaml
  done
  
  echo
  echo "##########################################################"
  echo "##### Generate certificates using cryptogen tool #########"
  echo "##########################################################"

  if [ -d "crypto-config" ]; then
    rm -Rf crypto-config
  fi
  (cryptogen generate --config=./crypto-config.yaml
  if [ "$?" -ne 0 ]; then
    echo "Failed to generate certificates..."
    exit 1
  fi
  )
  echo
}

# The `configtxgen tool is used to create four artifacts: orderer **bootstrap
# block**, fabric **channel configuration transaction**, and two **anchor
# peer transactions** - one for each Peer Org.
#
# The orderer block is the genesis block for the ordering service, and the
# channel transaction file is broadcast to the orderer at channel creation
# time.  The anchor peer transactions, as the name might suggest, specify each
# Org's anchor peer on this channel.
#
# Configtxgen consumes a file - ``configtx.yaml`` - that contains the definitions
# for the sample network. There are four members - one Orderer Org (``OrdererOrg``)
# and three Peer Orgs (``tradent`` , ``trader2`` & ``trader3``) each managing 
# and maintaining two peer nodes.
# This file also specifies a consortium - ``tradentConsortium`` - consisting of our
# three Peer Orgs.  Pay specific attention to the "Profiles" section at the top of
# this file.  You will notice that we have two unique headers. One for the orderer genesis
# block - ``ThreeOrgsOrdererGenesis`` - and one for our channel - ``ThreeOrgsChannel``.
# These headers are important, as we will pass them in as arguments when we create
# our artifacts.  This file also contains two additional specifications that are worth
# noting.  Firstly, we specify the anchor peers for each Peer Org
# (``peer0.trader2.tradent.com`` & ``peer0.trader3.tradent.com``).  Secondly, we point to
# the location of the MSP directory for each member, in turn allowing us to store the
# root certificates for each Org in the orderer genesis block.  This is a critical
# concept. Now any network entity communicating with the ordering service can have
# its digital signature verified.
#
# This function will generate the crypto material and our four configuration
# artifacts, and subsequently output these files into the ``channel-artifacts``
# folder.
#
# If you receive the following warning, it can be safely ignored:
#
# [bccsp] GetDefault -> WARN 001 Before using BCCSP, please call InitFactories(). Falling back to bootBCCSP.
#
# You can ignore the logs regarding intermediate certs, we are not using them in
# this crypto implementation.

# Generate orderer genesis block, channel configuration transaction and
# anchor peer update transactions
function generateChannelArtifacts() {
  which configtxgen
  if [ "$?" -ne 0 ]; then
    echo "configtxgen tool not found. exiting"
    exit 1
  fi

  if [ -d "channel-artifacts" ]; then
    rm -Rf channel-artifacts
  fi
  mkdir channel-artifacts

  # Copy the template configtx to create an actual three organisation configtx.yaml
  cp configtx-template.yaml configtx.yaml
  for (( i=0; i < ${#Orgs[@]}; i++ )); do
    # Connection profile for all Organisations, for instantiate chaincode
    sed $OPTS "s/@ORG_${i}/"${Orgs[$i]}"/g" ./configtx.yaml
  done
  
  echo "##########################################################"
  echo "#########  Generating Orderer Genesis block ##############"
  echo "##########################################################"
  # Note: For some unknown reason (at least for now) the block file can't be
  # named orderer.genesis.block or the orderer will fail to launch!
  (configtxgen -profile ThreeOrgsOrdererGenesis -outputBlock ./channel-artifacts/genesis.block
  if [ "$?" -ne 0 ]; then
    echo "Failed to generate orderer genesis block..."
    exit 1
  fi
  )
  echo

  # Generate the channels pertaining to each Organisation joining CommodityExchange
  for (( i=1; i < ${#Orgs[@]}; i++ ));
  do
    CHANNEL_NAME="exch-${Orgs[$i]}"
    echo "###################################################################"
    echo "###  Generating channel configuration transaction 'channel.tx'  ###"
    echo "###################################################################"
    (configtxgen -profile ThreeOrgsChannel -outputCreateChannelTx \
    ./channel-artifacts/${CHANNEL_NAME}.tx -channelID ${CHANNEL_NAME}
    if [ "$?" -ne 0 ]; then
      echo "Failed to generate channel ${CHANNEL_NAME} configuration txns..."
      exit 1
    fi
    )

    # Generate the anchor peer update for all Organisations
    for (( j=0; j < ${#Orgs[@]}; j++ ));
    do
    # Grab the secret key file for the corresponding Organisation's ca
      echo
      echo "###################################################################"
      echo "#######    Generating anchor peer update for "${Orgs[$j]}"MSP   ##########"
      echo "###################################################################"
      (configtxgen -profile ThreeOrgsChannel -outputAnchorPeersUpdate \
      ./channel-artifacts/"${Orgs[$j]}"MSPanchors-${CHANNEL_NAME}.tx \
      -channelID ${CHANNEL_NAME} -asOrg "${Orgs[$j]}"MSP
      if [ "$?" -ne 0 ]; then
        echo "Failed to generate anchor peer update for "${Orgs[$j]}"MSP..."
        exit 1
      fi
      )
    done
    echo
  done
  echo

}

# Obtain the OS and Architecture string that will be used to select the correct
# native binaries for your platform
OS_ARCH=$(echo "$(uname -s|tr '[:upper:]' '[:lower:]'|sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')" | awk '{print tolower($0)}')
# timeout duration - the duration the CLI should wait for a response from
# another container before giving up
CLI_TIMEOUT=15000
#default for delay
CLI_DELAY=5
# channel name defaults to "exch-channel"
CHANNEL_NAME="exch-channel"
# chaincode name defaults to "chaincode_example02"
CHAINCODE_NAME="chaincode_example02"
# use this as the default docker-compose yaml definition
COMPOSE_FILE=docker-compose-e2e.yaml
# the docker compose yaml for CouchDB
COMPOSE_FILE_COUCH=docker-compose-couch.yaml
# We will need a separate Fabric CA docker-compose as well
COMPOSE_FILE_CAS=docker-compose-cas.yaml
# And a CLI container, for exeuting any Fabric commands
COMPOSE_FILE_CLI=docker-compose-cli.yaml
# Let's assume that in Composer operation we set $LANGUAGE option as "node", otherwise "golang"
if [ -z ${COMPOSER_OPS+x} ]; then
  LANGUAGE=golang
else
  LANGUAGE=node
fi

# Parse commandline args
while getopts "h?m:c:b:t:d:f:s:l:a?" opt; do
  case "$opt" in
    m)  MODE=$OPTARG
    ;;
    c)  CHANNEL_NAME=$OPTARG
    ;;
    b)  CHAINCODE_NAME=$OPTARG
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
    a)  IF_CAS=1
    ;;
  esac
done

# Determine whether starting, stopping, restarting or generating for announce
if [ "$MODE" == "up" ]; then
  EXPMODE="Starting,"
  elif [ "$MODE" == "down" ]; then
  EXPMODE="Stopping,"
  elif [ "$MODE" == "restart" ]; then
  EXPMODE="Restarting,"
  elif [ "$MODE" == "generate" ]; then
  EXPMODE="Generating certs and genesis block,"
else
  echo "Fabric mode: ${MODE} encountered, exiting(1)"
  exit 1
fi

# Announce what was requested
ADDITIONS=""
if [ "${IF_COUCHDB}" == "couchdb" ]; then
  ADDITIONS="${ADDITIONS} and using database '${IF_COUCHDB}'"
fi
if [ "${IF_CAS}" == "1" ]; then
  ADDITIONS="${ADDITIONS} and with CLI container as well"
fi
echo "${EXPMODE} with channel '${CHANNEL_NAME}' and chaincode '${CHAINCODE_NAME}'${ADDITIONS}"

# ask for confirmation to proceed
askProceed

#Create the network using docker compose
if [ "${MODE}" == "up" ]; then
  networkUp
  elif [ "${MODE}" == "down" ]; then ## Clear the network
    networkDown
  elif [ "${MODE}" == "generate" ]; then ## Generate Artifacts
    generateCerts
    replacePrivateKey
    generateChannelArtifacts
  elif [ "${MODE}" == "restart" ]; then ## Restart the network
    networkDown
    askProceed
    networkUp
else
  echo "Fabric mode: ${MODE} encountered, exiting(1)"
  exit 1
fi

# Let's iterate, if needed to Composer operations now.
if [ -z ${COMPOSER_OPS+x} ]; then
  echo "Reached logical end and assuming Go-code chaincode deployment with COMPOSER_OPS unset"
else
  if [ "${MODE}" == "generate" ]; then
    echo "Bringing-up the CA Servers for respective organisation, needed for Composer Identity Request"
    docker-compose -f ${COMPOSE_FILE_CAS} up -d 2>&1
    echo
  fi
  echo "Composer operations using Composer version '${COMPOSER_OPS}'"
  echo "Executing './${COMPOSER_OPS}/${THIS_SCRIPT} $@'"
  cp -r ./crypto-config ./${COMPOSER_OPS}
  askProceed
  "${CURRENT_DIR}"/"${COMPOSER_OPS}"/"${THIS_SCRIPT}" "$@"
fi

# House-keeping jobs, important as iterative script execution might have created hell-a-lot artefacts
if [ "${MODE}" == "up" ]; then
  echo "House-keeping for networkUp"
  elif [ "${MODE}" == "down" ]; then ## Clear the network
    echo "House-keeping for networkDown"
  elif [ "${MODE}" == "generate" ]; then ## Generate Artifacts
    if [ -z ${COMPOSER_OPS+x} ]; then
      echo "Nothing needed to be done for house-keeping as generateCerts"
    else
      echo "House-keeping as generateCerts, bringing down Fabric CA servers"
      docker-compose -f ${COMPOSE_FILE_CAS} down
      mv ./${COMPOSER_OPS}/crypto-config ./${COMPOSER_OPS}/composer-cards
    fi
  elif [ "${MODE}" == "restart" ]; then ## Restart the network
    echo "House-keeping for restrartNetwork"
else
  echo "Fabric mode: ${MODE} encountered, exiting(1)"
  exit 1
fi
