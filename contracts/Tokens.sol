// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { MintableToken } from "./MintableToken.sol";
import { MintableStakeToken } from "./MintableStakeToken.sol";
import { RewardCompoundingStrategyToken } from "./RewardCompoundingStrategyToken.sol";

import { $ } from "./network/$.sol";

contract WHEAT is MintableToken
{
	constructor ()
		MintableToken("Wheat Token", "WHEAT", 18) public
	{
	}
}

contract stkWHEAT is MintableStakeToken
{
	constructor (address _WHEAT)
		MintableStakeToken("staked WHEAT", "stkWHEAT", 18, _WHEAT) public
	{
	}
}

contract stkBNB_CAKE is RewardCompoundingStrategyToken
{
	constructor (address _dev, address _treasury, address _collector)
		RewardCompoundingStrategyToken("staked BNB/CAKE", "stkBNB/CAKE", 18, $.PancakeSwap_MASTERCHEF, 1, $.CAKE, _dev, _treasury, _collector) public
	{
	}
}

contract stkBNB_BUSD is RewardCompoundingStrategyToken
{
	constructor (address _dev, address _treasury, address _collector)
		RewardCompoundingStrategyToken("staked BNB/BUSD", "stkBNB/BUSD", 18, $.PancakeSwap_MASTERCHEF, 2, $.WBNB, _dev, _treasury, _collector) public
	{
	}
}
