# WHEAT V1 Core

[![Truffle CI Actions Status](https://github.com/GrowthDeFi/wheat-v1-core/workflows/Truffle%20CI/badge.svg)](https://github.com/GrowthDeFi/wheat-v1-core/actions)

This repository contains the source code for the WHEAT smart contracts
(Version 1) and related support code.

## Deployed Contracts

| Token         | BSC Mainnet Address                                                                                                  |
| ------------- | -------------------------------------------------------------------------------------------------------------------- |
| WHEAT         | [0x3ab63309F85df5D4c3351ff8EACb87980E05Da4E](https://bscscan.com/address/0x3ab63309F85df5D4c3351ff8EACb87980E05Da4E) |
| MasterChef    | [0x95fABAe2E9Fb0A269cE307550cAC3093A3cdB448](https://bscscan.com/address/0x95fABAe2E9Fb0A269cE307550cAC3093A3cdB448) |

## MasterChef Configuration

Published at launch:

| WHEAT pid | Token           | Alloc Points | CAKE pid | Routing Token |
| ----------| -------------------------------------------------------------------------------------- | -------------|--------- | ------------- |
| 0         | [WHEAT](https://bscscan.com/address/0x3ab63309F85df5D4c3351ff8EACb87980E05Da4E)        | 15000        | -        | -             |
| 1         | [BNB/WHEAT](https://bscscan.com/address/0xba2aBFfaF06A83AC2a4beE91bB009409EE0c771D)    | 30000        | -        | -             |
| 2         | [BNB/GRO](https://bscscan.com/address/0x5eEb5A7d5229687698825d30e8302A56c5404d4b)      | 3000         | -        | -             |
| 3         | [GRO/gROOT](https://bscscan.com/address/0xd665A0b6293C6Bc05D3823Acb0c1596D4B88F3B2)    | 1000         | -        | -             |
| 4         | [BNB/gROOT](https://bscscan.com/address/0x7Fb2C6B9377480FcFB3afB987fD5be6F6139d8c4)    | 1000         | -        | -             |
| 5         | [stkCAKE](https://bscscan.com/address/0x84BA65DB2da175051E25F86e2f459C863CBb3E0C)      | 15000        | 0        | CAKE          |
| 6         | [stkBNB/CAKE](https://bscscan.com/address/0xb290b079d7386C8e6F7a01F2f83c760aD807752C)  | 15000        | 1        | CAKE          |
| 7         | [stkBNB/BUSD](https://bscscan.com/address/0x5cce1C68Db563586e10bc0B8Ef7b65265971cD91)  | 7000         | 2        | BNB           |
| 8         | [stkBNB/BTCB](https://bscscan.com/address/0x61f6Fa43D16890382E38E32Fd02C7601A271f133)  | 3000         | 15       | BNB           |
| 9         | [stkBNB/ETH](https://bscscan.com/address/0xc9e459BF16C10A40bc7daa4a2366ac685cEe784F)   | 3000         | 14       | BNB           |
| 10        | [stkBNB/LINK](https://bscscan.com/address/0xB2a97CC57AC2229a4017227cf71a28271a89f569)  | 1000         | 7        | BNB           |
| 11        | [stkBNB/UNI](https://bscscan.com/address/0x12821BE81Ee152DF53bEa1b9ad0B45A6d95B1ad5)   | 1000         | 25       | BNB           |
| 12        | [stkBNB/DOT](https://bscscan.com/address/0x9Be3593e1784E6Dc8A0b77760aA9e917Ed579676)   | 1000         | 5        | BNB           |
| 13        | [stkBNB/ADA](https://bscscan.com/address/0x13342abC6FD747dE2F11c58cB32f7326BE331183)   | 1000         | 3        | BNB           |
| 14        | [stkBUSD/UST](https://bscscan.com/address/0xd27F9D92cb456603FCCdcF2eBA92Db585140D969)  | 1000         | 63       | BUSD          |
| 15        | [stkBUSD/DAI](https://bscscan.com/address/0xEe827483fb49a72C8c13C460275e39f7A59fB439)  | 1000         | 52       | BUSD          |
| 16        | [stkBUSD/USDC](https://bscscan.com/address/0x97527E4033CAdD548eB2Eb5dB3BCdd8BF21f925D) | 1000         | 53       | BUSD          |

Published (or to be published) later:

| WHEAT pid | Token           | Alloc Points | CAKE pid | Routing Token |
| ----------| --------------- | -------------|--------- | ------------- |
| 17        | stkBTCB/bBADGER | 1000         | 106      | BTCB          |
| 18        | stkBNB/BSCX     | 1000         | 51       | BNB           |
| 19        | stkBNB/BRY      | 1000         | 75       | BNB           |
| 20        | stkBNB/WATCH    | 1000         | 84       | BNB           |
| 21        | stkBNB/BTCST    | 1000         | 55       | BNB           |
| 22        | stkBUSD/IOTX    | 1000         | 81       | BUSD          |
| 23        | stkBUSD/TPT     | 1000         | 85       | BUSD          |
| 24        | stkBNB/ZIL      | 1000         | 108      | BNB           |
| 25        | stkBNB/TWT      | 1000         | 12       | BNB           |
| 26        | stkBNB/bOPEN    | 1000         | 79       | BNB           |

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
