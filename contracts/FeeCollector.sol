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
	mapping (uint256 => bool) private hodllist;

	address public immutable rewardToken;

	address public buyback;

	uint256 public migrationTimestamp;
	address public migrationRecipient;

	constructor (address _masterChef, address _buyback) public
	{
		address _rewardToken = MasterChef(_masterChef).cake();
		masterChef = _masterChef;
		rewardToken = _rewardToken;
		buyback = _buyback;
	}

	function pendingReward() external view returns (uint256 _reward)
	{
		return _calcReward();
	}

	function gulp() external onlyEOAorWhitelist nonReentrant
	{
		_gulpReward();
	}

	function setBuyback(address _newBuyback) external onlyOwner nonReentrant
	{
		require(_newBuyback != address(0), "invalid address");
		address _oldBuyback = buyback;
		buyback = _newBuyback;
		emit ChangeBuyback(_oldBuyback, _newBuyback);
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

	function updateHodllist(uint256[] memory _pids, bool _hodl) external onlyOwner nonReentrant
	{
		for (uint256 _i = 0; _i < _pids.length; _i++) {
			hodllist[_i] = _hodl;
		}
	}

	function _calcReward() internal view returns (uint256 _reward)
	{
		_reward = Transfers._getBalance(rewardToken);
		uint256 _poolLength = MasterChef(masterChef).poolLength();
		for (uint256 _pid = 1; _pid < _poolLength; _pid++) {
			_reward += MasterChef(masterChef).pendingCake(_pid, address(this));
		}
		return _reward;
	}

	function _gulpReward() internal
	{
		uint256 _poolLength = MasterChef(masterChef).poolLength();
		for (uint256 _pid = 1; _pid < _poolLength; _pid++) {
			if (!hodllist[_pid]) continue;
			(address _token,,,) = MasterChef(masterChef).poolInfo(_pid);
			uint256 _balance = Transfers._getBalance(_token);
			if (_balance > 0) {
				Transfers._approveFunds(_token, masterChef, _balance);
				MasterChef(masterChef).deposit(_pid, _balance);
				continue;
			}
			uint256 _reward = MasterChef(masterChef).pendingCake(_pid, address(this));
			if (_reward > 0) {
				MasterChef(masterChef).withdraw(_pid, 0);
				continue;
			}
		}
		uint256 _balance = Transfers._getBalance(rewardToken);
		Transfers._pushFunds(rewardToken, buyback, _balance);
	}

	function _migrate(bool _emergency) internal
	{
		uint256 _poolLength = MasterChef(masterChef).poolLength();
		if (_emergency) {
			for (uint256 _pid = 1; _pid < _poolLength; _pid++) {
				if (!hodllist[_pid]) continue;
				MasterChef(masterChef).emergencyWithdraw(_pid);
				(address _token,,,) = MasterChef(masterChef).poolInfo(_pid);
				uint256 _balance = Transfers._getBalance(_token);
				Transfers._pushFunds(_token, migrationRecipient, _balance);
			}
		} else {
			for (uint256 _pid = 1; _pid < _poolLength; _pid++) {
				if (!hodllist[_pid]) continue;
				(uint256 _amount,) = MasterChef(masterChef).userInfo(_pid, address(this));
				if (_amount > 0) {
					MasterChef(masterChef).withdraw(_pid, _amount);
				}
				(address _token,,,) = MasterChef(masterChef).poolInfo(_pid);
				uint256 _balance = Transfers._getBalance(_token);
				Transfers._pushFunds(_token, migrationRecipient, _balance);
			}
			uint256 _balance = Transfers._getBalance(rewardToken);
			Transfers._pushFunds(rewardToken, buyback, _balance);
		}
	}

	event ChangeBuyback(address _oldBuyback, address _newBuyback);
	event AnnounceMigration(address indexed _migrationRecipient, uint256 indexed _migrationTimestamp);
	event CancelMigration(address indexed _migrationRecipient, uint256 indexed _migrationTimestamp);
	event Migrate(address indexed _migrationRecipient, uint256 indexed _migrationTimestamp);
}
