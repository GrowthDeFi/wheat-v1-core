// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IExchange } from "./IExchange.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";

import { Transfers } from "./modules/Transfers.sol";

import { MasterChef } from "./interop/MasterChef.sol";
import { Pair } from "./interop/UniswapV2.sol";

contract PancakeSwapCompoundingStrategyToken is ERC20, ReentrancyGuard, WhitelistGuard
{
	using SafeMath for uint256;

	uint256 constant MAXIMUM_DEPOSIT_FEE = 5e16; // 5%
	uint256 constant DEFAULT_DEPOSIT_FEE = 0e16; // 0%

	uint256 constant MAXIMUM_PERFORMANCE_FEE = 50e16; // 50%
	uint256 constant DEFAULT_PERFORMANCE_FEE = 10e16; // 10%

	address private immutable masterChef;
	uint256 private immutable pid;

	address public immutable rewardToken;
	address public immutable routingToken;
	address public immutable reserveToken;

	address public dev;
	address public treasury;
	address public collector;

	address public exchange;

	uint256 public depositFee = DEFAULT_DEPOSIT_FEE;
	uint256 public performanceFee = DEFAULT_PERFORMANCE_FEE;

	uint256 public lastGulpTime;

	constructor (string memory _name, string memory _symbol, uint8 _decimals,
		address _masterChef, uint256 _pid, address _routingToken,
		address _dev, address _treasury, address _collector, address _exchange)
		ERC20(_name, _symbol) public
	{
		_setupDecimals(_decimals);
		(address _reserveToken, address _rewardToken) = _getTokens(_masterChef, _pid);
		require(_routingToken == _reserveToken || _routingToken == Pair(_reserveToken).token0() || _routingToken == Pair(_reserveToken).token1(), "invalid token");
		masterChef = _masterChef;
		pid = _pid;
		rewardToken = _rewardToken;
		routingToken = _routingToken;
		reserveToken = _reserveToken;
		dev = _dev;
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

	function calcSharesFromAmount(uint256 _amount) external view returns (uint256 _shares)
	{
		(,,_shares) = _calcSharesFromAmount(_amount);
		return _shares;
	}

	function calcAmountFromShares(uint256 _shares) external view returns (uint256 _amount)
	{
		return _calcAmountFromShares(_shares);
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
		(uint256 _devAmount, uint256 _netAmount, uint256 _shares) = _calcSharesFromAmount(_amount);
		Transfers._pullFunds(reserveToken, _from, _amount);
		Transfers._pushFunds(reserveToken, dev, _devAmount);
		_deposit(_netAmount);
		_mint(_from, _shares);
	}

	function withdraw(uint256 _shares) external onlyEOAorWhitelist nonReentrant
	{
		address _from = msg.sender;
		uint256 _amount = _calcAmountFromShares(_shares);
		_burn(_from, _shares);
		_withdraw(_amount);
		Transfers._pushFunds(reserveToken, _from, _amount);
	}

	function gulp(uint256 _minRewardAmount) external onlyEOAorWhitelist nonReentrant
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
		require(_totalBalance >= _minRewardAmount, "high slippage");
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

	function setExchange(address _newExchange) external onlyOwner nonReentrant
	{
		address _oldExchange = exchange;
		exchange = _newExchange;
		emit ChangeExchange(_oldExchange, _newExchange);
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

	function _calcSharesFromAmount(uint256 _amount) internal view returns (uint256 _feeAmount, uint256 _netAmount, uint256 _shares)
	{
		_feeAmount = _amount.mul(depositFee) / 1e18;
		_netAmount = _amount - _feeAmount;
		_shares = _netAmount.mul(totalSupply()) / totalReserve();
		return (_feeAmount, _netAmount, _shares);
	}

	function _calcAmountFromShares(uint256 _shares) internal view returns (uint256 _amount)
	{
		return _shares.mul(totalReserve()) / totalSupply();
	}

	function _getTokens(address _masterChef, uint256 _pid) internal view returns (address _reserveToken, address _rewardToken)
	{
		uint256 _poolLength = MasterChef(_masterChef).poolLength();
		require(_pid < _poolLength, "invalid pid");
		(_reserveToken,,,) = MasterChef(_masterChef).poolInfo(_pid);
		_rewardToken = MasterChef(_masterChef).cake();
		return (_reserveToken, _rewardToken);
	}

	function _getPendingReward() internal view returns (uint256 _pendingReward)
	{
		return MasterChef(masterChef).pendingCake(pid, address(this));
	}

	function _getReserveAmount() internal view returns (uint256 _reserveAmount)
	{
		(_reserveAmount,) = MasterChef(masterChef).userInfo(pid, address(this));
		return _reserveAmount;
	}

	function _deposit(uint256 _amount) internal
	{
		Transfers._approveFunds(reserveToken, masterChef, _amount);
		if (pid == 0) {
			MasterChef(masterChef).enterStaking(_amount);
		} else {
			MasterChef(masterChef).deposit(pid, _amount);
		}
	}

	function _withdraw(uint256 _amount) internal
	{
		if (pid == 0) {
			MasterChef(masterChef).leaveStaking(_amount);
		} else {
			MasterChef(masterChef).withdraw(pid, _amount);
		}
	}

	event ChangeDev(address _oldDev, address _newDev);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeCollector(address _oldCollector, address _newCollector);
	event ChangeExchange(address _oldExchange, address _newExchange);
	event ChangeDepositFee(uint256 _oldDepositFee, uint256 _newDepositFee);
	event ChangePerformanceFee(uint256 _oldPerformanceFee, uint256 _newPerformanceFee);
}
