// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { Exchange } from "./Exchange.sol";
import { IStrategyToken } from "./IStrategyToken.sol";

import { Transfers } from "./modules/Transfers.sol";
import { UniswapV2LiquidityPoolAbstraction } from "./modules/UniswapV2LiquidityPoolAbstraction.sol";

import { MasterChef } from "./interop/MasterChef.sol";
import { Pair } from "./interop/UniswapV2.sol";

library LibRewardCompoundingStrategy
{
	using SafeMath for uint256;
	using LibRewardCompoundingStrategy for LibRewardCompoundingStrategy.Self;

	uint256 constant MAXIMUM_DEPOSIT_FEE = 5e16; // 5%
	uint256 constant DEFAULT_DEPOSIT_FEE = 3e16; // 3%

	uint256 constant MAXIMUM_PERFORMANCE_FEE = 50e16; // 50%
	uint256 constant DEFAULT_PERFORMANCE_FEE = 20e16; // 20%

	struct Self {
		address masterChef;
		uint256 pid;

		address reserveToken;
		address routingToken;
		address rewardToken;

		address exchange;

		uint256 depositFee;
		uint256 performanceFee;

		uint256 lastTotalSupply;
		uint256 lastTotalReserve;
	}

	function init(Self storage _self, address _masterChef, uint256 _pid, address _routingToken) public
	{
		_self._init(_masterChef, _pid, _routingToken);
	}

	function totalReserve(Self storage _self) public view returns (uint256 _totalReserve)
	{
		return _self._totalReserve();
	}

	function calcReward(Self storage _self) public view returns (uint256 _rewardAmount)
	{
		return _self._calcReward();
	}

	function calcPerformanceFee(Self storage _self) public view returns (uint256 _feeAmount)
	{
		return _self._calcPerformanceFee();
	}

	function deposit(Self storage _self, uint256 _amount) public
	{
		_self._deposit(_amount);
	}

	function withdraw(Self storage _self, uint256 _amount) public
	{
		_self._withdraw(_amount);
	}

	function gulpReward(Self storage _self) public
	{
		_self._gulpReward();
	}

	function gulpPerformanceFee(Self storage _self, address _to) public
	{
		_self._gulpPerformanceFee(_to);
	}

	function setExchange(Self storage _self, address _exchange) public
	{
		_self._setExchange(_exchange);
	}

	function setDepositFee(Self storage _self, uint256 _newDepositFee) public
	{
		_self._setDepositFee(_newDepositFee);
	}

	function setPerformanceFee(Self storage _self, uint256 _newPerformanceFee) public
	{
		_self._setPerformanceFee(_newPerformanceFee);
	}

	function _init(Self storage _self, address _masterChef, uint256 _pid, address _routingToken) internal
	{
		uint256 _poolLength = MasterChef(_masterChef).poolLength();
		require(1 <= _pid && _pid < _poolLength, "invalid pid");
		(address _reserveToken,,,) = MasterChef(_masterChef).poolInfo(_pid);
		require(_routingToken == Pair(_reserveToken).token0() || _routingToken == Pair(_reserveToken).token1(), "invalid token");
		address _rewardToken = MasterChef(_masterChef).cake();
		_self.masterChef = _masterChef;
		_self.pid = _pid;
		_self.reserveToken = _reserveToken;
		_self.routingToken = _routingToken;
		_self.rewardToken = _rewardToken;
		_self.depositFee = DEFAULT_DEPOSIT_FEE;
		_self.performanceFee = DEFAULT_PERFORMANCE_FEE;
		_self.lastTotalSupply = 1;
		_self.lastTotalReserve = 1;
	}

	function _totalReserve(Self storage _self) internal view returns (uint256 _reserve)
	{
		(_reserve,) = MasterChef(_self.masterChef).userInfo(_self.pid, address(this));
		return _reserve;
	}

	function _calcReward(Self storage _self) internal view returns (uint256 _rewardAmount)
	{
		require(_self.exchange != address(0), "exchange not set");
		uint256 _pendingReward = MasterChef(_self.masterChef).pendingCake(_self.pid, address(this));
		uint256 _collectedReward = Transfers._getBalance(_self.rewardToken);
		uint256 _totalReward = _pendingReward.add(_collectedReward);
		uint256 _totalConverted = _totalReward;
		if (_self.routingToken != _self.rewardToken) {
			_totalConverted = Exchange(_self.exchange).calcConversionFromInput(_self.rewardToken, _self.routingToken, _totalReward);
		}
		return UniswapV2LiquidityPoolAbstraction._estimateJoinPool(_self.reserveToken, _self.routingToken, _totalConverted);
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

	function _deposit(Self storage _self, uint256 _amount) internal
	{
		Transfers._approveFunds(_self.reserveToken, _self.masterChef, _amount);
		MasterChef(_self.masterChef).deposit(_self.pid, _amount);
	}

	function _withdraw(Self storage _self, uint256 _amount) internal
	{
		MasterChef(_self.masterChef).withdraw(_self.pid, _amount);
	}

	function _gulpReward(Self storage _self) internal
	{
		require(_self.exchange != address(0), "exchange not set");
		uint256 _pendingReward = MasterChef(_self.masterChef).pendingCake(_self.pid, address(this));
		if (_pendingReward > 0) {
			MasterChef(_self.masterChef).withdraw(_self.pid, 0);
		}
		if (_self.routingToken != _self.rewardToken) {
			uint256 _totalReward = Transfers._getBalance(_self.rewardToken);
			Transfers._approveFunds(_self.rewardToken, _self.exchange, _totalReward);
			Exchange(_self.exchange).convertFundsFromInput(_self.rewardToken, _self.routingToken, _totalReward, 1);
		}
		uint256 _totalConverted = Transfers._getBalance(_self.routingToken);
		uint256 _rewardAmount = UniswapV2LiquidityPoolAbstraction._joinPool(_self.reserveToken, _self.routingToken, _totalConverted);
		_self._deposit(_rewardAmount);
	}

	function _gulpPerformanceFee(Self storage _self, address _to) internal
	{
		uint256 _feeAmount = _self._calcPerformanceFee();
		if (_feeAmount > 0) {
			_self._withdraw(_feeAmount);
			Transfers._pushFunds(_self.reserveToken, _to, _feeAmount);
			_self.lastTotalSupply = IStrategyToken(address(this)).totalSupply();
			_self.lastTotalReserve = IStrategyToken(address(this)).totalReserve();
		}
	}

	function _setExchange(Self storage _self, address _exchange) internal
	{
		_self.exchange = _exchange;
	}

	function _setDepositFee(Self storage _self, uint256 _newDepositFee) internal
	{
		require(_newDepositFee <= MAXIMUM_DEPOSIT_FEE, "invalid rate");
		_self.depositFee = _newDepositFee;
	}

	function _setPerformanceFee(Self storage _self, uint256 _newPerformanceFee) internal
	{
		require(_newPerformanceFee <= MAXIMUM_PERFORMANCE_FEE, "invalid rate");
		_self.performanceFee = _newPerformanceFee;
	}
}
