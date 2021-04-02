// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { WhitelistGuard } from "./WhitelistGuard.sol";

import { Transfers } from "./modules/Transfers.sol";

import { MasterChef } from "./interop/MasterChef.sol";

contract FeeCollector is ReentrancyGuard, WhitelistGuard
{
	uint256 constant MIGRATION_WAIT_INTERVAL = 1 days;
	uint256 constant MIGRATION_OPEN_INTERVAL = 1 days;

	address private immutable masterChef;
	uint256 private immutable pid;

	address public immutable reserveToken;
	address public immutable rewardToken;

	address public buyback;
	address public treasury;

	uint256 public migrationTimestamp;
	address public migrationRecipient;

	constructor (address _masterChef, uint256 _pid, address _buyback, address _treasury) public
	{
		uint256 _poolLength = MasterChef(_masterChef).poolLength();
		require(1 <= _pid && _pid < _poolLength, "invalid pid");
		address _rewardToken = MasterChef(_masterChef).cake();
		(address _reserveToken,,,) = MasterChef(_masterChef).poolInfo(_pid);
		masterChef = _masterChef;
		pid = _pid;
		reserveToken = _reserveToken;
		rewardToken = _rewardToken;
		buyback = _buyback;
		treasury = _treasury;
	}

	function pendingReward() external view returns (uint256 _reward)
	{
		return _calcReward();
	}

	function gulp() external onlyEOAorWhitelist nonReentrant
	{
		_gulpReward();
	}

	function recoverLostFunds(address _token) external onlyOwner nonReentrant
	{
		require(_token != reserveToken, "invalid token");
		require(_token != rewardToken, "invalid token");
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

	function _calcReward() internal view returns (uint256 _reward)
	{
		_reward = Transfers._getBalance(rewardToken);
		_reward += MasterChef(masterChef).pendingCake(pid, address(this));
		return _reward;
	}

	function _gulpReward() internal
	{
		uint256 _reserveBalance = Transfers._getBalance(reserveToken);
		if (_reserveBalance > 0) {
			Transfers._approveFunds(reserveToken, masterChef, _reserveBalance);
			MasterChef(masterChef).deposit(pid, _reserveBalance);
		} else {
			uint256 _pendingReward = MasterChef(masterChef).pendingCake(pid, address(this));
			if (_pendingReward > 0) {
				MasterChef(masterChef).withdraw(pid, 0);
			}
		}
		uint256 _rewardBalance = Transfers._getBalance(rewardToken);
		Transfers._pushFunds(rewardToken, buyback, _rewardBalance);
	}

	function _migrate(bool _emergency) internal
	{
		if (_emergency) {
			MasterChef(masterChef).emergencyWithdraw(pid);
		} else {
			(uint256 _amount,) = MasterChef(masterChef).userInfo(pid, address(this));
			if (_amount > 0) {
				MasterChef(masterChef).withdraw(pid, _amount);
			}
			uint256 _rewardBalance = Transfers._getBalance(rewardToken);
			Transfers._pushFunds(rewardToken, buyback, _rewardBalance);
		}
		uint256 _reserveBalance = Transfers._getBalance(reserveToken);
		Transfers._pushFunds(reserveToken, migrationRecipient, _reserveBalance);
	}

	event ChangeBuyback(address _oldBuyback, address _newBuyback);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event AnnounceMigration(address indexed _migrationRecipient, uint256 indexed _migrationTimestamp);
	event CancelMigration(address indexed _migrationRecipient, uint256 indexed _migrationTimestamp);
	event Migrate(address indexed _migrationRecipient, uint256 indexed _migrationTimestamp);
}
