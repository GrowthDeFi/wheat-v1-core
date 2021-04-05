// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { IStrategyToken } from "./IStrategyToken.sol";

import { Transfers } from "./modules/Transfers.sol";

library LibPerformanceFee
{
	using SafeMath for uint256;
	using LibPerformanceFee for LibPerformanceFee.Self;

	uint256 constant MAXIMUM_PERFORMANCE_FEE = 50e16; // 50%
	uint256 constant DEFAULT_PERFORMANCE_FEE = 20e16; // 20%

	struct Self {
		address reserveToken;

		uint256 performanceFee;

		uint256 lastTotalSupply;
		uint256 lastTotalReserve;
	}

	function init(Self storage _self, address _reserveToken) public
	{
		_self._init(_reserveToken);
	}

	function setPerformanceFee(Self storage _self, uint256 _newPerformanceFee) public
	{
		_self._setPerformanceFee(_newPerformanceFee);
	}

	function calcPerformanceFee(Self storage _self) public view returns (uint256 _feeAmount)
	{
		return _self._calcPerformanceFee();
	}

	function gulpPerformanceFee(Self storage _self, address _to) public
	{
		_self._gulpPerformanceFee(_to);
	}

	function _init(Self storage _self, address _reserveToken) internal
	{
		_self.reserveToken = _reserveToken;

		_self.performanceFee = DEFAULT_PERFORMANCE_FEE;

		_self.lastTotalSupply = 1;
		_self.lastTotalReserve = 1;
	}

	function _setPerformanceFee(Self storage _self, uint256 _newPerformanceFee) internal
	{
		require(_newPerformanceFee <= MAXIMUM_PERFORMANCE_FEE, "invalid rate");
		_self.performanceFee = _newPerformanceFee;
	}

	function _calcPerformanceFee(Self storage _self) internal view returns (uint256 _feeAmount)
	{
		uint256 _oldTotalSupply = _self.lastTotalSupply;
		uint256 _oldTotalReserve = _self.lastTotalReserve;

		uint256 _newTotalSupply = IStrategyToken(address(this)).totalSupply();
		uint256 _newTotalReserve = IStrategyToken(address(this)).totalReserve();

		// calculates the profit using the following formula
		// ((P1 - P0) * S1 * f) / P1
		// where P1 = R1 / S1 and P0 = R0 / S0
		uint256 _positive = _oldTotalSupply.mul(_newTotalReserve);
		uint256 _negative = _newTotalSupply.mul(_oldTotalReserve);
		if (_positive > _negative) {
			uint256 _profitAmount = (_positive - _negative) / _oldTotalSupply;
			return _profitAmount.mul(_self.performanceFee) / 1e18;
		}

		return 0;
	}

	function _gulpPerformanceFee(Self storage _self, address _to) internal
	{
		uint256 _feeAmount = _self._calcPerformanceFee();
		if (_feeAmount > 0) {
			Transfers._pushFunds(_self.reserveToken, _to, _feeAmount);
			_self.lastTotalSupply = IStrategyToken(address(this)).totalSupply();
			_self.lastTotalReserve = IStrategyToken(address(this)).totalReserve();
		}
	}
}
