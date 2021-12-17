// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { DelayedActionGuard } from "./DelayedActionGuard.sol";

import { Transfers } from "./modules/Transfers.sol";
import { Wrapping } from "./modules/Wrapping.sol";

import { Joetroller, JRewardDistributor, JToken } from "./interop/BankerJoe.sol";

/**
 * @notice This contract implements a fee collector strategy for BankerJoe.
 *         It accumulates the token sent from strategies and converts it
 *         into reserve funds which are deposited into BankerJoe. The rewards accumulated
 *         on BankerJoe from reserve funds are, on the other hand, collected and sent to
 *         the buyback contract. These operations happen via the gulp function.
 */
contract BankerJoeFeeCollector is ReentrancyGuard, DelayedActionGuard
{
	// strategy token configuration
	address public immutable bonusToken;
	address public immutable rewardToken;
	address public immutable reserveToken;
	address public immutable underlyingToken;

	// addresses receiving tokens
	address public treasury;
	address public buyback;
	address public collector;

	/**
	 * @dev Constructor for this fee collector contract.
	 * @param _reserveToken The jToken address to be used as reserve.
	 * @param _bonusToken The token address to be collected as bonus.
	 * @param _treasury The treasury address used to recover lost funds.
	 * @param _buyback The buyback contract address to send collected rewards.
	 * @param _collector The fee collector address to send bonus rewards.
	 */
	constructor (address _reserveToken, address _bonusToken,
		address _treasury, address _buyback, address _collector) public
	{
		(address _underlyingToken, address _rewardToken) = _getTokens(_reserveToken);
		bonusToken = _bonusToken;
		rewardToken = _rewardToken;
		reserveToken = _reserveToken;
		underlyingToken = _underlyingToken;
		treasury = _treasury;
		buyback = _buyback;
		collector = _collector;
	}

	/**
	 * Performs the conversion of the reward token received from strategies
	 * into the reserve token. Also collects the rewards from its deposits
	 * and sent it to the buyback contract.
	 */
	function gulp() external nonReentrant
	{
		require(_gulp(), "unavailable");
	}

	/// @dev Actual gulp implementation
	function _gulp() internal returns (bool _success)
	{
		{
			uint256 _totalBalance = Transfers._getBalance(underlyingToken);
			_deposit(_totalBalance);
		}
		_claim();
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
		require(_token != underlyingToken, "invalid token");
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
	 */
	function migrate(address _migrationRecipient) external onlyOwner
		delayed(this.migrate.selector, keccak256(abi.encode(_migrationRecipient)))
	{
		_migrate(_migrationRecipient);
		emit Migrate(_migrationRecipient);
	}

	/// @dev Performs the actual migration of funds
	function _migrate(address _migrationRecipient) internal
	{
		uint256 _totalBalance = Transfers._getBalance(reserveToken);
		Transfers._pushFunds(reserveToken, _migrationRecipient, _totalBalance);
	}

	// ----- BEGIN: underlying contract abstraction

	/// @dev Lists the reserve and reward tokens of the lending pool
	function _getTokens(address _reserveToken) internal view returns (address _underlyingToken, address _rewardToken)
	{
		address _joetroller = JToken(_reserveToken).joetroller();
		address _distributor = Joetroller(_joetroller).rewardDistributor();
		_underlyingToken = JToken(_reserveToken).underlying();
		_rewardToken = JRewardDistributor(_distributor).joeAddress();
		return (_underlyingToken, _rewardToken);
	}

	/// @dev Performs a deposit into the lending pool
	function _deposit(uint256 _amount) internal
	{
		Transfers._approveFunds(underlyingToken, reserveToken, _amount);
		uint256 _errorCode = JToken(reserveToken).mint(_amount);
		require(_errorCode == 0, "lend unavailable");
	}

	/// @dev Claims the current pending reward for the lending pool
	function _claim() internal
	{
		address _joetroller = JToken(reserveToken).joetroller();
		address _distributor = Joetroller(_joetroller).rewardDistributor();
		address payable[] memory _accounts = new address payable[](1);
		_accounts[0] = address(this);
		address[] memory _jtokens = new address[](1);
		_jtokens[0] = reserveToken;
		JRewardDistributor(_distributor).claimReward(0, _accounts, _jtokens, false, true);
		JRewardDistributor(_distributor).claimReward(1, _accounts, _jtokens, false, true);
		Wrapping._wrap(bonusToken, address(this).balance);
	}

	// ----- END: underlying contract abstraction

	/// @dev Allows for receiving the native token
	receive() external payable
	{
	}

	// events emitted by this contract
	event ChangeBuyback(address _oldBuyback, address _newBuyback);
	event ChangeCollector(address _oldCollector, address _newCollector);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event Migrate(address indexed _migrationRecipient);
}
