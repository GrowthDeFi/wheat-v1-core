// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/EnumerableSet.sol";

abstract contract WhitelistGuard is Ownable
{
	using EnumerableSet for EnumerableSet.AddressSet;

	EnumerableSet.AddressSet private whitelist;

	modifier onlyEOAorWhitelist()
	{
		address _from = _msgSender();
		require(tx.origin == _from || whitelist.contains(_from), "access denied");
		_;
	}

	modifier onlyWhitelist()
	{
		address _from = _msgSender();
		require(whitelist.contains(_from), "access denied");
		_;
	}

	function addToWhitelist(address _address) external onlyOwner
	{
		require(whitelist.add(_address), "already listed");
	}

	function removeFromWhitelist(address _address) external onlyOwner
	{
		require(whitelist.remove(_address), "not listed");
	}
}
