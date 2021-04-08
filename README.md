# WHEAT V1 Core

[![Truffle CI Actions Status](https://github.com/GrowthDeFi/wheat-v1-core/workflows/Truffle%20CI/badge.svg)](https://github.com/GrowthDeFi/wheat-v1-core/actions)

This repository contains the source code for the WHEAT smart contracts
(Version 1) and related support code.

## Deployed Contracts

| Token         | BSC Mainnet Address                                                                                                   |
| ------------- | --------------------------------------------------------------------------------------------------------------------- |

| Token         | BSC Testnet Address                                                                                                   |
| ------------- | --------------------------------------------------------------------------------------------------------------------- |

## MasterChef Mainnet Configuration

Published at launch:

| WHEAT pid | Token           | Alloc Points | CAKE pid | Routing Token |
| ----------| --------------- | -------------|--------- | ------------- |
| 0         | WHEAT           | 15000        | -        | -             |
| 1         | BNB/WHEAT       | 30000        | -        | -             |
| 2         | BNB/GRO         | 3000         | -        | -             |
| 3         | GRO/gROOT       | 1000         | -        | -             |
| 4         | BNB/gROOT       | 1000         | -        | -             |
| 5         | stkCAKE         | 15000        | 0        | CAKE          |
| 6         | stkBNB/CAKE     | 15000        | 1        | CAKE          |
| 7         | stkBNB/BUSD     | 5000         | 2        | BNB           |
| 8         | stkBNB/BTCB     | 3000         | 15       | BNB           |
| 9         | stkBNB/ETH      | 3000         | 14       | BNB           |
| 10        | stkBETH/ETH     | 2000         | 70       | ETH           |
| 11        | stkBNB/LINK     | 1000         | 7        | BNB           |
| 12        | stkBNB/UNI      | 1000         | 25       | BNB           |
| 13        | stkBNB/DOT      | 1000         | 5        | BNB           |
| 14        | stkBNB/ADA      | 1000         | 3        | BNB           |
| 15        | stkBUSD/UST     | 1000         | 63       | BUSD          |
| 16        | stkBUSD/DAI     | 1000         | 52       | BUSD          |
| 17        | stkBUSD/USDC    | 1000         | 53       | BUSD          |

Published (or to be published) later:

| WHEAT pid | Token           | Alloc Points | CAKE pid | Routing Token |
| ----------| --------------- | -------------|--------- | ------------- |
| 18        | stkBTCB/bBADGER | 1000         | 106      | BTCB          |
| 19        | stkBNB/BSCX     | 1000         | 51       | BNB           |
| 20        | stkBNB/BRY      | 1000         | 75       | BNB           |
| 21        | stkBNB/WATCH    | 1000         | 84       | BNB           |
| 22        | stkBNB/BTCST    | 1000         | 55       | BNB           |
| 23        | stkBUSD/IOTX    | 1000         | 81       | BUSD          |
| 24        | stkBUSD/TPT     | 1000         | 85       | BUSD          |
| 25        | stkBNB/ZIL      | 1000         | 108      | BNB           |
| 26        | stkBNB/TWT      | 1000         | 12       | BNB           |
| 27        | stkBNB/bOPEN    | 1000         | 79       | BNB           |

## Repository Organization

* [/contracts/](contracts). This folder is where the smart contract source code
  resides.
* [/migrations/](migrations). This folder hosts the relevant set of Truffle
  migration scripts used to publish the smart contracts to the blockchain.
* [/scripts/](scripts). This folder contains scripts to run local forks.
* [/test/](test). This folder contains relevant unit tests for Truffle written
  in Solidity.

## Building, Deploying and Testing

Configuring the repository:

    $ npm i

Compiling the smart contracts:

    $ npm run build

Running the unit tests:

    $ ./scripts/start-bscmain-fork.sh & npm run test:bscmain

_(Standard installation of Node 14.15.4 on Ubuntu 20.04)_
