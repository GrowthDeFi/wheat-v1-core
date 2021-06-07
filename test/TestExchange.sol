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
		_testConvertFundsFromInput($.AUTO, $.CAKE, 1e17); // 0.1 AUTO
	}

	function test02() external
	{
		_testConvertFundsFromInput($.PANTHER, $.CAKE, 100e18); // 100 PANTHER
	}

	function test03() external
	{
		_testConvertFundsFromInput($.CAKE, $.GRO, 20e18); // 20 CAKE
	}

	function test04() external
	{
		_testConvertFundsFromInput($.CAKE, $.WHEAT, 20e18); // 20 CAKE
	}

	function test05() external
	{
		_testConvertFundsFromOutput($.AUTO, $.CAKE, 10e18); // 10 CAKE
	}

	function test06() external
	{
		_testConvertFundsFromOutput($.CAKE, $.GRO, 10e18); // 10 GRO
	}

	function test07() external
	{
		_testConvertFundsFromOutput($.CAKE, $.WHEAT, 50e18); // 50 WHEAT
	}

	function _testConvertFundsFromInput(address _from, address _to, uint256 _inputAmount) internal
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

	function _testConvertFundsFromOutput(address _from, address _to, uint256 _outputAmount) internal
	{
		_burnAll(_from);
		_burnAll(_to);

		address _exchange = EXCHANGE;

		uint256 SLIPPAGE = 1e15; // 0.1%

		uint256 _expectedInputAmount =  Exchange(_exchange).calcConversionFromOutput(_from, _to, _outputAmount);
		uint256 _maxInputAmount = _expectedInputAmount.mul(1e18 + SLIPPAGE).div(1e18);

		_mint(_from, _maxInputAmount);

		Assert.equal(Transfers._getBalance(_from), _maxInputAmount, "Balance before must match max input");
		Assert.equal(Transfers._getBalance(_to), 0e18, "Balance before must be 0e18");

		Transfers._approveFunds(_from, _exchange, _maxInputAmount);
		uint256 _inputAmount = Exchange(_exchange).convertFundsFromOutput(_from, _to, _outputAmount, _maxInputAmount);

		Assert.equal(Transfers._getBalance(_from), _maxInputAmount - _inputAmount, "Balance after must be the difference");
		Assert.equal(Transfers._getBalance(_to), _outputAmount, "Balance after must match output");
	}
}
