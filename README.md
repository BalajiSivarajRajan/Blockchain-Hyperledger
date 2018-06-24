##  What is Blockchain? 
  There is no single definition for Blockchain. According to me Blockchain is an immutable distributed ledger that records the transactions in a decentralized environment.  It’s an ordered list of all the transactions since inception. There are different type of Blockchain like public(permissionless) & permission. In this writeup I going to discuss about the permission Blockchain – Hyperledger Fabric. 


![alt text](https://github.com/BalajiSivarajRajan/Blockchain-Hyperledger/blob/master/commodity-exchange/images/current-state.png)

### <p align="center"> Current state of transactions
  
## What is distributed ledger? 
  It is a set of records that are shared, replicated and synchronized among the participants in a network. It records all the transactions like exchange of data or assets among the participants in the network. 

## Problem statement: 
  There are different participants in a business and every participants keeps their own ledger copy. Transactions are bilateral and each participants has to interact with each other and thus by creating a complex network. Transaction are governed by a central body which needs multiple approvals. This is a time & money consuming task. 

### Trust: 
  Establishing trust in a network is very difficult and it’s a time consuming with subject of reputation. Reputed and governing body takes time to create trust. 

### Transparency: 
  As each participant in the network has its own ledger which is not shared and so there is no transparency in the network. 

### Accountability:  
  Regulators like bank, clearinghouse, stock exchange, legal services are required as a middlemen to ensure the accountability of the transaction.

## How Blockchain helps?
  Blockchain is a tamper-proof immutable distributed ledger which records all the transactions in a network. The ledger is maintained by all participants and it is distributed in a peer-to-peer network.  Instead of trusting on the 3rd party or central governances, Blockchain uses consensus protocol to commit a transaction into the ledger. Integrity of the transaction are achieved by cryptographic hashes and digital signatures.   

## How Blockchain works?
  In a distributed peer-to-peer network, transactions are stored in blocks which are linked together to form chain and this is called as Blockchain. Each block contains hash of the current block, timestamp of recent valid transaction and hash for the previous block. Previous block hash is used to link the block and prevents from altering the block or inserting between blocks. 
  
![alt text](https://github.com/BalajiSivarajRajan/Blockchain-Hyperledger/blob/master/commodity-exchange/images/Blockchain-state.png)

### <p align="center"> Blockchain state of transactions

## Hyperledger – Linux foundation project
  Hyperledger is an open source hosted by Linux foundation and openly governed by collaborative effort to advance the cross-industry blockchain technologies for business. Hyperledger Fabric is a blockchain framework implementation and it is one of the Hyperledger projects. 

  Some key feature of Fabric:
    -	No  token
    -	Permissioned blockchain
    -	Based on consensus 
    -	Endorsement polices for transactions approvals 
    -	Private Channels for sharing confidential information
    
### Components of Hyperledger fabric

### Peers
  These are the network services that maintain the ledger. It receives ordered update messages for committing new transaction to the ledger and to run the smart contacts. 

### Committing peers
  It commits transactions and maintains the ledger & state.

### Endorsing peers
  It receives transactions for endorsement and it verifies whether the transaction fulfills all the necessary and sufficient conditions. Thereby the Endorsing peer responds by granting or denying the endorsement.

### Ordering service or Orderers
  It approves the inclusion of a blocks into the ledger. It communicates with peers and endorsing peers. It provides shared  communication channel to clients and peers over which the transaction can be broadcasted.

### Channels
  These are subnets of the peer network which shares a single ledger. It is used to restrict access to transaction with involved parties. It means clients only can see the messages and their associated transactions of the channels they are connected to and are unaware of other channels.

### Certificate authorities
  It provides identity services to participants on the network. It manages different types of certificates required to run the blockchain.

### Smart contracts
  It’s the transaction logic running on each invocation call. Transaction invocation results in updating or querying the ledger state.

### Consensus
  It’s the process by which the agreement is obtained on the peer network. It is responsible for consistently replicating the ledger and for agreeing on new blocks. 

### Shared ledger
  It is an immutable record of all transactions on the network. It’s a collection of records that all participants on the network can access. 

### Client
  It is an End-user application which must be connected to the Blockchain through a peer. 

## Architecture of Hyperledger Fabric v1

![alt text](https://github.com/BalajiSivarajRajan/Blockchain-Hyperledger/blob/master/commodity-exchange/images/Hyperledger-architecture-v1.png)

## How it works? 
  Client application / SDK submits a transaction proposal for a chaincode by targeting the required peers. All the Endorser peers will execute the transactions. These transactions will not be updated in the ledger as it is only to endorse. Once endorsement is completed, it is signed by the endorser and returned to the client. The client then submit the transaction to the Orderer. It is then the Ordering service collects the transaction in blocks and distributes to the committing peers. These committing peers then delivers to other peers using gossip. There are different ordering algorithms are available such as SOLO (single node, development), Kafka, SBFT. 
 
![alt text](https://github.com/BalajiSivarajRajan/Blockchain-Hyperledger/blob/master/commodity-exchange/images/fabric-transaction-processing.png)

  Committing peers validate the transactions against the endorsement policy and also check whether the transactions are valid for the current state. After all these process the transactions are written into the ledger. Client applications are notified when the transactions are succeed or failed and also when the blocks are added into the ledger, if they are registered for the notification. Client application will also be notified by each peer to which they are connected to. 

## Conclusion
  I have given an overview of what Blockchain is and high level view of Hyperledger fabric. This approach can be used across various business areas like finance, supply chain, trade, etcs.
