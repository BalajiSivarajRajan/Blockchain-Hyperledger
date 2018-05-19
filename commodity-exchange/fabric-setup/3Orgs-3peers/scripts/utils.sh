# This is a collection of bash functions used by different scripts

# verify the result of the end-to-end test
verifyResult () {
	if [ $1 -ne 0 ] ; then
		echo "!!!!!!!!!!!!!!! "$2" !!!!!!!!!!!!!!!!"
    	echo "========= ERROR !!! FAILED to execute End-2-End Scenario ==========="
		echo
   		exit 1
	fi
}

setGlobals () {
	ORG_NAME="${Orgs[$1]}"

	echo "Setting necessary environment variables for Org: ${ORG_NAME}, Peer$2"
	CORE_PEER_LOCALMSPID="${ORG_NAME}MSP"
	CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/${ORG_NAME}.tradent.com/peers/peer0.${ORG_NAME}.tradent.com/tls/ca.crt
	CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/${ORG_NAME}.tradent.com/users/Admin@${ORG_NAME}.tradent.com/msp
	CORE_PEER_ADDRESS=peer$2.${ORG_NAME}.tradent.com:7051

	env |grep CORE
}

createChannel() {
	setGlobals 0 0

	if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
		peer channel create -o orderer.tradent.com:7050 -c $CHANNEL_NAME -f ./channel-artifacts/$CHANNEL_NAME.tx >&log.txt
	else
		peer channel create -o orderer.tradent.com:7050 -c $CHANNEL_NAME -f ./channel-artifacts/$CHANNEL_NAME.tx --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA >&log.txt
	fi
	res=$?
	cat log.txt
	verifyResult $res "Channel creation failed"
	echo "===================== Channel \"$CHANNEL_NAME\" is created successfully ===================== "
	echo
}

updateAnchorPeers() {
	ORG=$1
	PEER=$2
	setGlobals $ORG $PEER

	if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
		peer channel update -o orderer.tradent.com:7050 -c ${CHANNEL_NAME} -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors-${CHANNEL_NAME}.tx >&log.txt
	else
		peer channel update -o orderer.tradent.com:7050 -c ${CHANNEL_NAME} -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors-${CHANNEL_NAME}.tx --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA >&log.txt
	fi
	res=$?
	cat log.txt
	verifyResult $res "Anchor peer update failed"
	echo "===================== Anchor peers for org \"$CORE_PEER_LOCALMSPID\" on \"$CHANNEL_NAME\" is updated successfully ===================== "
	sleep $DELAY
	echo
}

## Sometimes Join takes time hence RETRY at least for 5 times
joinWithRetry () {
	setGlobals $1 $2
	peer channel join -b ${CHANNEL_NAME}.block  >&log.txt
	res=$?
	cat log.txt
	if [ $res -ne 0 -a $COUNTER -lt $MAX_RETRY ]; then
		COUNTER=` expr $COUNTER + 1`
		echo "PEER$1 failed to join the channel, Retry after 2 seconds"
		sleep $DELAY
		joinWithRetry $1 $2
	else
		COUNTER=1
	fi
  	verifyResult $res "After $MAX_RETRY attempts, \"$CORE_PEER_ADDRESS\" has failed to Join the Channel"
}

joinChannel () {
	for org in 0 1 2; do
		for ch in 0; do
			joinWithRetry $org $ch
			echo "===================== Peer: \"$CORE_PEER_ADDRESS\" joined on the channel \"$CHANNEL_NAME\" ===================== "
			sleep $DELAY
			echo
		done
	done
}

installChaincode () {
	ORG=$1
	PEER=$2
	VERSION=$3
	: ${VERSION:="1.0"}
	setGlobals $ORG $PEER

	peer chaincode install -n ${CHANNEL_NAME}-cc -v ${VERSION} -l ${LANGUAGE} -p ${CC_SRC_PATH} >&log.txt
	res=$?
	cat log.txt
    verifyResult $res "Chaincode installation on remote peer \"$CORE_PEER_ADDRESS\" has Failed"
	echo "===================== Chaincode is installed on remote peer \"$CORE_PEER_ADDRESS\" ===================== "
	echo
}

instantiateChaincode () {
	ORG=$1
	PEER=$2
	setGlobals $ORG $PEER

	# while 'peer chaincode' command can get the orderer endpoint from the peer (if join was successful),
	# lets supply it directly as we know it using the "-o" option
	ENDORSEMENT_POLICY="\"OR ('${Orgs[0]}MSP.member','${Orgs[1]}MSP.member','${Orgs[2]}MSP.member')\""
	echo "Endorsement Policy is set to: ${ENDORSEMENT_POLICY}"

	if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
		peer chaincode instantiate -o orderer.tradent.com:7050 -C ${CHANNEL_NAME} \
		-n ${CHANNEL_NAME}-cc -l ${LANGUAGE} -v 1.0 -c '{"Args":["init","a","100","b","200"]}' \
		-P "OR ('${Orgs[0]}MSP.member','${Orgs[1]}MSP.member','${Orgs[2]}MSP.member')" >&log.txt
	else
		peer chaincode instantiate -o orderer.tradent.com:7050 --tls $CORE_PEER_TLS_ENABLED \
		--cafile $ORDERER_CA -C ${CHANNEL_NAME} -n ${CHANNEL_NAME}-cc -l ${LANGUAGE} -v 1.0 \
		-c '{"Args":["init","a","100","b","200"]}' \
		-P "OR ('${Orgs[0]}MSP.member','${Orgs[1]}MSP.member','${Orgs[2]}MSP.member')" >&log.txt
	fi
	res=$?
	cat log.txt
	verifyResult $res "Chaincode instantiation on \"$CORE_PEER_ADDRESS\" on channel '$CHANNEL_NAME' failed"
	echo "===================== Chaincode Instantiation on \"$CORE_PEER_ADDRESS\" on channel '$CHANNEL_NAME' is successful ===================== "
	echo
}

chaincodeQuery () {
  ORG=$1
  PEER=$2
  echo "===================== Querying on \"$CORE_PEER_ADDRESS\" on channel '$CHANNEL_NAME'... ===================== "
  setGlobals $ORG $PEER
  local rc=1
  local starttime=$(date +%s)

  # continue to poll
  # we either get a successful response, or reach TIMEOUT
  while test "$(($(date +%s)-starttime))" -lt "$TIMEOUT" -a $rc -ne 0
  do
     sleep $DELAY
     echo "Attempting to Query \"$CORE_PEER_ADDRESS\" ...$(($(date +%s)-starttime)) secs"
     peer chaincode query -C $CHANNEL_NAME -n ${CHANNEL_NAME}-cc -c '{"Args":["query","a"]}' >&log.txt
     test $? -eq 0 && VALUE=$(cat log.txt | awk '/Query Result/ {print $NF}')
     test "$VALUE" = "$3" && let rc=0
  done
  echo
  cat log.txt
  if test $rc -eq 0 ; then
	echo "===================== Query on \"$CORE_PEER_ADDRESS\" on channel '$CHANNEL_NAME' is successful ===================== "
  else
	echo "!!!!!!!!!!!!!!! Query result on \"$CORE_PEER_ADDRESS\" is INVALID !!!!!!!!!!!!!!!!"
    echo "================== ERROR !!! FAILED to execute End-2-End Scenario =================="
	echo
	exit 1
  fi
}

chaincodeInvoke () {
	ORG=$1
	PEER=$2
	setGlobals $ORG $PEER

	# while 'peer chaincode' command can get the orderer endpoint from the peer (if join was successful),
	# lets supply it directly as we know it using the "-o" option
	if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
		peer chaincode invoke -o orderer.tradent.com:7050 -C ${CHANNEL_NAME} -n ${CHANNEL_NAME}-cc -c '{"Args":["invoke","a","b","10"]}' >&log.txt
	else
		peer chaincode invoke -o orderer.tradent.com:7050  --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA -C ${CHANNEL_NAME} -n ${CHANNEL_NAME}-cc -c '{"Args":["invoke","a","b","10"]}' >&log.txt
	fi
	res=$?
	cat log.txt
	verifyResult $res "Invoke execution on \"$CORE_PEER_ADDRESS\" failed "
	echo "===================== Invoke transaction on \"$CORE_PEER_ADDRESS\" on channel '$CHANNEL_NAME' is successful ===================== "
	echo
}
