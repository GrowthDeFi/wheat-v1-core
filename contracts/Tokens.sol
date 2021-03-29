// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { RewardCompoundingStrategyToken } from "./RewardCompoundingStrategyToken.sol";

import { $ } from "./network/$.sol";

contract stkBNB_CAKE is RewardCompoundingStrategyToken
{
	constructor (address _dev, address _treasury, address _collector)
		RewardCompoundingStrategyToken("stake BNB/CAKE", "stkBNB/CAKE", 18, $.PancakeSwap_MASTERCHEF, 1, $.CAKE, _dev, _treasury, _collector) public
	{
	}
}

contract stkBNB_BUSD is RewardCompoundingStrategyToken
{
	constructor (address _dev, address _treasury, address _collector)
		RewardCompoundingStrategyToken("stake BNB/BUSD", "stkBNB/BUSD", 18, $.PancakeSwap_MASTERCHEF, 2, $.WBNB, _dev, _treasury, _collector) public
	{
	}
}
