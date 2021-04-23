// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IExchange } from "./IExchange.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";

import { Transfers } from "./modules/Transfers.sol";

import { AutoFarmV2 } from "./interop/AutoFarmV2.sol";
import { Pair } from "./interop/UniswapV2.sol";

contract AutoFarmCompoundingStrategyToken is ERC20, ReentrancyGuard, WhitelistGuard
{
	using SafeMath for uint256;
	using LibAutoFarmCompoundingStrategy for LibAutoFarmCompoundingStrategy.Self;

	address public treasury;
	address public collector;

	LibAutoFarmCompoundingStrategy.Self lib;

	constructor (string memory _name, string memory _symbol, uint8 _decimals,
		address _autoFarm, uint256 _pid, address _routingToken,
		address _treasury, address _collector)
		ERC20(_name, _symbol) public
	{
		_setupDecimals(_decimals);
		lib.init(_autoFarm, _pid, _routingToken);
		treasury = _treasury;
		collector = _collector;
		_mint(address(1), 1); // avoids division by zero
	}

	function reserveToken() external view returns (address _reserveToken)
	{
		return lib.reserveToken;
	}

	function routingToken() external view returns (address _routingToken)
	{
		return lib.routingToken;
	}

	function rewardToken() external view returns (address _rewardToken)
	{
		return lib.rewardToken;
	}

	function exchange() external view returns (address _exchange)
	{
		return lib.exchange;
	}

	function performanceFee() external view returns (uint256 _performanceFee)
	{
		return lib.performanceFee;
	}

	function totalReserve() public view returns (uint256 _totalReserve)
	{
		_totalReserve = lib.totalReserve();
		if (_totalReserve == uint256(-1)) return _totalReserve;
		return _totalReserve + 1; // avoids division by zero
	}

	function calcSharesFromAmount(uint256 _amount) public view returns (uint256 _shares)
	{
		return _amount.mul(totalSupply()) / totalReserve();
	}

	function calcAmountFromShares(uint256 _shares) public view returns (uint256 _amount)
	{
		return _shares.mul(totalReserve()) / totalSupply();
	}

	function pendingReward() external view returns (uint256 _rewardAmount)
	{
		return lib.calcPendingReward();
	}

	function pendingPerformanceFee() external view returns (uint256 _feeReward)
	{
		return lib.calcPerformanceFee();
	}

	function deposit(uint256 _amount) external onlyEOAorWhitelist nonReentrant
	{
		address _from = msg.sender;
		uint256 _shares = calcSharesFromAmount(_amount);
		Transfers._pullFunds(lib.reserveToken, _from, _amount);
		lib.deposit(_amount);
		_mint(_from, _shares);
	}

	function withdraw(uint256 _shares) external onlyEOAorWhitelist nonReentrant
	{
		address _from = msg.sender;
		uint256 _amount = calcAmountFromShares(_shares);
		_burn(_from, _shares);
		lib.withdraw(_amount);
		Transfers._pushFunds(lib.reserveToken, _from, _amount);
	}

	function gulp() external onlyEOAorWhitelist nonReentrant
	{
		lib.gulpPerformanceFee(collector);
		lib.gulpPendingReward();
	}

	function recoverLostFunds(address _token) external onlyOwner nonReentrant
	{
		require(_token != lib.reserveToken, "invalid token");
		require(_token != lib.routingToken, "invalid token");
		require(_token != lib.rewardToken, "invalid token");
		uint256 _balance = Transfers._getBalance(_token);
		Transfers._pushFunds(_token, treasury, _balance);
	}

	function setTreasury(address _newTreasury) external onlyOwner nonReentrant
	{
		require(_newTreasury != address(0), "invalid address");
		address _oldTreasury = treasury;
		treasury = _newTreasury;
		emit ChangeTreasury(_oldTreasury, _newTreasury);
	}

	function setCollector(address _newCollector) external onlyOwner nonReentrant
	{
		require(_newCollector != address(0), "invalid address");
		address _oldCollector = collector;
		collector = _newCollector;
		emit ChangeCollector(_oldCollector, _newCollector);
	}

	function setExchange(address _newExchange) external onlyOwner nonReentrant
	{
		address _oldExchange = lib.exchange;
		lib.setExchange(_newExchange);
		emit ChangeExchange(_oldExchange, _newExchange);
	}

	function setPerformanceFee(uint256 _newPerformanceFee) external onlyOwner nonReentrant
	{
		uint256 _oldPerformanceFee = lib.performanceFee;
		lib.setPerformanceFee(_newPerformanceFee);
		emit ChangePerformanceFee(_oldPerformanceFee, _newPerformanceFee);
	}

	event ChangeExchange(address _oldExchange, address _newExchange);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeCollector(address _oldCollector, address _newCollector);
	event ChangePerformanceFee(uint256 _oldPerformanceFee, uint256 _newPerformanceFee);
}

library LibAutoFarmCompoundingStrategy
{
	using SafeMath for uint256;
	using LibAutoFarmCompoundingStrategy for LibAutoFarmCompoundingStrategy.Self;

	uint256 constant MAXIMUM_PERFORMANCE_FEE = 50e16; // 50%
	uint256 constant DEFAULT_PERFORMANCE_FEE = 20e16; // 20%

	struct Self {
		address autoFarm;
		uint256 pid;

		address reserveToken;
		address routingToken;
		address rewardToken;

		address exchange;

		uint256 performanceFee;
	}

	function init(Self storage _self, address _autoFarm, uint256 _pid, address _routingToken) public
	{
		_self._init(_autoFarm, _pid, _routingToken);
	}

	function totalReserve(Self storage _self) public view returns (uint256 _totalReserve)
	{
		return _self._totalReserve();
	}

	function calcPendingReward(Self storage _self) public view returns (uint256 _rewardAmount)
	{
		return _self._calcPendingReward();
	}

	function calcPerformanceFee(Self storage _self) public view returns (uint256 _feeReward)
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

	function gulpPendingReward(Self storage _self) public
	{
		_self._gulpPendingReward();
	}

	function gulpPerformanceFee(Self storage _self, address _to) public
	{
		_self._gulpPerformanceFee(_to);
	}

	function setExchange(Self storage _self, address _exchange) public
	{
		_self._setExchange(_exchange);
	}

	function setPerformanceFee(Self storage _self, uint256 _newPerformanceFee) public
	{
		_self._setPerformanceFee(_newPerformanceFee);
	}

	function _init(Self storage _self, address _autoFarm, uint256 _pid, address _routingToken) internal
	{
		uint256 _poolLength = AutoFarmV2(_autoFarm).poolLength();
		require(_pid < _poolLength, "invalid pid");
		(address _reserveToken,,,,) = AutoFarmV2(_autoFarm).poolInfo(_pid);
		require(_routingToken == _reserveToken || _routingToken == Pair(_reserveToken).token0() || _routingToken == Pair(_reserveToken).token1(), "invalid token");
		address _rewardToken = AutoFarmV2(_autoFarm).AUTOv2();
		_self.autoFarm = _autoFarm;
		_self.pid = _pid;
		_self.reserveToken = _reserveToken;
		_self.routingToken = _routingToken;
		_self.rewardToken = _rewardToken;
		_self.performanceFee = DEFAULT_PERFORMANCE_FEE;
	}

	function _totalReserve(Self storage _self) internal view returns (uint256 _reserve)
	{
		return AutoFarmV2(_self.autoFarm).stakedWantTokens(_self.pid, address(this));
	}

	function _calcPendingReward(Self storage _self) internal view returns (uint256 _rewardAmount)
	{
		require(_self.exchange != address(0), "exchange not set");
		uint256 _collectedReward = Transfers._getBalance(_self.rewardToken);
		uint256 _pendingReward = AutoFarmV2(_self.autoFarm).pendingAUTO(_self.pid, address(this));
		uint256 _totalReward = _collectedReward.add(_pendingReward);
		uint256 _feeReward = _totalReward.mul(_self.performanceFee) / 1e18;
		uint256 _netReward = _totalReward - _feeReward;
		uint256 _totalConverted = _netReward;
		if (_self.routingToken != _self.rewardToken) {
			_totalConverted = IExchange(_self.exchange).calcConversionFromInput(_self.rewardToken, _self.routingToken, _netReward);
		}
		uint256 _totalJoined = _totalConverted;
		if (_self.reserveToken != _self.routingToken) {
			_totalJoined = IExchange(_self.exchange).calcJoinPoolFromInput(_self.reserveToken, _self.routingToken, _totalConverted);
		}
		return _totalJoined;
	}

	function _calcPerformanceFee(Self storage _self) internal view returns (uint256 _feeReward)
	{
		uint256 _collectedReward = Transfers._getBalance(_self.rewardToken);
		uint256 _pendingReward = AutoFarmV2(_self.autoFarm).pendingAUTO(_self.pid, address(this));
		uint256 _totalReward = _collectedReward.add(_pendingReward);
		return _totalReward.mul(_self.performanceFee) / 1e18;
	}

	function _deposit(Self storage _self, uint256 _amount) internal
	{
		Transfers._approveFunds(_self.reserveToken, _self.autoFarm, _amount);
		AutoFarmV2(_self.autoFarm).deposit(_self.pid, _amount);
	}

	function _withdraw(Self storage _self, uint256 _amount) internal
	{
		AutoFarmV2(_self.autoFarm).withdraw(_self.pid, _amount);
	}

	function _gulpPendingReward(Self storage _self) internal
	{
		require(_self.exchange != address(0), "exchange not set");
		if (_self.routingToken != _self.rewardToken) {
			uint256 _totalReward = Transfers._getBalance(_self.rewardToken);
			Transfers._approveFunds(_self.rewardToken, _self.exchange, _totalReward);
			IExchange(_self.exchange).convertFundsFromInput(_self.rewardToken, _self.routingToken, _totalReward, 1);
		}
		if (_self.reserveToken != _self.routingToken) {
			uint256 _totalConverted = Transfers._getBalance(_self.routingToken);
			Transfers._approveFunds(_self.routingToken, _self.exchange, _totalConverted);
			IExchange(_self.exchange).joinPoolFromInput(_self.reserveToken, _self.routingToken, _totalConverted, 1);
		}
		uint256 _totalJoined = Transfers._getBalance(_self.reserveToken);
		_self._deposit(_totalJoined);
	}

	// must be called prior to _gulpPendingReward
	function _gulpPerformanceFee(Self storage _self, address _to) internal
	{
		uint256 _pendingReward = AutoFarmV2(_self.autoFarm).pendingAUTO(_self.pid, address(this));
		if (_pendingReward > 0) {
			_self._withdraw(0);
		}
		uint256 _totalReward = Transfers._getBalance(_self.rewardToken);
		uint256 _feeReward = _totalReward.mul(_self.performanceFee) / 1e18;
		Transfers._pushFunds(_self.rewardToken, _to, _feeReward);
	}

	function _setExchange(Self storage _self, address _exchange) internal
	{
		_self.exchange = _exchange;
	}

	function _setPerformanceFee(Self storage _self, uint256 _newPerformanceFee) internal
	{
		require(_newPerformanceFee <= MAXIMUM_PERFORMANCE_FEE, "invalid rate");
		_self.performanceFee = _newPerformanceFee;
	}
}
