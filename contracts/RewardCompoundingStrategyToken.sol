// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { Exchange } from "./Exchange.sol";
import { IStrategyToken } from "./IStrategyToken.sol";
import { LibPerformanceFee } from "./LibPerformanceFee.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";

import { Transfers } from "./modules/Transfers.sol";
import { UniswapV2LiquidityPoolAbstraction } from "./modules/UniswapV2LiquidityPoolAbstraction.sol";

import { MasterChef } from "./interop/MasterChef.sol";
import { Pair } from "./interop/UniswapV2.sol";

contract RewardCompoundingStrategyToken is IStrategyToken, ERC20, ReentrancyGuard, WhitelistGuard
{
	using SafeMath for uint256;
	using LibPerformanceFee for LibPerformanceFee.Self;

	uint256 constant MAXIMUM_DEPOSIT_FEE = 5e16; // 5%
	uint256 constant DEFAULT_DEPOSIT_FEE = 3e16; // 3%

	uint256 constant DEPOSIT_FEE_COLLECTOR_SHARE = 833333333333333333; // 5/6
	uint256 constant DEPOSIT_FEE_DEV_SHARE = 166666666666666667; // 1/6

	address private immutable masterChef;
	uint256 private immutable pid;

	address public immutable override reserveToken;
	address public immutable routingToken;
	address public immutable rewardToken;

	address public exchange;

	address public dev;
	address public treasury;
	address public collector;

	uint256 public depositFee = DEFAULT_DEPOSIT_FEE;

	LibPerformanceFee.Self lpf;

	constructor (string memory _name, string memory _symbol, uint8 _decimals,
		address _masterChef, uint256 _pid, address _routingToken,
		address _dev, address _treasury, address _collector)
		ERC20(_name, _symbol) public
	{
		_setupDecimals(_decimals);
		uint256 _poolLength = MasterChef(_masterChef).poolLength();
		require(1 <= _pid && _pid < _poolLength, "invalid pid");
		(address _reserveToken,,,) = MasterChef(_masterChef).poolInfo(_pid);
		require(_routingToken == Pair(_reserveToken).token0() || _routingToken == Pair(_reserveToken).token1(), "invalid token");
		address _rewardToken = MasterChef(_masterChef).cake();
		masterChef = _masterChef;
		pid = _pid;
		reserveToken = _reserveToken;
		routingToken = _routingToken;
		rewardToken = _rewardToken;
		dev = _dev;
		treasury = _treasury;
		collector = _collector;
		_mint(address(1), 1); // avoids division by zero
		lpf.init();
	}

	function totalReserve() public view override returns (uint256 _totalReserve)
	{
		(_totalReserve,) = MasterChef(masterChef).userInfo(pid, address(this));
		if (_totalReserve == uint256(-1)) return _totalReserve;
		return _totalReserve + 1; // avoids division by zero
	}

	function calcSharesFromAmount(uint256 _amount) external view override returns (uint256 _shares)
	{
		(,,,_shares) = _calcSharesFromAmount(_amount);
		return _shares;
	}

	function calcAmountFromShares(uint256 _shares) external view override returns (uint256 _amount)
	{
		(_amount) = _calcAmountFromShares(_shares);
		return _amount;
	}

	function pendingReward() external view returns (uint256 _rewardCost)
	{
		return _calcReward();
	}

	function pendingPerformanceFee() external view returns (uint256 _feeCost)
	{
		return lpf.calcPerformanceFee();
	}

	function deposit(uint256 _amount) external override onlyEOAorWhitelist nonReentrant
	{
		address _from = msg.sender;
		(uint256 _devAmount, uint256 _collectorAmount, uint256 _netAmount, uint256 _shares) = _calcSharesFromAmount(_amount);
		Transfers._pullFunds(reserveToken, _from, _amount);
		Transfers._pushFunds(reserveToken, dev, _devAmount);
		Transfers._pushFunds(reserveToken, collector, _collectorAmount);
		Transfers._approveFunds(reserveToken, masterChef, _netAmount);
		MasterChef(masterChef).deposit(pid, _netAmount);
		_mint(_from, _shares);
	}

	function withdraw(uint256 _shares) external override onlyEOAorWhitelist nonReentrant
	{
		address _from = msg.sender;
		(uint256 _amount) = _calcAmountFromShares(_shares);
		MasterChef(masterChef).withdraw(pid, _amount);
		Transfers._pushFunds(reserveToken, _from, _amount);
		_burn(_from, _shares);
	}

	function gulp() external onlyEOAorWhitelist nonReentrant
	{
		_gulpReward();
		lpf.gulpPerformanceFee(collector);
	}

	function recoverLostFunds(address _token) external onlyOwner nonReentrant
	{
		require(_token != reserveToken, "invalid token");
		require(_token != routingToken, "invalid token");
		require(_token != rewardToken, "invalid token");
		uint256 _balance = Transfers._getBalance(_token);
		Transfers._pushFunds(_token, treasury, _balance);
	}

	function setExchange(address _newExchange) external onlyOwner nonReentrant
	{
		address _oldExchange = exchange;
		exchange = _newExchange;
		emit ChangeExchange(_oldExchange, _newExchange);
	}

	function setDev(address _newDev) external onlyOwner nonReentrant
	{
		require(_newDev != address(0), "invalid address");
		address _oldDev = dev;
		dev = _newDev;
		emit ChangeDev(_oldDev, _newDev);
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

	function setDepositFee(uint256 _newDepositFee) external onlyOwner nonReentrant
	{
		require(_newDepositFee <= MAXIMUM_DEPOSIT_FEE, "invalid rate");
		uint256 _oldDepositFee = depositFee;
		depositFee = _newDepositFee;
		emit ChangeDepositFee(_oldDepositFee, _newDepositFee);
	}

	function setPerformanceFee(uint256 _newPerformanceFee) external onlyOwner nonReentrant
	{
		uint256 _oldPerformanceFee = lpf.performanceFee;
		lpf.setPerformanceFee(_newPerformanceFee);
		emit ChangePerformanceFee(_oldPerformanceFee, _newPerformanceFee);
	}

	function _calcAmountFromShares(uint256 _shares) internal view returns (uint256 _amount)
	{
		return _shares.mul(totalReserve()) / totalSupply();
	}

	function _calcSharesFromAmount(uint256 _amount) internal view returns (uint256 _devAmount, uint256 _collectorAmount, uint256 _netAmount, uint256 _shares)
	{
		uint256 _feeAmount = _amount.mul(depositFee) / 1e18;
		_devAmount = (_feeAmount * DEPOSIT_FEE_DEV_SHARE) / 1e18;
		_collectorAmount = _feeAmount - _devAmount;
		_netAmount = _amount - _feeAmount;
		_shares = _netAmount.mul(totalSupply()) / totalReserve();
		return (_devAmount, _collectorAmount, _netAmount, _shares);
	}

	function _calcReward() internal view returns (uint256 _rewardCost)
	{
		require(exchange != address(0), "exchange not set");
		uint256 _pendingRewardAmount = MasterChef(masterChef).pendingCake(pid, address(this));
		uint256 _collectedRewardAmount = Transfers._getBalance(rewardToken);
		uint256 _rewardAmount = _pendingRewardAmount.add(_collectedRewardAmount);
		uint256 _routingAmount = _rewardAmount;
		if (routingToken != rewardToken) {
			_routingAmount = Exchange(exchange).calcConversionFromInput(rewardToken, routingToken, _rewardAmount);
		}
		return UniswapV2LiquidityPoolAbstraction.estimateJoinPool(reserveToken, routingToken, _routingAmount);
	}

	function _gulpReward() internal
	{
		require(exchange != address(0), "exchange not set");
		uint256 _pendingRewardAmount = MasterChef(masterChef).pendingCake(pid, address(this));
		if (_pendingRewardAmount > 0) {
			MasterChef(masterChef).withdraw(pid, 0);
		}
		if (routingToken != rewardToken) {
			uint256 _rewardAmount = Transfers._getBalance(rewardToken);
			Transfers._approveFunds(rewardToken, exchange, _rewardAmount);
			Exchange(exchange).convertFundsFromInput(rewardToken, routingToken, _rewardAmount, 1);
		}
		uint256 _routingAmount = Transfers._getBalance(routingToken);
		uint256 _rewardCost = UniswapV2LiquidityPoolAbstraction.joinPool(reserveToken, routingToken, _routingAmount);
		Transfers._approveFunds(reserveToken, masterChef, _rewardCost);
		MasterChef(masterChef).deposit(pid, _rewardCost);
	}

	event ChangeExchange(address _oldExchange, address _newExchange);
	event ChangeDev(address _oldDev, address _newDev);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeCollector(address _oldCollector, address _newCollector);
	event ChangeDepositFee(uint256 _oldDepositFee, uint256 _newDepositFee);
	event ChangePerformanceFee(uint256 _oldPerformanceFee, uint256 _newPerformanceFee);
}

library LibRewardCompoundingStrategyToken
{
	using SafeMath for uint256;
	using LibRewardCompoundingStrategyToken for LibRewardCompoundingStrategyToken.Self;

	uint256 constant MAXIMUM_PERFORMANCE_FEE = 50e16; // 50%
	uint256 constant DEFAULT_PERFORMANCE_FEE = 20e16; // 20%

	struct Self {
		address token;

		uint256 performanceFee;

		uint256 lastTotalSupply;
		uint256 lastTotalReserve;
	}

	function init(Self storage _self, address _token) public
	{
		_self.token = _token;

		_self.performanceFee = DEFAULT_PERFORMANCE_FEE;

		_self.lastTotalSupply = 1;
		_self.lastTotalReserve = 1;
	}

	function setPerformanceFee(Self storage _self, uint256 _newPerformanceFee) public
	{
		_self._setPerformanceFee(_newPerformanceFee);
	}

	function calcPerformanceFee(Self storage _self) public view returns (uint256 _feeCost)
	{
		return _self._calcPerformanceFee();
	}

	function gulpPerformanceFee(Self storage _self) public
	{
		_self._gulpPerformanceFee();
	}

	function _setPerformanceFee(Self storage _self, uint256 _newPerformanceFee) internal
	{
		require(_newPerformanceFee <= MAXIMUM_PERFORMANCE_FEE, "invalid rate");
		_self.performanceFee = _newPerformanceFee;
	}

	function _calcPerformanceFee(Self storage _self) internal view returns (uint256 _feeCost)
	{
		uint256 _oldTotalSupply = _self.lastTotalSupply;
		uint256 _oldTotalReserve = _self.lastTotalReserve;

		uint256 _newTotalSupply = RewardCompoundingStrategyToken(_self.token).totalSupply();
		uint256 _newTotalReserve = RewardCompoundingStrategyToken(_self.token).totalReserve();

		// calculates the profit using the following formula
		// ((P1 - P0) * S1 * f) / P1
		// where P1 = R1 / S1 and P0 = R0 / S0
		uint256 _positive = _oldTotalSupply.mul(_newTotalReserve);
		uint256 _negative = _newTotalSupply.mul(_oldTotalReserve);
		if (_positive > _negative) {
			uint256 _profitCost = (_positive - _negative) / _oldTotalSupply;
			return _profitCost.mul(_self.performanceFee) / 1e18;
		}

		return 0;
	}

	function _gulpPerformanceFee(Self storage _self) internal
	{
		uint256 _feeCost = _self._calcPerformanceFee();
		if (_feeCost > 0) {
			address _reserveToken = RewardCompoundingStrategyToken(_self.token).reserveToken();
			address _collector = RewardCompoundingStrategyToken(_self.token).collector();
			Transfers._pushFunds(_reserveToken, _collector, _feeCost);
			_self.lastTotalSupply = RewardCompoundingStrategyToken(_self.token).totalSupply();
			_self.lastTotalReserve = RewardCompoundingStrategyToken(_self.token).totalReserve();
		}
	}
}
