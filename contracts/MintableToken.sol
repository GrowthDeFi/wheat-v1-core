// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MintableToken is ERC20, Ownable
{
	constructor (string memory _name, string memory _symbol, uint8 _decimals)
		ERC20(_name, _symbol) public
	{
		_setupDecimals(_decimals);
	}

	function mint(address _to, uint256 _amount) external onlyOwner
	{
		_mint(_to, _amount);
	}

	function burn(address _from ,uint256 _amount) external onlyOwner
	{
		_burn(_from, _amount);
	}
}
