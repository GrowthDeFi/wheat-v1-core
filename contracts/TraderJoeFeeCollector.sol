// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IExchange } from "./IExchange.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";
import { DelayedActionGuard } from "./DelayedActionGuard.sol";

import { Transfers } from "./modules/Transfers.sol";

import { MasterChefJoeV2, JoeBar } from "./interop/TraderJoe.sol";
import { Pair } from "./interop/UniswapV2.sol";

/**
 * @notice This contract implements a fee collector strategy for TraderJoe's MasterChef.
 *         It accumulates the converted reward token sent from strategies (WAVAX/JOE)
 *         and deposits into MasterChef. The rewards/bonus accumulated on MasterChed from
 *         reserve funds are, on the other hand, collected and sent to the buyback/collector
 *         contract. These operations happen via the gulp function.
 */
contract TraderJoeFeeCollector is ReentrancyGuard, /*WhitelistGuard,*/ DelayedActionGuard
{
	// underlying contract configuration
	address private immutable masterChef;
	uint256 private immutable pid;

	// strategy token configuration
	address public immutable bonusToken;
	address public immutable rewardToken;
	address public immutable reserveToken;

	// addresses receiving tokens
	address public treasury;
	address public buyback;
	address public collector;

	/**
	 * @dev Constructor for this fee collector contract.
	 * @param _masterChef The MasterChef contract address.
	 * @param _pid The MasterChef Pool ID (pid).
	 * @param _treasury The treasury address used to recover lost funds.
	 * @param _buyback The buyback contract address to send collected rewards.
	 * @param _collector The fee collector contract to send collected bonus.
	 */
	constructor (address _masterChef, uint256 _pid,
		address _treasury, address _buyback, address _collector) public
	{
		(address _reserveToken, address _rewardToken, address _bonusToken) = _getTokens(_masterChef, _pid);
		masterChef = _masterChef;
		pid = _pid;
		bonusToken = _bonusToken;
		rewardToken = _rewardToken;
		reserveToken = _reserveToken;
		treasury = _treasury;
		buyback = _buyback;
		collector = _collector;
	}

	/**
	 * Performs the conversion of the reward token received from strategies
	 * into the reserve token. Also collects the rewards from its deposits
	 * and sent it to the buyback contract.
	 */
	function gulp() external /*onlyEOAorWhitelist*/ nonReentrant
	{
		require(_gulp(), "unavailable");
	}

	/// @dev Actual gulp implementation
	function _gulp() internal returns (bool _success)
	{
		{
			uint256 _totalBalance = Transfers._getBalance(reserveToken);
			(uint256 _pendingReward, uint256 _pendingBonus) = _getPendingReward();
			if (_totalBalance > 0 || _pendingReward > 0 || _pendingBonus > 0) {
				_deposit(_totalBalance);
			}
		}
		{
			uint256 _totalBonus = Transfers._getBalance(bonusToken);
			Transfers._pushFunds(bonusToken, collector, _totalBonus);
		}
		{
			uint256 _totalReward = Transfers._getBalance(rewardToken);
			Transfers._pushFunds(rewardToken, buyback, _totalReward);
		}
		return true;
	}

	/**
	 * @notice Allows the recovery of tokens sent by mistake to this
	 *         contract, excluding tokens relevant to its operations.
	 *         The full balance is sent to the treasury address.
	 *         This is a privileged function.
	 * @param _token The address of the token to be recovered.
	 */
	function recoverLostFunds(address _token) external onlyOwner nonReentrant
		delayed(this.recoverLostFunds.selector, keccak256(abi.encode(_token)))
	{
		require(_token != bonusToken, "invalid token");
		require(_token != rewardToken, "invalid token");
		require(_token != reserveToken, "invalid token");
		uint256 _balance = Transfers._getBalance(_token);
		Transfers._pushFunds(_token, treasury, _balance);
	}

	/**
	 * @notice Updates the treasury address used to recover lost funds.
	 *         This is a privileged function.
	 * @param _newTreasury The new treasury address.
	 */
	function setTreasury(address _newTreasury) external onlyOwner
		delayed(this.setTreasury.selector, keccak256(abi.encode(_newTreasury)))
	{
		require(_newTreasury != address(0), "invalid address");
		address _oldTreasury = treasury;
		treasury = _newTreasury;
		emit ChangeTreasury(_oldTreasury, _newTreasury);
	}

	/**
	 * @notice Updates the buyback contract address used to send collected rewards.
	 *         This is a privileged function.
	 * @param _newBuyback The new buyback contract address.
	 */
	function setBuyback(address _newBuyback) external onlyOwner
		delayed(this.setBuyback.selector, keccak256(abi.encode(_newBuyback)))
	{
		require(_newBuyback != address(0), "invalid address");
		address _oldBuyback = buyback;
		buyback = _newBuyback;
		emit ChangeBuyback(_oldBuyback, _newBuyback);
	}

	/**
	 * @notice Updates the fee collector contract address used to send collected bonus.
	 *         This is a privileged function.
	 * @param _newCollector The new fee collector contract address.
	 */
	function setCollector(address _newCollector) external onlyOwner
		delayed(this.setCollector.selector, keccak256(abi.encode(_newCollector)))
	{
		require(_newCollector != address(0), "invalid address");
		address _oldCollector = collector;
		collector = _newCollector;
		emit ChangeCollector(_oldCollector, _newCollector);
	}

	/**
	 * @notice Performs a migration of this contracts funds.
	 *         This is a privileged function.
	 * @param _migrationRecipient The address to receive the migrated funds.
	 * @param _emergency A flag indicating whether or not use the emergency
	 *                   mode from the underlying MasterChef contract.
	 */
	function migrate(address _migrationRecipient, bool _emergency) external onlyOwner
		delayed(this.migrate.selector, keccak256(abi.encode(_migrationRecipient, _emergency)))
	{
		_migrate(_migrationRecipient, _emergency);
		emit Migrate(_migrationRecipient);
	}

	/// @dev Performs the actual migration of funds
	function _migrate(address _migrationRecipient, bool _emergency) internal
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
		Transfers._pushFunds(reserveToken, _migrationRecipient, _totalBalance);
	}

	// ----- BEGIN: underlying contract abstraction

	/// @dev Lists the reserve and reward tokens of the MasterChef pool
	function _getTokens(address _masterChef, uint256 _pid) internal view returns (address _reserveToken, address _rewardToken, address _bonusToken)
	{
		uint256 _poolLength = MasterChefJoeV2(_masterChef).poolLength();
		require(_pid < _poolLength, "invalid pid");
		(_reserveToken,,,,) = MasterChefJoeV2(_masterChef).poolInfo(_pid);
		_rewardToken = MasterChefJoeV2(_masterChef).joe();
		(_bonusToken,) = MasterChefJoeV2(_masterChef).rewarderBonusTokenInfo(_pid);
		return (_reserveToken, _rewardToken, _bonusToken);
	}

	/// @dev Retrieves the current pending reward for the MasterChef pool
	function _getPendingReward() internal view returns (uint256 _pendingReward, uint256 _pendingBonus)
	{
		(_pendingReward,,, _pendingBonus) = MasterChefJoeV2(masterChef).pendingTokens(pid, address(this));
		return (_pendingReward, _pendingBonus);
	}

	/// @dev Retrieves the deposited reserve for the MasterChef pool
	function _getReserveAmount() internal view returns (uint256 _reserveAmount)
	{
		(_reserveAmount,) = MasterChefJoeV2(masterChef).userInfo(pid, address(this));
		return _reserveAmount;
	}

	/// @dev Performs a deposit into the MasterChef pool
	function _deposit(uint256 _amount) internal
	{
		Transfers._approveFunds(reserveToken, masterChef, _amount);
		MasterChefJoeV2(masterChef).deposit(pid, _amount);
	}

	/// @dev Performs an withdrawal from the MasterChef pool
	function _withdraw(uint256 _amount) internal
	{
		MasterChefJoeV2(masterChef).withdraw(pid, _amount);
	}

	/// @dev Performs an emergency withdrawal from the MasterChef pool
	function _emergencyWithdraw() internal
	{
		MasterChefJoeV2(masterChef).emergencyWithdraw(pid);
	}

	// ----- END: underlying contract abstraction

	// events emitted by this contract
	event ChangeBuyback(address _oldBuyback, address _newBuyback);
	event ChangeCollector(address _oldCollector, address _newCollector);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event Migrate(address indexed _migrationRecipient);
}
