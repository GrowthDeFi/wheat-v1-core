// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { Transfers } from "../contracts/modules/Transfers.sol";
import { Wrapping } from "../contracts/modules/Wrapping.sol";

import { Router02 } from "../contracts/interop/UniswapV2.sol";

import { $ } from "../contracts/network/$.sol";

contract Env
{
	using SafeMath for uint256;

	uint256 public initialBalance = 10 ether;

	receive() external payable {}

	function _getBalance(address _token) internal view returns (uint256 _amount)
	{
		return Transfers._getBalance(_token);
	}

	function _mint(address _token, uint256 _amount) internal
	{
		address _router = $.UniswapV2_Compatible_ROUTER02;
		address _TOKEN = Router02(_router).WETH();
		if (_token == _TOKEN) {
			Wrapping._wrap(_token, _amount);
		} else {
			address _this = address(this);
			uint256 _value = _this.balance;
			uint256 _deadline = uint256(-1);
			address[] memory _path = new address[](2);
			_path[0] = _TOKEN;
			_path[1] = _token;
			Router02(_router).swapETHForExactTokens{value: _value}(_amount, _path, _this, _deadline);
		}
	}

	function _burnAll(address _token) internal
	{
		_burn(_token, _getBalance(_token));
	}

	function _burn(address _token, uint256 _amount) internal
	{
		address _from = msg.sender;
		Transfers._pushFunds(_token, _from, _amount);
	}
}
