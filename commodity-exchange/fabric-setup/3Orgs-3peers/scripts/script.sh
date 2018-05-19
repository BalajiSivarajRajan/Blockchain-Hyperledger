#!/bin/bash

echo
echo " ____    _____      _      ____    _____ "
echo "/ ___|  |_   _|    / \    |  _ \  |_   _|"
echo "\___ \    | |     / _ \   | |_) |   | |  "
echo " ___) |   | |    / ___ \  |  _ <    | |  "
echo "|____/    |_|   /_/   \_\ |_| \_\   |_|  "
echo
echo "Build the CommodityExchange network (CommodityExchange) for end-to-end test"
echo
CHANNEL_NAME="$1"
DELAY="$2"
LANGUAGE="$3"
: ${CHANNEL_NAME:="exch-channel"}
: ${TIMEOUT:="60"}
: ${LANGUAGE:="golang"}
LANGUAGE=`echo "$LANGUAGE" | tr [:upper:] [:lower:]`
COUNTER=1
MAX_RETRY=5
ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/tradent.com/orderers/orderer.tradent.com/msp/tlscacerts/tlsca.tradent.com-cert.pem

CC_SRC_PATH="github.com/chaincode/chaincode_example02/go/"
echo "Channel name : "$CHANNEL_NAME

# Declare an array of our Organisations, this should match with configtx.yaml & crypto-config.yaml
declare -a Orgs=("CommodityExchange" "trader2" "trader3")

# import Utilities
. scripts/utils.sh

## Create and Join peers with channel
for (( i=1; i < ${#Orgs[@]}; i++ ));
do
	# Create the needed channels (for 3 Organisations it is 2 channels)
	CHANNEL_NAME="exch-${Orgs[$i]}"
	echo "Creating channel...${CHANNEL_NAME}"
	createChannel

	# Join channels in Star architecture, centre being ${Orgs[$0]}
	#echo "Joining ${Orgs[$0]} and ${Orgs[$i]} with ${CHANNEL_NAME}"
	joinWithRetry 0 0
	joinWithRetry i 0
done

# ## Set the anchor peers for each org in the channel
# echo "Updating anchor peers for CommodityExchange..."
# updateAnchorPeers 0 0
# echo "Updating anchor peers for trader2..."
# updateAnchorPeers 1 0
# echo "Updating anchor peers for trader3..."
# updateAnchorPeers 2 0

## Continue with chaincode install and instantiate, in case pure Fabric go-code was the intention,
## Else, we might as well stop here after channel creation, joining and updating anchor peers
if [ "$LANGUAGE" = "golang" ]; then
	# CC_SRC_PATH="/opt/gopath/src/github.com/chaincode/chaincode_example02/node/"

	# Install chaincode on Peer0/CommodityExchange and Peer2/trader3
	CHANNEL_NAME="exch-trader2"
	echo "Installing chaincode exch-trader2 on CommodityExchange/peer0..."
	installChaincode 0 0
	echo "Install chaincode exch-trader2 on trader2/peer0..."
	installChaincode 1 0

	# Install chaincode on Peer0/CommodityExchange and Peer2/trader3
	CHANNEL_NAME="exch-trader3"
	echo "Installing chaincode exch-trader3 on CommodityExchange/peer0..."
	installChaincode 0 0
	echo "Install chaincode exch-trader3 on trader3/peer0..."
	installChaincode 2 0

	# Instantiate chaincode on trader2/peer0
	# Docker instantiate dev-peer0.trader2.CommodityExchange.com-exchcc-1.0-{docker-id}
	CHANNEL_NAME="exch-trader2"
	echo "Instantiating chaincode exch-trader2 on trader2/peer0..."
	instantiateChaincode 1 0

	# Instantiate chaincode on trader2/peer0
	# Docker instantiate dev-peer0.trader2.CommodityExchange.com-exchcc-1.0-{docker-id}
	CHANNEL_NAME="exch-trader3"
	echo "Instantiating chaincode exch-trader3 on trader3/peer0..."
	instantiateChaincode 2 0

	# Query on chaincode on Peer0/CommodityExchange
	# Docker instantiate dev-peer0.CommodityExchange.CommodityExchange.com-exchcc-1.0-{docker-id}
	echo "Querying chaincode on CommodityExchange/peer0..."
	chaincodeQuery 0 0 100

	# Invoke on chaincode on Peer0/CommodityExchange
	# Should just fetch results, from CommodityExchange/PEER0
	echo "Sending invoke transaction on CommodityExchange/peer0..."
	chaincodeInvoke 0 0

	# Query on chaincode on Peer0/trader3, check if the result is 90
	# Docker instantiate dev-peer0.trader3.CommodityExchange.com-exchcc-1.0-{docker-id}
	echo "Querying chaincode on trader3/peer3..."
	chaincodeQuery 2 0 90
fi

echo
echo "========= All GOOD, CommodityExchange execution completed =========== "
echo

echo
echo " _____   _   _   ____   "
echo "| ____| | \ | | |  _ \  "
echo "|  _|   |  \| | | | | | "
echo "| |___  | |\  | | |_| | "
echo "|_____| |_| \_| |____/  "
echo

exit 0