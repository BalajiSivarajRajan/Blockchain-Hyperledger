##  What is Blockchain? 
  There is no single definition for Blockchain. According to me Blockchain is – it’s a immutable distributed ledger that records the transactions in a decentralized environment.  It’s an ordered list of all the transactions since inception. There are different type of Blockchain, public & permission. In this writeup I will talk about the permission Blockchain – Hyperledger Fabric. 


![alt text](https://github.com/BalajiSivarajRajan/Blockchain-Hyperledger/blob/master/commodity-exchange/current-state.png)

### <p align="center"> Current state of transactions
  
## What is distributed ledger? 
  It a set of records that are shared, replicated and synchronized among the participants in a network. It records the all the transactions like exchange of data or assets among the participants in the network. 

## Problem statement: 
  There are different participants in a business and every participants keeps their own ledger copy. Transactions are bilateral and each participants has to interact with each other and thus my creating a complex network. Transaction are governed by a central body and which needs multiple approvals. This is a time & money consuming task. 

### Trust: 
  Establishing trust in a network is very difficult and it’s a time consuming with subjective of reputation. Reputed and governing body take time to create trust. 

### Transparency: 
  With each participant in the network has its own ledger there is no transparency in the network and the ledgers are not shared. 
Accountability:  Regulators like bank, clearinghouse, stock exchange, legal services are required as middlemen to ensure the accountability of the transaction.

## How Blockchain helps?
  Blockchain is a tamper-proof, distributed ledger which all records that happens in a network. The ledger is maintains by all the participants and it is distributed to all the participants in a peer-to-peer network which can public or private.  Instead of trusting on the 3rd party or central governances, Blockchain uses consensus protocol to transaction committed into ledger. Integrity of the transaction are achieved by cryptographic hashes and digital signatures.   

## How Blockchain works?
  In a distributed peer-to-peer network transactions are stored in blocks which are linked together to form chain and this is called as Blockchain. Each block contains hash of the current block, timestamp of recent valid transaction and hash for the previous block. Previous block hash is used to link the block and prevents from altering the block or inserting between blocks. 
  
![alt text](https://github.com/BalajiSivarajRajan/Blockchain-Hyperledger/blob/master/commodity-exchange/current-state.png)

### <p align="center"> Blockchain state of transactions

## Hyperledger – Linux foundation project
  Hyperledger is an open source and openly governed collaborative effort to advance cross-industry blockchain technologies for business, hosted by The Linux Foundation. Hyperledger Fabric is a blockchain framework implementation and one of the Hyperledger projects. 

  Some key feature of Fabric:
    -	No  token
    -	Permissioned blockchain
    -	Based on consensus 
    -	Endorsement polices for transactions approvals 
    -	Private Channels  for sharing confidential information
    
### Components of Hyperledger fabric

### Peers
  They are networked services and maintain the ledger. It receive ordered update messages for committing new transaction to the ledger and run smart contacts. 

### Committing peers
  It commits transactions and maintains ledger & state

### Endorsing peers
  It receives transactions for endorsement transaction by checking whether they fulfil necessary and sufficient conditions and responds by granting or denying the endorsement

### Ordering service or Orderers
  It approves the inclusion of a blocks into the ledger. It communicates with peers and endorsing peers. They provide communication channel to clients and peers over which messages containing transaction can be broadcasted. It provides a shared communication channel to peers and clients.

### Channels
  These are Subnet of the peer network that share a single ledger. Its used to restrict access to transaction with involved parties only which means clients only see the messages and associated transactions of the channels they are connected to and are unaware of other channels.

### Certificate authorities
  It provides identity services to participants on the network. It manages different type of certificates required to run the blockchain

### Smart contracts
  It’s the transaction logic running on each invocation call. Transaction invocation results in updating or querying the ledger state

### Consensus
  It’s the process by which the agreement is obtained on the peer network. Its responsible for consistently replicating the ledger and for agreeing on new block. 

### Shared ledger
  Immutable record of all transactions on the network. It’s a collection of records that all participants on the network can access. 

### Client
  End-user applications which must be connected to the Blockchain through a peer. 

## Architecture of Hyperledger Fabric v1

! [alt text]

## How it works? 
Client application / SDK submits a transaction proposal for a chaincode by targeting the required peers. All the Endorser will execute  the transaction. These transactions will not be updated in the ledger as its only to endorse. Once endorsement is completed, its signed by the endorser and returned to the client. The client then submit the transaction to the Orderer. Its then the Ordering service collects the transaction in blocks and distributes to the committing peers. These committing peers then delivers to other peers using gossip. There are different ordering algorithms are available and they are SOLO (single node, development), Kafka, SBFT. 
 
! [alt text]

Committing peers validate the transaction against the endorsement policy and also check whether they are valid for the current state. After all these process, the transactions are written into the ledger. Client applications are notified when the transactions are succeed or failed and also when the blocks are added into the ledger, if the client applications are registered for the notification. Client application will be notified by each peer to which they are connected to. 
