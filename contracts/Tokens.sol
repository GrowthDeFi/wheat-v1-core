// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { MintableToken } from "./MintableToken.sol";
import { MintableStakeToken } from "./MintableStakeToken.sol";

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
