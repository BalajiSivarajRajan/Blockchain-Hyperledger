#!/bin/bash
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

# This script is designed to be run in the trader1cli container as the
# second step of the BYFN tutorial. It joins the trader1 peers to the
# channel previously setup in the BYFN tutorial and install the
# chaincode as version 2.0 on peer0.trader1.
#

echo
echo "========= Getting trader1 on to your first network ========= "
echo
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

# import utils
. scripts/utils.sh

echo "Fetching channel config block from orderer..."
peer channel fetch 0 $CHANNEL_NAME.block -o orderer.tradent.com:7050 -c $CHANNEL_NAME --tls --cafile $ORDERER_CA >&log.txt
res=$?
cat log.txt
verifyResult $res "Fetching config block from orderer has Failed"

echo "===================== Having peer0.trader1 join the channel ===================== "
peer channel join -b $CHANNEL_NAME.block
echo "===================== peer0.trader1 joined the channel \"$CHANNEL_NAME\" ===================== "
# echo "===================== Having peer1.trader1 join the channel ===================== "
# joinChannelWithRetry 1 3
# echo "===================== peer1.trader1 joined the channel \"$CHANNEL_NAME\" ===================== "
# echo "Installing chaincode 2.0 on peer0.trader1..."
# installChaincode 0 3 2.0

echo
echo "========= Got trader1 halfway onto your first network ========= "
echo

exit 0
