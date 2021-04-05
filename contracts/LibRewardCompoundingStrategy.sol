// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { Exchange } from "./Exchange.sol";

import { Transfers } from "./modules/Transfers.sol";
import { UniswapV2LiquidityPoolAbstraction } from "./modules/UniswapV2LiquidityPoolAbstraction.sol";

import { MasterChef } from "./interop/MasterChef.sol";
import { Pair } from "./interop/UniswapV2.sol";

library LibRewardCompoundingStrategy
{
	using SafeMath for uint256;
	using LibRewardCompoundingStrategy for LibRewardCompoundingStrategy.Self;

	struct Self {
		address masterChef;
		uint256 pid;

		address reserveToken;
		address routingToken;
		address rewardToken;

		address exchange;
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

	function setExchange(Self storage _self, address _exchange) public
	{
		_self._setExchange(_exchange);
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

	function _setExchange(Self storage _self, address _exchange) internal
	{
		_self.exchange = _exchange;
	}
}
