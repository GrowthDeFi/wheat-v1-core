// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Transfers } from "./modules/Transfers.sol";
import { Wrapping } from "./modules/Wrapping.sol";

interface IStrategy
{
	function reserveToken() external view returns (address _reserveToken);

	function deposit(uint256 _amount) external;
	function withdraw(uint256 _shares) external;
}

contract NativeBridge
{
	address public immutable nativeToken;

	constructor (address _nativeToken) public
	{
		nativeToken = _nativeToken;
	}

	function deposit(address _strategyToken) public payable
	{
		address _from = msg.sender;
		uint256 _amount = msg.value;
		address _reserveToken = IStrategy(_strategyToken).reserveToken();
		require(_reserveToken == nativeToken, "unsupported operation");
		Wrapping._wrap(_reserveToken, _amount);
		Transfers._approveFunds(_reserveToken, _strategyToken, _amount);
		IStrategy(_strategyToken).deposit(_amount);
		uint256 _shares = Transfers._getBalance(_strategyToken);
		Transfers._pushFunds(_strategyToken, _from, _shares);
	}

	function withdraw(address _strategyToken, uint256 _shares) public
	{
		address payable _from = msg.sender;
		address _reserveToken = IStrategy(_strategyToken).reserveToken();
		require(_reserveToken == nativeToken, "unsupported operation");
		Transfers._pullFunds(_strategyToken, _from, _shares);
		IStrategy(_strategyToken).withdraw(_shares);
		uint256 _amount = Transfers._getBalance(_reserveToken);
		Wrapping._unwrap(_reserveToken, _amount);
		_from.transfer(_amount);
	}

	receive() external payable
	{
		require(msg.sender == nativeToken, "not allowed"); // not to be used directly
	}
}
