// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { MintableToken } from "./MintableToken.sol";
import { MintableStakeToken } from "./MintableStakeToken.sol";
import { InterestBearingStrategyToken } from "./InterestBearingStrategyToken.sol";

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

contract stkBNB is InterestBearingStrategyToken
{
	constructor (address _dev, address _treasury, address _buyback)
		InterestBearingStrategyToken("staked BNB", "stkBNB", 18, $.WBNB, $.ibBNB, _dev, _treasury, _buyback) public
	{
	}
}
