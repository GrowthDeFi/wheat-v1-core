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

	address public immutable reserveToken;
	address public immutable rewardToken;

	address public exchange;

	address public buyback;
	address public treasury;

	uint256 public migrationTimestamp;
	address public migrationRecipient;

	constructor (address _autoFarm, uint256 _pid, address _buyback, address _treasury) public
	{
		uint256 _poolLength = AutoFarmV2(_autoFarm).poolLength();
		require(_pid < _poolLength, "invalid pid");
		address _rewardToken = AutoFarmV2(_autoFarm).AUTOv2();
		(address _reserveToken,,,,) = AutoFarmV2(_autoFarm).poolInfo(_pid);
		require(_rewardToken == _reserveToken || _rewardToken == Pair(_reserveToken).token0() || _rewardToken == Pair(_reserveToken).token1(), "invalid token");
		autoFarm = _autoFarm;
		pid = _pid;
		reserveToken = _reserveToken;
		rewardToken = _rewardToken;
		buyback = _buyback;
		treasury = _treasury;
	}

	function pendingDeposit() external view returns (uint256 _depositAmount)
	{
		return _calcPendingDeposit();
	}

	function pendingReward() external view returns (uint256 _rewardAmount)
	{
		return _calcPendingReward();
	}

	function gulp() external onlyEOAorWhitelist nonReentrant
	{
		_gulp();
	}

	function recoverLostFunds(address _token) external onlyOwner nonReentrant
	{
		require(_token != reserveToken, "invalid token");
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

	function _calcPendingDeposit() internal view returns (uint256 _depositAmount)
	{
		return Transfers._getBalance(rewardToken);
	}

	function _calcPendingReward() internal view returns (uint256 _rewardAmount)
	{
		return AutoFarmV2(autoFarm).pendingAUTO(pid, address(this));
	}

	function _gulp() internal
	{
		if (reserveToken != rewardToken) {
			uint256 _depositBalance = Transfers._getBalance(rewardToken);
			if (_depositBalance > 0) {
				Transfers._approveFunds(rewardToken, exchange, _depositBalance);
				IExchange(exchange).joinPoolFromInput(reserveToken, rewardToken, _depositBalance, 1);
			}
		}
		uint256 _reserveBalance = Transfers._getBalance(reserveToken);
		if (_reserveBalance > 0) {
			_deposit(_reserveBalance);
		} else {
			uint256 _pendingReward = AutoFarmV2(autoFarm).pendingAUTO(pid, address(this));
			if (_pendingReward > 0) {
				_withdraw(0);
			}
		}
		uint256 _rewardBalance = Transfers._getBalance(rewardToken);
		Transfers._pushFunds(rewardToken, buyback, _rewardBalance);
	}

	function _migrate(bool _emergency) internal
	{
		if (_emergency) {
			AutoFarmV2(autoFarm).emergencyWithdraw(pid);
		} else {
			uint256 _amount = AutoFarmV2(autoFarm).stakedWantTokens(pid, address(this));
			if (_amount > 0) {
				_withdraw(_amount);
			}
			uint256 _rewardBalance = Transfers._getBalance(rewardToken);
			if (reserveToken == rewardToken) {
				_rewardBalance -= _amount;
			}
			Transfers._pushFunds(rewardToken, buyback, _rewardBalance);
		}
		uint256 _reserveBalance = Transfers._getBalance(reserveToken);
		Transfers._pushFunds(reserveToken, migrationRecipient, _reserveBalance);
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

	event ChangeExchange(address _oldExchange, address _newExchange);
	event ChangeBuyback(address _oldBuyback, address _newBuyback);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event AnnounceMigration(address indexed _migrationRecipient, uint256 indexed _migrationTimestamp);
	event CancelMigration(address indexed _migrationRecipient, uint256 indexed _migrationTimestamp);
	event Migrate(address indexed _migrationRecipient, uint256 indexed _migrationTimestamp);
}
