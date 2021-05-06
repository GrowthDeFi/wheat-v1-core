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

Already published:

| WHEAT pid | Token                                                                                    | Underlying pid  | Routing Token |
| ----------| ---------------------------------------------------------------------------------------- | --------------- | ------------- |
| 0         | [WHEAT](https://bscscan.com/address/0x3ab63309F85df5D4c3351ff8EACb87980E05Da4E)          | -               | -             |
| 1         | [BNB/WHEAT](https://bscscan.com/address/0xba2aBFfaF06A83AC2a4beE91bB009409EE0c771D)      | -               | -             |
| 2         | [BNB/GRO](https://bscscan.com/address/0x5eEb5A7d5229687698825d30e8302A56c5404d4b)        | -               | -             |
| 3         | [GRO/gROOT](https://bscscan.com/address/0xd665A0b6293C6Bc05D3823Acb0c1596D4B88F3B2)      | -               | -             |
| 4         | [BNB/gROOT](https://bscscan.com/address/0x7Fb2C6B9377480FcFB3afB987fD5be6F6139d8c4)      | -               | -             |
| 5         | [stkCAKE](https://bscscan.com/address/0x84BA65DB2da175051E25F86e2f459C863CBb3E0C)        | PancakeSwap 0   | CAKE          |
| 6         | [stkBNB/CAKE](https://bscscan.com/address/0xb290b079d7386C8e6F7a01F2f83c760aD807752C)    | PancakeSwap 1   | CAKE          |
| 7         | [stkBNB/BUSD](https://bscscan.com/address/0x5cce1C68Db563586e10bc0B8Ef7b65265971cD91)    | PancakeSwap 2   | BNB           |
| 8         | [stkBNB/BTCB](https://bscscan.com/address/0x61f6Fa43D16890382E38E32Fd02C7601A271f133)    | PancakeSwap 15  | BNB           |
| 9         | [stkBNB/ETH](https://bscscan.com/address/0xc9e459BF16C10A40bc7daa4a2366ac685cEe784F)     | PancakeSwap 14  | BNB           |
| 10        | [stkBNB/LINK](https://bscscan.com/address/0xB2a97CC57AC2229a4017227cf71a28271a89f569)    | PancakeSwap 7   | BNB           |
| 11        | [stkBNB/UNI](https://bscscan.com/address/0x12821BE81Ee152DF53bEa1b9ad0B45A6d95B1ad5)     | PancakeSwap 25  | BNB           |
| 12        | [stkBNB/DOT](https://bscscan.com/address/0x9Be3593e1784E6Dc8A0b77760aA9e917Ed579676)     | PancakeSwap 5   | BNB           |
| 13        | [stkBNB/ADA](https://bscscan.com/address/0x13342abC6FD747dE2F11c58cB32f7326BE331183)     | PancakeSwap 3   | BNB           |
| 14        | [stkBUSD/UST](https://bscscan.com/address/0xd27F9D92cb456603FCCdcF2eBA92Db585140D969)    | PancakeSwap 63  | BUSD          |
| 15        | [stkBUSD/DAI](https://bscscan.com/address/0xEe827483fb49a72C8c13C460275e39f7A59fB439)    | PancakeSwap 52  | BUSD          |
| 16        | [stkBUSD/USDC](https://bscscan.com/address/0x97527E4033CAdD548eB2Eb5dB3BCdd8BF21f925D)   | PancakeSwap 53  | BUSD          |
| 17        | -                                                                                        | -               | -             |
| 18        | [stkBNB/CAKEv2](https://bscscan.com/address/0x4291474e88E2fEE6eC5B8c28F4Ed2075cEf5B803)  | PancakeSwap 251 | CAKE          |
| 19        | [stkBNB/BUSDv2](https://bscscan.com/address/0xdC4D358B34619e4fE7feb28bE301B2FBe4F3aFf9)  | PancakeSwap 252 | BNB           |
| 20        | [stkBNB/BTCBv2](https://bscscan.com/address/0xA561fa603bf0B43Cb0d0911EeccC8B6777d3401B)  | PancakeSwap 262 | BNB           |
| 21        | [stkBNB/ETHv2](https://bscscan.com/address/0x28e6aa3DD98372Da0959Abe9d0efeB4455d4dFe1)   | PancakeSwap 261 | BNB           |
| 22        | [stkBNB/LINKv2](https://bscscan.com/address/0x3B88a64D0B9fA485B71c98B00D799aa8D1aEe9E3)  | PancakeSwap 257 | BNB           |
| 23        | [stkBNB/UNIv2](https://bscscan.com/address/0x515785CE5D5e94f93fe41Ed3fd83779Fb3Aff8A4)   | PancakeSwap 268 | BNB           |
| 24        | [stkBNB/DOTv2](https://bscscan.com/address/0x53073f685474341cdc765F97E7CFB2F427BD9db9)   | PancakeSwap 255 | BNB           |
| 25        | [stkBNB/ADAv2](https://bscscan.com/address/0xf5aFfe3459813AB193329E53f17098806709046A)   | PancakeSwap 253 | BNB           |
| 26        | [stkBUSD/USTv2](https://bscscan.com/address/0x5141da4ab5b3e13ceE7B10980aE6bB848FdB59Cd)  | PancakeSwap 293 | BUSD          |
| 27        | [stkBUSD/DAIv2](https://bscscan.com/address/0x691e486b5F7E39e90d37485164fAbDDd93aE43cD)  | PancakeSwap 282 | BUSD          |
| 28        | [stkBUSD/USDCv2](https://bscscan.com/address/0xae35A19F1DAc62AD3794773D5f0983f05073D0f2) | PancakeSwap 283 | BUSD          |
| 29        | [BNB/WHEATv2](https://bscscan.com/address/0xD58F6FC430BFd33e07566541D91b80143d1D3BB5)    | -               | -             |
| 30        | [BNB/GROv2](https://bscscan.com/address/0x2e9AC5cFCD34E98d5edD9b31A48922f8c664b673)      | -               | -             |
| 31        | [GRO/gROOTv2](https://bscscan.com/address/0x6Fc18618a58e2A5ff0877E0561B8724d135DFC00)    | -               | -             |
| 32        | [BNB/gROOTv2](https://bscscan.com/address/0x0d5B76B7120736000D20A5E33bFF2185DCA79e9a)    | -               | -             |
| 33        | [stkBNB/CAKEv2](https://bscscan.com/address/0x86c15Efe94320Cd139eA4875b7ceF336e1F91f16)  | AutoFarm 243    | BNB           |
| 34        | [stkBNB/BUSDv2](https://bscscan.com/address/0xd5ffd8318b1c82FDE321f7BC1a553462A13A2E14)  | AutoFarm 244    | BNB           |
| 35        | [stkBNB/USDTv2](https://bscscan.com/address/0x7259CeBc6D8f84afdce4B81a3a33D53A526521F8)  | AutoFarm 245    | BNB           |
| 36        | [stkBNB/BTCBv2](https://bscscan.com/address/0x074fD0f3289cF3F5E0E80c969F62B21cB38Ad3b5)  | AutoFarm 246    | BNB           |
| 37        | [stkBNB/ETHv2](https://bscscan.com/address/0x15B310c8D9d0Ac9aefB94BF492e7eAbC43B4f93e)   | AutoFarm 247    | BNB           |
| 38        | [stkBUSD/USDTv2](https://bscscan.com/address/0x6f1c4303bC40AEee0aa60dD90e4eeC353487b66f) | AutoFarm 248    | BUSD          |
| 39        | [stkBUSD/VAIv2](https://bscscan.com/address/0xC8daDd57BD9342b7ba9449B952DBE11B4f3D1648)  | AutoFarm 249    | BUSD          |
| 40        | [stkBNB/DOTv2](https://bscscan.com/address/0x5C96941B28B824c3E9d01E5cb2D77B3f7801560e)   | AutoFarm 250    | BNB           |
| 41        | [stkBNB/LINKv2](https://bscscan.com/address/0x501382584a3DBF1471918Cd4ee0fd3bE23FfDF29)  | AutoFarm 251    | BNB           |
| 42        | [stkBNB/UNIv2](https://bscscan.com/address/0x0900a05910E7d4811f9FC17843120D6412df2968)   | AutoFarm 252    | BNB           |
| 43        | [stkBNB/DODOv2](https://bscscan.com/address/0x67A4c8d130ED95fFaB9F2CDf001811Ada1077875)  | AutoFarm 253    | BNB           |
| 44        | [stkBNB/ALPHAv2](https://bscscan.com/address/0x6C6d105066462EE9b5Cfc7628e2edB1000e887F1) | AutoFarm 256    | BNB           |
| 45        | [stkBNB/ADAv2](https://bscscan.com/address/0x73099318dfBB1C59e473322F29C215132A14Ab86)   | AutoFarm 258    | BNB           |
| 46        | [stkBUSD/USTv2](https://bscscan.com/address/0xB2b5dba919Da2E06d6cDd15dF17bA4b99D3eB1bD)  | AutoFarm 265    | BUSD          |
| 47        | [stkBUSD/BTCBv2](https://bscscan.com/address/0xf30D01da4257c696e537E2fdF0a2Ce6C9D627352) | AutoFarm 354    | BUSD          |

[comment]: # Pending publication after PancakeSwap V2 migration:

[comment]: # | WHEAT pid | Token                                                                                    | CAKE pid | Routing Token |
[comment]: # | ----------| ---------------------------------------------------------------------------------------- | -------- | ------------- |
[comment]: # | -         | stkCAKEv2                                                                                | 0        | CAKE          |

[comment]: # To be published later (CAKE based):

[comment]: # | WHEAT pid | Token                                                                                    | CAKE pid | Routing Token |
[comment]: # | ----------| ---------------------------------------------------------------------------------------- | -------- | ------------- |
[comment]: # | -         | stkBTCB/bBADGER                                                                          | 332      | BTCB          |
[comment]: # | -         | stkBNB/BSCX                                                                              | 281      | BNB           |
[comment]: # | -         | stkBNB/BRY                                                                               | 303      | BNB           |
[comment]: # | -         | stkBNB/WATCH                                                                             | 312      | BNB           |
[comment]: # | -         | stkBNB/BTCST                                                                             | 285      | BNB           |
[comment]: # | -         | stkBUSD/IOTX                                                                             | 309      | BUSD          |
[comment]: # | -         | stkBUSD/TPT                                                                              | 313      | BUSD          |
[comment]: # | -         | stkBNB/ZIL                                                                               | 334      | BNB           |
[comment]: # | -         | stkBNB/TWT                                                                               | 259      | BNB           |
[comment]: # | -         | stkBNB/bOPEN                                                                             | 307      | BNB           |

[comment]: # To be published later (AUTO based):

[comment]: # | WHEAT pid | Token                                                                                    | AUTO pid | Routing Token |
[comment]: # | ----------| ---------------------------------------------------------------------------------------- | -------- | ------------- |
[comment]: # | -         | [stkBNB/AUTOv1](https://bscscan.com/address/0x30cD3DF94b0FA799F946efB3CcB9E9902069aAEB)  | 6        | AUTO          |
[comment]: # | -         | [stkbeltBNB](https://bscscan.com/address/0x0000000000000000000000000000000000000000)     | 338      | BNB           |
[comment]: # | -         | [stkbeltBTC](https://bscscan.com/address/0x0000000000000000000000000000000000000000)     | 339      | BTC           |
[comment]: # | -         | [stkbeltETH](https://bscscan.com/address/0x0000000000000000000000000000000000000000)     | 340      | ETH           |
[comment]: # | -         | [stk4Belt](https://bscscan.com/address/0x0000000000000000000000000000000000000000)       | 341      | ?             |

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
