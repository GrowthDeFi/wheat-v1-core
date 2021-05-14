// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IExchange } from "./IExchange.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";

import { Transfers } from "./modules/Transfers.sol";

import { AutoFarmV2 } from "./interop/AutoFarmV2.sol";
import { Pair } from "./interop/UniswapV2.sol";

contract AutoFarmFeeCollector is ReentrancyGuard, WhitelistGuard
{
	uint256 constant MIGRATION_WAIT_INTERVAL = 1 days;
	uint256 constant MIGRATION_OPEN_INTERVAL = 1 days;

	address private immutable autoFarm;
	uint256 private immutable pid;

	address public immutable rewardToken;
	address public immutable routingToken;
	address public immutable reserveToken;

	address public treasury;
	address public buyback;

	address public exchange;

	uint256 public lastGulpTime;

	uint256 public migrationTimestamp;
	address public migrationRecipient;

	constructor (address _autoFarm, uint256 _pid, address _routingToken,
		address _treasury, address _buyback, address _exchange) public
	{
		(address _reserveToken, address _rewardToken) = _getTokens(_autoFarm, _pid);
		require(_routingToken == _reserveToken || _routingToken == Pair(_reserveToken).token0() || _routingToken == Pair(_reserveToken).token1(), "invalid token");
		autoFarm = _autoFarm;
		pid = _pid;
		rewardToken = _rewardToken;
		routingToken = _routingToken;
		reserveToken = _reserveToken;
		treasury = _treasury;
		buyback = _buyback;
		exchange = _exchange;
	}

	function pendingDeposit() external view returns (uint256 _depositAmount)
	{
		uint256 _totalReward = Transfers._getBalance(rewardToken);
		uint256 _totalRouting = _totalReward;
		if (rewardToken != routingToken) {
			require(exchange != address(0), "exchange not set");
			_totalRouting = IExchange(exchange).calcConversionFromInput(rewardToken, routingToken, _totalReward);
		}
		uint256 _totalBalance = _totalRouting;
		if (routingToken != reserveToken) {
			require(exchange != address(0), "exchange not set");
			_totalBalance = IExchange(exchange).calcJoinPoolFromInput(reserveToken, routingToken, _totalRouting);
		}
		return _totalBalance;
	}

	function pendingReward() external view returns (uint256 _pendingReward)
	{
		return _getPendingReward();
	}

	function gulp(uint256 _minDepositAmount) external onlyEOAorWhitelist nonReentrant
	{
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
		require(_totalBalance >= _minDepositAmount, "high slippage");
		_deposit(_totalBalance);
		uint256 _totalReward = Transfers._getBalance(rewardToken);
		Transfers._pushFunds(rewardToken, buyback, _totalReward);
		lastGulpTime = now;
	}

	function recoverLostFunds(address _token) external onlyOwner nonReentrant
	{
		require(_token != rewardToken, "invalid token");
		require(_token != routingToken, "invalid token");
		require(_token != reserveToken, "invalid token");
		uint256 _balance = Transfers._getBalance(_token);
		Transfers._pushFunds(_token, treasury, _balance);
	}

	function setBuyback(address _newBuyback) external onlyOwner nonReentrant
	{
		require(_newBuyback != address(0), "invalid address");
		address _oldBuyback = buyback;
		buyback = _newBuyback;
		emit ChangeBuyback(_oldBuyback, _newBuyback);
	}

	function setTreasury(address _newTreasury) external onlyOwner nonReentrant
	{
		require(_newTreasury != address(0), "invalid address");
		address _oldTreasury = treasury;
		treasury = _newTreasury;
		emit ChangeTreasury(_oldTreasury, _newTreasury);
	}

	function setExchange(address _newExchange) external onlyOwner nonReentrant
	{
		address _oldExchange = exchange;
		exchange = _newExchange;
		emit ChangeExchange(_oldExchange, _newExchange);
	}

	function announceMigration(address _migrationRecipient) external onlyOwner nonReentrant
	{
		require(migrationTimestamp == 0, "ongoing migration");
		uint256 _migrationTimestamp = now;
		migrationTimestamp = _migrationTimestamp;
		migrationRecipient = _migrationRecipient;
		emit AnnounceMigration(_migrationRecipient, _migrationTimestamp);
	}

	function cancelMigration() external onlyOwner nonReentrant
	{
		uint256 _migrationTimestamp = migrationTimestamp;
		require(_migrationTimestamp != 0, "migration not started");
		address _migrationRecipient = migrationRecipient;
		migrationTimestamp = 0;
		migrationRecipient = address(0);
		emit CancelMigration(_migrationRecipient, _migrationTimestamp);
	}

	function migrate(address _migrationRecipient, bool _emergency) external onlyOwner nonReentrant
	{
		uint256 _migrationTimestamp = migrationTimestamp;
		require(_migrationTimestamp != 0, "migration not started");
		require(_migrationRecipient == migrationRecipient, "recipient mismatch");
		uint256 _start = _migrationTimestamp + MIGRATION_WAIT_INTERVAL;
		uint256 _end = _start + MIGRATION_OPEN_INTERVAL;
		require(_start <= now && now < _end, "not available");
		_migrate(_emergency);
		migrationTimestamp = 0;
		migrationRecipient = address(0);
		emit Migrate(_migrationRecipient, _migrationTimestamp);
	}

	function _migrate(bool _emergency) internal
	{
		if (_emergency) {
			_emergencyWithdraw();
		} else {
			uint256 _totalReserve = _getReserveAmount();
			if (_totalReserve > 0) {
				_withdraw(_totalReserve);
			}
			uint256 _totalReward = Transfers._getBalance(rewardToken);
			if (reserveToken == rewardToken) {
				_totalReward -= _totalReserve;
			}
			Transfers._pushFunds(rewardToken, buyback, _totalReward);
		}
		uint256 _totalBalance = Transfers._getBalance(reserveToken);
		Transfers._pushFunds(reserveToken, migrationRecipient, _totalBalance);
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

	function _emergencyWithdraw() internal
	{
		AutoFarmV2(autoFarm).emergencyWithdraw(pid);
	}

	event ChangeBuyback(address _oldBuyback, address _newBuyback);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeExchange(address _oldExchange, address _newExchange);
	event AnnounceMigration(address indexed _migrationRecipient, uint256 indexed _migrationTimestamp);
	event CancelMigration(address indexed _migrationRecipient, uint256 indexed _migrationTimestamp);
	event Migrate(address indexed _migrationRecipient, uint256 indexed _migrationTimestamp);
}
