// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Assert } from "truffle/Assert.sol";

import { Env } from "./Env.sol";

import { Exchange } from "../contracts/Exchange.sol";

import { Transfers } from "../contracts/modules/Transfers.sol";

import { $ } from "../contracts/network/$.sol";

contract TestExchange is Env
{
	function test01() external
	{
		_testFromInput($.AUTO, $.CAKE, 1e17); // 0.1 AUTO
	}

	function test02() external
	{
		_testFromInput($.PANTHER, $.CAKE, 100e18); // 100 PANTHER
	}

	function test03() external
	{
		_testFromInput($.CAKE, $.GRO, 20e18); // 20 CAKE
	}

	function test04() external
	{
		_testFromInput($.CAKE, $.WHEAT, 20e18); // 20 CAKE
	}

	function _testFromInput(address _from, address _to, uint256 _inputAmount) internal
	{
		_burnAll(_from);
		_burnAll(_to);

		_mint(_from, _inputAmount);

		address _exchange = EXCHANGE;

		uint256 SLIPPAGE = 1e15; // 0.1%

		if (_from == $.PANTHER) { // workaround the transfer tax
			_inputAmount = Transfers._getBalance(_from);
			SLIPPAGE = 5e16; // 5%
		}

		uint256 _expectedOutputAmount =  Exchange(_exchange).calcConversionFromInput(_from, _to, _inputAmount);
		uint256 _minOutputAmount = _expectedOutputAmount.mul(1e18 - SLIPPAGE).div(1e18);

		Assert.equal(Transfers._getBalance(_from), _inputAmount, "Balance before must match input");
		Assert.equal(Transfers._getBalance(_to), 0e18, "Balance before must be 0e18");

		Transfers._approveFunds(_from, _exchange, _inputAmount);
		uint256 _outputAmount = Exchange(_exchange).convertFundsFromInput(_from, _to, _inputAmount, _minOutputAmount);

		Assert.equal(Transfers._getBalance(_from), 0e18, "Balance after must be 0e18");
		Assert.equal(Transfers._getBalance(_to), _outputAmount, "Balance after must match output");
	}
}
