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

	uint256 constant MAXIMUM_PERFORMANCE_FEE = 50e16; // 50%
	uint256 constant DEFAULT_PERFORMANCE_FEE = 10e16; // 20%

	address private immutable autoFarm;
	uint256 private immutable pid;

	address public immutable rewardToken;
	address public immutable routingToken;
	address public immutable reserveToken;

	address public treasury;
	address public collector;

	address public exchange;

	uint256 public performanceFee = DEFAULT_PERFORMANCE_FEE;

	uint256 public lastGulpTime;

	constructor (string memory _name, string memory _symbol, uint8 _decimals,
		address _autoFarm, uint256 _pid, address _routingToken,
		address _treasury, address _collector, address _exchange)
		ERC20(_name, _symbol) public
	{
		_setupDecimals(_decimals);
		(address _reserveToken, address _rewardToken) = _getTokens(_autoFarm, _pid);
		require(_routingToken == _reserveToken || _routingToken == Pair(_reserveToken).token0() || _routingToken == Pair(_reserveToken).token1(), "invalid token");
		autoFarm = _autoFarm;
		pid = _pid;
		rewardToken = _rewardToken;
		routingToken = _routingToken;
		reserveToken = _reserveToken;
		treasury = _treasury;
		collector = _collector;
		exchange = _exchange;
		_mint(address(1), 1); // avoids division by zero
	}

	function totalReserve() public view returns (uint256 _totalReserve)
	{
		_totalReserve = _getReserveAmount();
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

	function pendingPerformanceFee() external view returns (uint256 _feeReward)
	{
		uint256 _pendingReward = _getPendingReward();
		uint256 _balanceReward = Transfers._getBalance(rewardToken);
		uint256 _totalReward = _pendingReward.add(_balanceReward);
		_feeReward = _totalReward.mul(performanceFee) / 1e18;
		return _feeReward;
	}

	function pendingReward() external view returns (uint256 _rewardAmount)
	{
		uint256 _pendingReward = _getPendingReward();
		uint256 _balanceReward = Transfers._getBalance(rewardToken);
		uint256 _totalReward = _pendingReward.add(_balanceReward);
		uint256 _feeReward = _totalReward.mul(performanceFee) / 1e18;
		uint256 _netReward = _totalReward - _feeReward;
		uint256 _totalRouting = _netReward;
		if (rewardToken != routingToken) {
			require(exchange != address(0), "exchange not set");
			_totalRouting = IExchange(exchange).calcConversionFromInput(rewardToken, routingToken, _netReward);
		}
		uint256 _totalBalance = _totalRouting;
		if (routingToken != reserveToken) {
			require(exchange != address(0), "exchange not set");
			_totalBalance = IExchange(exchange).calcJoinPoolFromInput(reserveToken, routingToken, _totalRouting);
		}
		return _totalBalance;
	}

	function deposit(uint256 _amount) external onlyEOAorWhitelist nonReentrant
	{
		address _from = msg.sender;
		uint256 _shares = calcSharesFromAmount(_amount);
		Transfers._pullFunds(reserveToken, _from, _amount);
		_deposit(_amount);
		_mint(_from, _shares);
	}

	function withdraw(uint256 _shares) external onlyEOAorWhitelist nonReentrant
	{
		address _from = msg.sender;
		uint256 _amount = calcAmountFromShares(_shares);
		_burn(_from, _shares);
		_withdraw(_amount);
		Transfers._pushFunds(reserveToken, _from, _amount);
	}

	function gulp() external onlyEOAorWhitelist nonReentrant
	{
		uint256 _pendingReward = _getPendingReward();
		if (_pendingReward > 0) {
			_withdraw(0);
		}
		{
			uint256 _totalReward = Transfers._getBalance(rewardToken);
			uint256 _feeReward = _totalReward.mul(performanceFee) / 1e18;
			Transfers._pushFunds(rewardToken, collector, _feeReward);
		}
		if (rewardToken != routingToken) {
			require(exchange != address(0), "exchange not set");
			uint256 _totalReward = Transfers._getBalance(rewardToken);
			Transfers._approveFunds(rewardToken, exchange, _totalReward);
			IExchange(exchange).convertFundsFromInput(rewardToken, routingToken, _totalReward, 1);
		}
		if (routingToken != reserveToken) {
			require(exchange != address(0), "exchange not set");
			uint256 _totalRouting = Transfers._getBalance(routingToken);
			Transfers._approveFunds(routingToken, exchange, _totalRouting);
			IExchange(exchange).joinPoolFromInput(reserveToken, routingToken, _totalRouting, 1);
		}
		uint256 _totalBalance = Transfers._getBalance(reserveToken);
		_deposit(_totalBalance);
		lastGulpTime = now;
	}

	function recoverLostFunds(address _token) external onlyOwner nonReentrant
	{
		require(_token != reserveToken, "invalid token");
		require(_token != routingToken, "invalid token");
		require(_token != rewardToken, "invalid token");
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
		address _oldExchange = exchange;
		exchange = _newExchange;
		emit ChangeExchange(_oldExchange, _newExchange);
	}

	function setPerformanceFee(uint256 _newPerformanceFee) external onlyOwner nonReentrant
	{
		require(_newPerformanceFee <= MAXIMUM_PERFORMANCE_FEE, "invalid rate");
		uint256 _oldPerformanceFee = performanceFee;
		performanceFee = _newPerformanceFee;
		emit ChangePerformanceFee(_oldPerformanceFee, _newPerformanceFee);
	}

	function _getTokens(address _autoFarm, uint256 _pid) internal view returns (address _reserveToken, address _rewardToken)
	{
		uint256 _poolLength = AutoFarmV2(_autoFarm).poolLength();
		require(_pid < _poolLength, "invalid pid");
		(_reserveToken,,,,) = AutoFarmV2(_autoFarm).poolInfo(_pid);
		_rewardToken = AutoFarmV2(_autoFarm).AUTOv2();
		return (_reserveToken, _rewardToken);
	}

	function _getPendingReward() internal view returns (uint256 _pendingReward)
	{
		return AutoFarmV2(autoFarm).pendingAUTO(pid, address(this));
	}

	function _getReserveAmount() internal view returns (uint256 _reserveAmount)
	{
		return AutoFarmV2(autoFarm).stakedWantTokens(pid, address(this));
	}

	function _deposit(uint256 _amount) internal
	{
		Transfers._approveFunds(reserveToken, autoFarm, _amount);
		AutoFarmV2(autoFarm).deposit(pid, _amount);
	}

	function _withdraw(uint256 _amount) internal
	{
		AutoFarmV2(autoFarm).withdraw(pid, _amount);
	}

	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeCollector(address _oldCollector, address _newCollector);
	event ChangeExchange(address _oldExchange, address _newExchange);
	event ChangePerformanceFee(uint256 _oldPerformanceFee, uint256 _newPerformanceFee);
}
