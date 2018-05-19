#!/bin/bash -x


# Grab the current directory, and change to it
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
THIS_SCRIPT=`basename "$0"`
cd ${CURRENT_DIR}

# Declare an array of our Organisations, this should match with configtx.yaml & crypto-config.yaml
declare -a Channels=("exch-trader2" "exch-trader3")
declare -a Orgs=("CommodityExchange" "trader2" "trader3")
declare CHAINCODE_NAME="commodity-exchange"

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

cd composer-cards

# # Install chaincode as per settings, we can't be clever enough here (but lets try)
# for (( i=0; i < ${#Orgs[@]}; i++ )); do
#   ORG_ID="${Orgs[$i]}"

#   # Install the runtime (chaincode) using the PeerAdmin@${ORG_ID}-only
#   composer runtime install -c PeerAdmin@${ORG_ID}-only -n ${CHAINCODE_NAME}
#   if [ $? -ne 0 ]; then
#     echo "ERROR !!! Unable to perform runtime install using '-c PeerAdmin@${ORG_ID}-only -n ${CHAINCODE_NAME}'"
#   fi
# done

# You should be now ready to Instantiate the chaincode (or BNA)
echo "You're about to start network manually, assuming all Cards, Fabric up and runnig ..."
#askProceed

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

    PING_ID=Admin-"${Orgs[$0]}"-${CHANNEL_NAME}@${CHAINCODE_NAME}
    # Composer network ping using Admin-Org1-exch-CHANNEL1@CHAINCODE
    composer network ping -c ${PING_ID}
    if [ $? -ne 0 ]; then
      echo "ERROR !!! Unable to perform 'Composer network ping -c ${PING_ID}'"
    fi
  fi
done

cd $CURRENT_DIR
