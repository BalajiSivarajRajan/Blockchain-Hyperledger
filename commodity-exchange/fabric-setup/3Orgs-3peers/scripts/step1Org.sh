#!/bin/bash
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

# This script is designed to be run in the org3cli container as the
# first step of the BYFN tutorial.  It creates and submits a
# configuration transaction to add org3 to the network previously
# setup in the BYFN tutorial.
#

CHANNEL_NAME="$1"
DELAY="$2"
LANGUAGE="$3"
TIMEOUT="$4"
: ${CHANNEL_NAME:="exch-channel"}
: ${DELAY:="3"}
: ${LANGUAGE:="golang"}
: ${TIMEOUT:="10"}
LANGUAGE=`echo "$LANGUAGE" | tr [:upper:] [:lower:]`
COUNTER=1
MAX_RETRY=5
ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/tradent.com/orderers/orderer.tradent.com/msp/tlscacerts/tlsca.tradent.com-cert.pem

CC_SRC_PATH="github.com/chaincode/chaincode_example02/go/"
if [ "$LANGUAGE" = "node" ]; then
	CC_SRC_PATH="/opt/gopath/src/github.com/chaincode/chaincode_example02/node/"
fi

echo
echo "========= Creating config transaction to add org3 to network =========== "
echo

echo "Installing and starting configtxlater"
apt-get -y update && apt-get -y install jq
configtxlator start >/dev/null 2>&1 &
CONFIGTXLATOR_URL=http://127.0.0.1:7059

echo "Fetching the most recent configuration block for the channel"
peer channel fetch config config_block.pb -o orderer.tradent.com:7050 -c ${CHANNEL_NAME} --tls --cafile ${ORDERER_CA}

echo "Creating config transaction adding org3 to the network"
# translate channel configuration block into JSON format
curl -X POST --data-binary @config_block.pb "$CONFIGTXLATOR_URL/protolator/decode/common.Block" | jq . > config_block.json

# strip away all of the encapsulating wrappers
jq .data.data[0].payload.data.config config_block.json > config.json

# append new org to the configuration
jq -s '.[0] * {"channel_group":{"groups":{"Application":{"groups":{"trader1MSP":.[1]}}}}}' config.json ./channel-artifacts/trader1.json >& updated_config.json

# translate json config files back to protobuf
curl -X POST --data-binary @config.json "$CONFIGTXLATOR_URL/protolator/encode/common.Config" > config.pb
curl -X POST --data-binary @updated_config.json "$CONFIGTXLATOR_URL/protolator/encode/common.Config" > updated_config.pb

# get delta between old and new configs
curl -X POST -F channel=$CHANNEL_NAME -F "original=@config.pb" -F "updated=@updated_config.pb" "${CONFIGTXLATOR_URL}/configtxlator/compute/update-from-configs" > config_update.pb

# translate protobuf delta to json
curl -X POST --data-binary @config_update.pb "$CONFIGTXLATOR_URL/protolator/decode/common.ConfigUpdate" | jq . > config_update.json

# wrap delta in an envelope message
echo '{"payload":{"header":{"channel_header":{"channel_id":"'${CHANNEL_NAME}'", "type":2}},"data":{"config_update":'$(cat config_update.json)'}}}' | jq . > config_update_in_envelope.json

# translate json back to protobuf
curl -X POST --data-binary @config_update_in_envelope.json "$CONFIGTXLATOR_URL/protolator/encode/common.Envelope" > config_update_in_envelope.pb

echo
echo "========= Config transaction to add trader1 to network created ===== "
echo

echo "Signing config transaction"
echo
peer channel signconfigtx -f config_update_in_envelope.pb

echo
echo "========= Submitting transaction from a different peer (peer0.trader2) which also signs it ========= "
echo
export CORE_PEER_LOCALMSPID="trader2MSP"
export CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/trader2.tradent.com/peers/peer0.trader2.tradent.com/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/trader2.tradent.com/users/Admin\@trader2.tradent.com/msp/
export CORE_PEER_ADDRESS=peer0.trader2.tradent.com:7051
peer channel update -f config_update_in_envelope.pb -c ${CHANNEL_NAME} -o orderer.tradent.com:7050 --tls true --cafile ${ORDERER_CA}

echo
echo "========= Config transaction to add trader1 to network submitted! =========== "
echo

exit 0
