// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { MintableToken } from "./MintableToken.sol";

import { Math } from "./modules/Math.sol";
import { Transfers } from "./modules/Transfers.sol";

contract MintableStakeToken is MintableToken
{
	address public immutable cake;

	constructor (string memory _name, string memory _symbol, uint8 _decimals, address _cake)
		MintableToken(_name, _symbol, _decimals) public
	{
		cake = _cake;
	}

	function safeCakeTransfer(address _to, uint256 _amount) external onlyOwner
	{
		uint256 _balance = Transfers._getBalance(cake);
		Transfers._pushFunds(cake, _to, Math._min(_amount, _balance));
	}
}
