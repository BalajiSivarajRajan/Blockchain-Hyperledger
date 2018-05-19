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

# prepending $PWD/../bin to PATH to ensure we are picking up the correct binaries
# this may be commented out to resolve installed version of tools if desired
# export FABRIC_CFG_PATH=${PWD}
# export COMPOSE_PROJECT_NAME="biznet"
# export TAG="latest"

# Grab the current directory, and change to it
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
THIS_SCRIPT=`basename "$0"`
cd ${CURRENT_DIR}

# Declare an array of our Organisations, this should match with configtx.yaml & crypto-config.yaml
declare -a Channels=("exch-trader2" "exch-trader3")
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

# Bring-up the Business Network, createPeerAdmin Composer cards in case
function biznetUp () {
  # Generate artifacts, i.e. composer cards and connection profiles, if they don't exist
  if [ ! -d "composer-cards" ]; then
    createConnProfiles
    createComposerCards

    # Copy the crypto-config certificates and keys to composer-cards directory.
    # This is where we plan to issue composer-playground and or other CLI operations
    echo "Copying ../crypto-config materials to ./composer-cards"
    cp -r ../crypto-config ./composer-cards
  fi

  cd composer-cards

  # Install chaincode as per settings, we can't be clever enough here (but lets try)
  for (( i=0; i < ${#Orgs[@]}; i++ )); do
    ORG_ID="${Orgs[$i]}"

    # Install the runtime (chaincode) using the PeerAdmin@${ORG_ID}-only
    composer runtime install -c PeerAdmin@${ORG_ID}-only -n ${CHAINCODE_NAME}
    if [ $? -ne 0 ]; then
      echo "ERROR !!! Unable to perform runtime install using '-c PeerAdmin@${ORG_ID}-only -n ${CHAINCODE_NAME}'"
    fi
  done

  # You should be now ready to Instantiate the chaincode (or BNA)
  echo "Composer operations successfully deployed, you should now perform 'composer network create ...'"
  echo "Or we can give it a go, if you please ..."
  askProceed

  for (( j=0; j < ${#Channels[@]}; j++ )); do
    # Perform 2nd set of operations involving connection profile organisation ALL cards
    ORG_ID="${Orgs[$j+1]}"
    CHANNEL_NAME="${Channels[$j]}"
    CARD_NAME=PeerAdmin@"${ORG_ID}"-${CHANNEL_NAME}
    ENDORSEMENT_POLICY=endorsement-policy-${CHANNEL_NAME}.json
    
    # Composer network start, AND if successful, Composer network ping as well
    echo "Executing, Composer Network Start -c ${CARD_NAME} -a .. -o ..=${ENDORSEMENT_POLICY} -A Admin-${ORG_ID} .. -A Admin-"${Orgs[0]}""
    composer network start -c ${CARD_NAME} \
    -a ../chaincode/${CHAINCODE_NAME}/${CHAINCODE_NAME}@0.0.1.bna \
    -o endorsementPolicyFile=${ENDORSEMENT_POLICY} \
    -A Admin-${ORG_ID} -C ${ORG_ID}/Admin-${ORG_ID}/admin-pub.pem \
    -A Admin-"${Orgs[0]}" -C "${Orgs[0]}"/Admin-"${Orgs[0]}"/admin-pub.pem
    if [ $? -ne 0 ]; then
      echo "ERROR !!! Whilst performing 'Composer network start with -c ${CARD_NAME} & -a ../chaincode/${CHAINCODE_NAME}/${CHAINCODE_NAME}@0.0.1.bna'"
    else
      # With the grace of almighty, we have reached here with successful chaincode instantiate,
      # lets ping the network one-by-one

      PING_ID=Admin-${ORG_ID}-${CHANNEL_NAME}@${CHAINCODE_NAME}
      # Composer network ping using Admin-Org1-exch-CHANNEL1@CHAINCODE
      composer network ping -c ${PING_ID}
      if [ $? -ne 0 ]; then
        echo "ERROR !!! Unable to perform 'Composer network ping -c ${PING_ID}'"
      fi

      PING_ID=Admin-"${Orgs[0]}"-${CHANNEL_NAME}@${CHAINCODE_NAME}
      # Composer network ping using Admin-Org1-exch-CHANNEL1@CHAINCODE
      composer network ping -c ${PING_ID}
      if [ $? -ne 0 ]; then
        echo "ERROR !!! Unable to perform 'Composer network ping -c ${PING_ID}'"
      fi
    fi
  done
  
  cd $CURRENT_DIR
}

# Tear down running network
function biznetDown () {
  # Don't remove composer cards, connnection profiles, endorsement-ploicy etc if restarting
  if [ "$MODE" != "restart" ]; then
    # Delete all the Composer Cards, as created for each organisation
    for (( i=0; i < ${#Orgs[@]}; i++ )); do
      ORG_ID="${Orgs[$i]}"
      CARD_NAME=PeerAdmin@${ORG_ID}-only

      # Delete the PeerAdmin@${ORG_ID}-only
      composer card delete -n ${CARD_NAME}
      if [ $? -ne 0 ]; then
        echo "ERROR !!! Unable to delete composer card '${CARD_NAME}'"
      fi

      for (( j=0; j < ${#Channels[@]}; j++ )); do
        # Perform 2nd set of operations involving connection profile organisation ALL cards
        CHANNEL_NAME="${Channels[$j]}"
        CARD_NAME=PeerAdmin@${ORG_ID}-${CHANNEL_NAME}

        # Delete the PeerAdmin@${ORG_ID}-${CHANNEL_NAME}
        composer card delete -n ${CARD_NAME}
        if [ $? -ne 0 ]; then
          echo "ERROR !!! Unable to delete composer card '${CARD_NAME}'"
        fi

        CARD_NAME=Admin-${ORG_ID}-${CHANNEL_NAME}@${CHAINCODE_NAME}
        # Delete the Admin-${ORG_ID}-${CHANNEL_NAME}@${CHAINCODE_NAME}
        composer card delete -n ${CARD_NAME}
        if [ $? -ne 0 ]; then
          echo "ERROR !!! Unable to delete composer card '${CARD_NAME}'"
        fi
      done

      # remove the directory having connection profiles, composer cards for this organisation
      rm -Rf ./composer-cards/${ORG_ID}
    done

    # remove the composer-cards, crypto-config & composer-logs directories and any contents therein
    rm -Rf composer-cards crypto-config composer-logs
  fi

}

# Using docker-compose-e2e-template.yaml and docker-compose-cas-template.yaml, replace
# constants with private key file names generated by the cryptogen tool and output a
# docker-compose.yaml specific to this configuration
function createConnProfiles () {
  # Time to create the composer connection profiles too
  if [ -d "composer-cards" ]; then
    rm -Rf composer-cards
  fi
  echo
  echo "##################################################################################"
  echo "##### Generate composer profiles, and copy secret key to docker-composer #########"
  echo "##################################################################################"
  mkdir composer-cards

  for (( j=0; j < ${#Channels[@]}; j++ )); do
    CHANNEL_NAME="${Channels[$j]}"

    for (( i=0; i < ${#Orgs[@]}; i++)); do
      echo "Creating connection profile './composer-cards/connection-ORG_${i}-CHANNEL_${j}.json'"
      cp ./connection-ORG_${i}-CHANNEL_${j}-template.json ./composer-cards/connection-ORG_${i}-CHANNEL_${j}.json
      mkdir ./composer-cards/"${Orgs[$i]}"

      # Create respective directories and save connection profiles within
      echo "Creating connection profile './composer-cards/"${Orgs[$i]}"/connection-"${Orgs[$i]}"-only.json'"
      cp ./connection-ORG-only-template.json ./composer-cards/"${Orgs[$i]}"/connection-"${Orgs[$i]}"-only.json

      # Grab the secret key and public Admin user's file for the corresponding Organisation
      echo "Copying secret key from crypto-config/.../Admin@"${Orgs[$i]}".tradent.com/msp"
      cp ./crypto-config/peerOrganizations/"${Orgs[$i]}".tradent.com/users/Admin@"${Orgs[$i]}".tradent.com/msp/signcerts/*.pem ./composer-cards/"${Orgs[$i]}"/
      cp ./crypto-config/peerOrganizations/"${Orgs[$i]}".tradent.com/users/Admin@"${Orgs[$i]}".tradent.com/msp/keystore/*_sk ./composer-cards/"${Orgs[$i]}"/
    done
    echo "Creating endorsement policy './composer-cards/endorsement-policy-CHANNEL_${j}.json'"
    cp ./endorsement-policy-CHANNEL_${j}-template.json ./composer-cards/endorsement-policy-${CHANNEL_NAME}.json
  done
  
  for (( j=0; j < ${#Channels[@]}; j++ )); do
    CHANNEL_NAME="${Channels[$j]}"

    for (( i=0; i < ${#Orgs[@]}; i++ )); do
      REQUEST_PORT=$((7000 + (${i} * 1000) + 51))
      EVENT_PORT=$((7000 + (${i} * 1000) + 53))
      CA_PORT=$((7000 + (${i} * 1000) + 54))
      ORG_ID="${Orgs[$i]}"
      cd composer-cards

      # Connection profile for all Organisations, for instantiate chaincode
      sed $OPTS "s/@ORG_${i}/${ORG_ID}/g" ./connection-ORG_*.json ./endorsement-policy-*.json
      sed $OPTS "s/@requestPORT_${i}/${REQUEST_PORT}/g" ./connection-ORG_*.json
      sed $OPTS "s/@eventPORT_${i}/${EVENT_PORT}/g" ./connection-ORG_*.json
      sed $OPTS "s/@caPORT_${i}/${CA_PORT}/g" ./connection-ORG_*.json
      sed $OPTS "s/@CHANNEL_NAME_${j}/${CHANNEL_NAME}/g" ./connection-ORG_*.json

      # Organisation only connection profile, for install chaincode
      sed $OPTS "s/@ORG/${ORG_ID}/g" ./${ORG_ID}/connection-${ORG_ID}-only.json
      sed $OPTS "s/@requestPORT/${REQUEST_PORT}/g" ./${ORG_ID}/connection-${ORG_ID}-only.json
      sed $OPTS "s/@eventPORT/${EVENT_PORT}/g" ./${ORG_ID}/connection-${ORG_ID}-only.json
      sed $OPTS "s/@caPORT/${CA_PORT}/g" ./${ORG_ID}/connection-${ORG_ID}-only.json
      sed $OPTS "s/@CHANNEL_NAME_${j}/${CHANNEL_NAME}/g" ./${ORG_ID}/connection-${ORG_ID}-only.json

      cd "${CURRENT_DIR}"
    done
  done

  for (( j=0; j < ${#Channels[@]}; j++ )); do
    CHANNEL_NAME="${Channels[$j]}"

    # Move the Org-all connection profiles to respective Organisation directory with correct naming
    for (( i=0; i < ${#Orgs[@]}; i++)); do
      echo "Moving ./composer-cards/"${Orgs[$i]}"/connection-"${Orgs[$i]}"-all.json"
      mv ./composer-cards/connection-ORG_${i}-CHANNEL_${j}.json ./composer-cards/"${Orgs[$i]}"/connection-"${Orgs[$i]}"-"${CHANNEL_NAME}".json
    done
  done
}

# Using docker-compose-e2e-template.yaml and docker-compose-cas-template.yaml, replace
# constants with private key file names generated by the cryptogen tool and output a
# docker-compose.yaml specific to this configuration
function createComposerCards () {
  echo
  echo "################################################################"
  echo "##### Create business network [composer] cards and import ######"
  echo "################################################################"
  
  # The next steps will replace the template's contents with the
  # actual values of the private key file names for the two CAs.
  CURRENT_DIR=$PWD

  for (( i=0; i < ${#Orgs[@]}; i++ )); do
    cd "$CURRENT_DIR"
    ORG_ID="${Orgs[$i]}"
    cd composer-cards/${ORG_ID}

    ADMIN_PEM=$(ls *.pem)
    ADMIN_SK=$(ls *_sk)

    # Perform 1st set of operations involving connection profile organisation ONLY cards
    CARD_NAME=PeerAdmin@${ORG_ID}-only
    CONN_PROFILE="connection-${ORG_ID}-only.json"
    echo "Composer card ${CARD_NAME} create with connection profile: ${CONN_PROFILE}"

    if [ -f "${CONN_PROFILE}" ]; then
      # Connection card create and import for each Organisation progressively
      composer card create -p ${CONN_PROFILE} -u PeerAdmin -c ${ADMIN_PEM} -k ${ADMIN_SK} -r PeerAdmin -r ChannelAdmin
      if [ $? -ne 0 ]; then
        echo "ERROR !!! Unable to create composer PeerAdmin card for ${ORG_ID} with profile ${CONN_PROFILE}"
      else
        # Delete any existing composer card, if present from prior run, and import this card
        echo "Performing composer card delete and import for ${CARD_NAME}"
        composer card delete -n ${CARD_NAME}
        composer card import -f ${CARD_NAME}.card
        if [ $? -ne 0 ]; then
          echo "ERROR !!! Unable to import "${CARD_NAME}".card"
        else
          # Import success, run composer identity request to retrieve certs to use as the Administrator
          composer identity request -c ${CARD_NAME} -u admin -s adminpw -d Admin-${ORG_ID}
          if [ $? -ne 0 ]; then
            echo "ERROR !!! Composer identity request failed for -c ${CARD_NAME} -d Admin-${ORG_ID}"
          fi
        fi
      fi
    else
      echo "Composer card create, couldn't locate connection profile: ${CONN_PROFILE}"
    fi

    for (( j=0; j < ${#Channels[@]}; j++ )); do
      # Perform 2nd set of operations involving connection profile organisation ALL cards
      CHANNEL_NAME="${Channels[$j]}"
      CARD_NAME=PeerAdmin@${ORG_ID}-${CHANNEL_NAME}
      CONN_PROFILE="connection-${ORG_ID}-${CHANNEL_NAME}.json"
      echo "Composer card ${CARD_NAME} create with connection profile: ${CONN_PROFILE}"

      if [ -f "${CONN_PROFILE}" ]; then
        # Connection card create and import for each Organisation progressively
        composer card create -p ${CONN_PROFILE} -u PeerAdmin -c ${ADMIN_PEM} -k ${ADMIN_SK} -r PeerAdmin -r ChannelAdmin
        if [ $? -ne 0 ]; then
          echo "ERROR !!! Unable to create composer PeerAdmin card for ${ORG_ID} with profile ${CONN_PROFILE}"
        else
          # Delete any existing composer card, if present from prior run, and import this card
          echo "Performing composer card delete and import for ${CARD_NAME}"
          composer card delete -n ${CARD_NAME}
          composer card import -f ${CARD_NAME}.card
          if [ $? -ne 0 ]; then
            echo "ERROR !!! Unable to import "${CARD_NAME}".card"
          else
            # Import success, run composer card create business Administrator card to access network as Organisation
            CARD_NAME=Admin-${ORG_ID}-${CHANNEL_NAME}@${CHAINCODE_NAME}
            composer card create -p ${CONN_PROFILE} -u Admin-${ORG_ID}-${CHANNEL_NAME} -n ${CHAINCODE_NAME} -c Admin-${ORG_ID}/admin-pub.pem -k Admin-${ORG_ID}/admin-priv.pem
            if [ $? -ne 0 ]; then
              echo "ERROR !!! Composer identity request failed for -c ${CARD_NAME} -d Admin-${ORG_ID}"
            else
              # Delete any existing composer card, if present from prior run, and import this card
              echo "Performing composer card delete and import for ${CARD_NAME}"
              composer card delete -n ${CARD_NAME}
              composer card import -f ${CARD_NAME}.card
              if [ $? -ne 0 ]; then
                echo "ERROR !!! Unable to import "${CARD_NAME}".card"
              fi
            fi
          fi
        fi
      else
        echo "Composer card create, couldn't locate connection profile: ${CONN_PROFILE}"
      fi
    done
  done

  cd "$CURRENT_DIR"
}

echo
# check that the composer command exists at a version v0.16.x
if hash composer 2>/dev/null; then
    composer --version | awk -F. '{if ($2<16) exit 1}'
    if [ $? -eq 1 ]; then
        echo 'Cannot use this version of composer with this level of fabric' 
        exit 1
    else
        echo Using composer-cli at $(composer --version)
    fi
else
    echo 'Need to have composer-cli installed at v0.16.x for proceeding'
    exit 1
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
  esac
done

# Determine whether starting, stopping, restarting or generating for announce
if [ "$MODE" == "up" ]; then
  EXPMODE="Bringing up Business Network,"
  elif [ "$MODE" == "down" ]; then
  EXPMODE="Bringing down Business Network,"
  elif [ "$MODE" == "restart" ]; then
  EXPMODE="Restarting Business Network,"
  elif [ "$MODE" == "generate" ]; then
  EXPMODE="Generating connection profiles and Composer cards,"
else
  echo "Composer mode: ${MODE} encountered, exiting(1)"
  exit 1
fi

# Check if specific Business Network Archive (BNA) directory provided
ADDITIONS=""
if [ -z "$CHAINCODE_NAME" ]; then
  ADDITIONS="${ADDITIONS} and default Business Network Archive 'trade-network'"
  CHAINCODE_NAME="trade-network"
else
  if [ ! -d "./chaincode/${CHAINCODE_NAME}" ]; then
    echo "Couldn't locate chaincode deployment directory './chaincode/${CHAINCODE_NAME}'"
    ADDITIONS="${ADDITIONS} and default Business Network Archive 'trade-network'"
    CHAINCODE_NAME="trade-network"
  else
    ADDITIONS="${ADDITIONS} and Business Network Archive '${CHAINCODE_NAME}'"
  fi
fi
echo "${EXPMODE}${ADDITIONS}"

#Create the network using docker compose
if [ "${MODE}" == "up" ]; then
  echo
  biznetUp
  elif [ "${MODE}" == "down" ]; then ## Clear the network
    echo
    biznetDown
  elif [ "${MODE}" == "generate" ]; then ## Generate Artifacts
    echo
    createConnProfiles
    createComposerCards
  elif [ "${MODE}" == "restart" ]; then ## Restart the network
    echo
    biznetDown
    askProceed
    biznetUp
else
  echo "Composer mode: ${MODE} encountered, exiting(1)"
  exit 1
fi
