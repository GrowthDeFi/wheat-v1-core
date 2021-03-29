// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/EnumerableSet.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { Exchange } from "./Exchange.sol";

import { Transfers } from "./modules/Transfers.sol";
import { UniswapV2LiquidityPoolAbstraction } from "./modules/UniswapV2LiquidityPoolAbstraction.sol";

import { MasterChef } from "./interop/MasterChef.sol";
import { Pair } from "./interop/UniswapV2.sol";

contract RewardCompoundingStrategyToken is ERC20, Ownable, ReentrancyGuard
{
	using SafeMath for uint256;
	using EnumerableSet for EnumerableSet.AddressSet;

	uint256 constant MAXIMUM_DEPOSIT_FEE = 5e16; // 5%
	uint256 constant DEFAULT_DEPOSIT_FEE = 3e16; // 3%

	uint256 constant MAXIMUM_PERFORMANCE_FEE = 50e16; // 50%
	uint256 constant DEFAULT_PERFORMANCE_FEE = 20e16; // 20%

	uint256 constant DEPOSIT_FEE_COLLECTOR_SHARE = 833333333333333333; // 5/6
	uint256 constant DEPOSIT_FEE_DEV_SHARE = 166666666666666667; // 1/6

	address private immutable masterChef;
	uint256 private immutable pid;

	address public immutable reserveToken;
	address public immutable routingToken;
	address public immutable rewardToken;

	address public exchange;

	address public dev;
	address public treasury;
	address public collector;

	uint256 public depositFee = DEFAULT_DEPOSIT_FEE;
	uint256 public performanceFee = DEFAULT_PERFORMANCE_FEE;

	uint256 private lastTotalSupply = 1;
	uint256 private lastTotalReserve = 1;

	EnumerableSet.AddressSet private whitelist;

	modifier onlyEOAorWhitelist()
	{
		address _from = _msgSender();
		require(tx.origin == _from || whitelist.contains(_from), "access denied");
		_;
	}

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
	}

	function totalReserve() public view returns (uint256 _totalReserve)
	{
		(_totalReserve,) = MasterChef(masterChef).userInfo(pid, address(this));
		if (_totalReserve == uint256(-1)) return _totalReserve;
		return _totalReserve + 1; // avoids division by zero
	}

	function calcSharesFromCost(uint256 _cost) external view returns (uint256 _shares)
	{
		(,,,_shares) = _calcSharesFromCost(_cost);
		return _shares;
	}

	function calcCostFromShares(uint256 _shares) external view returns (uint256 _cost)
	{
		(_cost) = _calcCostFromShares(_shares);
		return _cost;
	}

	function pendingReward() external view returns (uint256 _rewardsCost)
	{
		return _calcReward();
	}

	function pendingPerformanceFee() external view returns (uint256 _feeCost)
	{
		return _calcPerformanceFee();
	}

	function deposit(uint256 _cost) external onlyEOAorWhitelist nonReentrant
	{
		address _from = msg.sender;
		(uint256 _devCost, uint256 _collectorCost, uint256 _netCost, uint256 _shares) = _calcSharesFromCost(_cost);
		Transfers._pullFunds(reserveToken, _from, _cost);
		Transfers._pushFunds(reserveToken, dev, _devCost);
		Transfers._pushFunds(reserveToken, collector, _collectorCost);
		Transfers._approveFunds(reserveToken, masterChef, _netCost);
		MasterChef(masterChef).deposit(pid, _netCost);
		_mint(_from, _shares);
	}

	function withdraw(uint256 _shares) external onlyEOAorWhitelist nonReentrant
	{
		address _from = msg.sender;
		(uint256 _cost) = _calcCostFromShares(_shares);
		MasterChef(masterChef).withdraw(pid, _cost);
		Transfers._pushFunds(reserveToken, _from, _cost);
		_burn(_from, _shares);
	}

	function gulp() external onlyEOAorWhitelist nonReentrant
	{
		_gulpReward();
		_gulpPerformanceFee();
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
		require(_newPerformanceFee <= MAXIMUM_PERFORMANCE_FEE, "invalid rate");
		uint256 _oldPerformanceFee = performanceFee;
		performanceFee = _newPerformanceFee;
		emit ChangePerformanceFee(_oldPerformanceFee, _newPerformanceFee);
	}

	function _calcCostFromShares(uint256 _shares) internal view returns (uint256 _cost)
	{
		return _shares.mul(totalReserve()) / totalSupply();
	}

	function _calcSharesFromCost(uint256 _cost) internal view returns (uint256 _devCost, uint256 _collectorCost, uint256 _netCost, uint256 _shares)
	{
		uint256 _feeCost = _cost.mul(depositFee) / 1e18;
		_devCost = (_feeCost * DEPOSIT_FEE_DEV_SHARE) / 1e18;
		_collectorCost = _feeCost - _devCost;
		_netCost = _cost - _feeCost;
		_shares = _netCost.mul(totalSupply()) / totalReserve();
		return (_devCost, _collectorCost, _netCost, _shares);
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

	function _calcPerformanceFee() internal view returns (uint256 _feeCost)
	{
		uint256 _oldTotalSupply = lastTotalSupply;
		uint256 _oldTotalReserve = lastTotalReserve;

		uint256 _newTotalSupply = totalSupply();
		uint256 _newTotalReserve = totalReserve();

		// calculates the profit using the following formula
		// ((P1 - P0) * S1 * f) / P1
		// where P1 = R1 / S1 and P0 = R0 / S0
		uint256 _positive = _oldTotalSupply.mul(_newTotalReserve);
		uint256 _negative = _newTotalSupply.mul(_oldTotalReserve);
		if (_positive > _negative) {
			uint256 _profitCost = (_positive - _negative) / _oldTotalSupply;
			return _profitCost.mul(performanceFee).div(1e18);
		}

		return 0;
	}

	function _gulpReward() internal
	{
		require(exchange != address(0), "exchange not set");
		uint256 _pendingRewardAmount = MasterChef(masterChef).pendingCake(pid, address(this));
		if (_pendingRewardAmount > 0) {
			MasterChef(masterChef).withdraw(pid, 1);
			Transfers._approveFunds(reserveToken, masterChef, 1);
			MasterChef(masterChef).deposit(pid, 1);
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

	function _gulpPerformanceFee() internal
	{
		uint256 _feeCost = _calcPerformanceFee();
		if (_feeCost > 0) {
			Transfers._pushFunds(reserveToken, collector, _feeCost);
			lastTotalSupply = totalSupply();
			lastTotalReserve = totalReserve();
		}
	}

	event ChangeExchange(address _oldExchange, address _newExchange);
	event ChangeDev(address _oldDev, address _newDev);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeCollector(address _oldCollector, address _newCollector);
	event ChangeDepositFee(uint256 _oldDepositFee, uint256 _newDepositFee);
	event ChangePerformanceFee(uint256 _oldPerformanceFee, uint256 _newPerformanceFee);
}
