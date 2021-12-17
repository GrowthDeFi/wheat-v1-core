// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IExchange } from "./IExchange.sol";
import { DelayedActionGuard } from "./DelayedActionGuard.sol";

import { Transfers } from "./modules/Transfers.sol";

/**
 * @notice This contract implements an "universal" buyback contract. It accumulates
 *         the reward token, send from fee collectors and/or strategies; converts
 *         into the two desired buyback tokens, according to the configured splitting;
 *         and burn these amounts.
 */
contract UniversalBuyback is ReentrancyGuard, DelayedActionGuard
{
	using SafeMath for uint256;

	uint256 constant DEFAULT_MINIMAL_GULP_FACTOR = 80e16; // 80%

	uint256 constant DEFAULT_REWARD_BUYBACK1_SHARE = 85e16; // 85%
	uint256 constant DEFAULT_REWARD_BUYBACK2_SHARE = 15e16; // 15%

	// dead address to receive "burnt" tokens
	address constant public FURNACE = 0x000000000000000000000000000000000000dEaD;

	// buyback token configuration
	address public immutable rewardToken;
	address public immutable buybackToken1;
	address public immutable buybackToken2;

	// addresses receiving tokens
	address public treasury;

	// exchange contract address
	address public exchange;

	// minimal gulp factor
	uint256 public minimalGulpFactor = DEFAULT_MINIMAL_GULP_FACTOR;

	// split configuration
	uint256 public rewardBuyback1Share = DEFAULT_REWARD_BUYBACK1_SHARE;
	uint256 public rewardBuyback2Share = DEFAULT_REWARD_BUYBACK2_SHARE;

	/**
	 * @dev Constructor for this buyback contract.
	 * @param _rewardToken The input reward token for this contract, to be converted.
	 * @param _buybackToken1 The first buyback token for this contract, to convert to and burn accorting to rewardBuyback1Share.
	 * @param _buybackToken2 The second buyback token for this contract, to convert to and burn according to rewardBuyback2Share.
	 * @param _treasury The treasury address used to recover lost funds.
	 * @param _exchange The exchange contract used to convert funds.
	 */
	constructor (address _rewardToken, address _buybackToken1, address _buybackToken2, address _treasury, address _exchange) public
	{
		rewardToken = _rewardToken;
		buybackToken1 = _buybackToken1;
		buybackToken2 = _buybackToken2;
		treasury = _treasury;
		exchange = _exchange;
	}

	/**
	 * @notice Allows for the beforehand calculation of the amount of
	 *         reward token to be converted on the next gulp call.
	 * @return _buybackAmount The amount of the reward token to be converted.
	 */
	/*
	function pendingBuyback() external view returns (uint256 _buybackAmount)
	{
		return Transfers._getBalance(rewardToken);
	}
	*/

	/**
	 * @notice Allows for the beforehand calculation of the amount of
	 *         buyback tokens to be burned on the next gulp call.
	 * @return _burning1 The amount of the first buyback token to be burned.
	 * @return _burning2 The amount of the second buyback token to be burned.
	 */
	/*
	function pendingBurning() external view returns (uint256 _burning1, uint256 _burning2)
	{
		require(exchange != address(0), "exchange not set");
		uint256 _balance = Transfers._getBalance(rewardToken);
		uint256 _amount1 = _balance.mul(rewardBuyback1Share) / 1e18;
		uint256 _amount2 = _balance.mul(rewardBuyback2Share) / 1e18;
		_burning1 = IExchange(exchange).calcConversionFromInput(rewardToken, buybackToken1, _amount1);
		_burning2 = IExchange(exchange).calcConversionFromInput(rewardToken, buybackToken2, _amount2);
		return (_burning1, _burning2);
	}
	*/

	/**
	 * Performs the conversion of the accumulated reward token into
	 * the buyback tokens, according to the defined splitting, and burns them.
	 */
	function gulp() external nonReentrant
	{
		require(_gulp(), "unavailable");
	}

	/// @dev Actual gulp implementation
	function _gulp() internal returns (bool _success)
	{
		require(exchange != address(0), "exchange not set");
		uint256 _balance = Transfers._getBalance(rewardToken);
		uint256 _amount1 = _balance.mul(rewardBuyback1Share) / 1e18;
		uint256 _amount2 = _balance.mul(rewardBuyback2Share) / 1e18;
		uint256 _factor1 = IExchange(exchange).oracleAveragePriceFactorFromInput(rewardToken, buybackToken1, _amount1);
		if (_factor1 < minimalGulpFactor) return false;
		uint256 _factor2 = IExchange(exchange).oracleAveragePriceFactorFromInput(rewardToken, buybackToken2, _amount2);
		if (_factor2 < minimalGulpFactor) return false;
		Transfers._approveFunds(rewardToken, exchange, _amount1 + _amount2);
		IExchange(exchange).convertFundsFromInput(rewardToken, buybackToken1, _amount1, 1);
		IExchange(exchange).convertFundsFromInput(rewardToken, buybackToken2, _amount2, 1);
		uint256 _burning1 = Transfers._getBalance(buybackToken1);
		uint256 _savings2 = Transfers._getBalance(buybackToken2);
		_burn(buybackToken1, _burning1);
		_save(buybackToken2, _savings2);
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
		require(_token != rewardToken, "invalid token");
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
	 * @notice Updates the exchange address used to convert funds. A zero
	 *         address can be used to temporarily pause conversions.
	 *         This is a privileged function.
	 * @param _newExchange The new exchange address.
	 */
	function setExchange(address _newExchange) external onlyOwner
		delayed(this.setExchange.selector, keccak256(abi.encode(_newExchange)))
	{
		address _oldExchange = exchange;
		exchange = _newExchange;
		emit ChangeExchange(_oldExchange, _newExchange);
	}

	/**
	 * @notice Updates the minimal gulp factor which defines the tolerance
	 *         for gulping when below the average price. Default is 99%,
	 *         which implies accepting up to 1% below the average price.
	 *         This is a privileged function.
	 * @param _newMinimalGulpFactor The new minimal gulp factor.
	 */
	function setMinimalGulpFactor(uint256 _newMinimalGulpFactor) external onlyOwner
		delayed(this.setMinimalGulpFactor.selector, keccak256(abi.encode(_newMinimalGulpFactor)))
	{
		require(_newMinimalGulpFactor <= 1e18, "invalid factor");
		uint256 _oldMinimalGulpFactor = minimalGulpFactor;
		minimalGulpFactor = _newMinimalGulpFactor;
		emit ChangeMinimalGulpFactor(_oldMinimalGulpFactor, _newMinimalGulpFactor);
	}

	/**
	 * @notice Updates the split share for the buyback and burn tokens.
	 *         The sum must add up to 100%.
	 *         This is a privileged function.
	 * @param _newRewardBuyback1Share The first token share.
	 * @param _newRewardBuyback2Share The second token share.
	 */
	function setRewardSplit(uint256 _newRewardBuyback1Share, uint256 _newRewardBuyback2Share) external onlyOwner
		delayed(this.setRewardSplit.selector, keccak256(abi.encode(_newRewardBuyback1Share, _newRewardBuyback2Share)))
	{
		require(_newRewardBuyback1Share <= 1e18, "invalid rate");
		require(_newRewardBuyback2Share <= 1e18, "invalid rate");
		require(_newRewardBuyback1Share + _newRewardBuyback2Share == 1e18, "invalid split");
		uint256 _oldRewardBuyback1Share = rewardBuyback1Share;
		uint256 _oldRewardBuyback2Share = rewardBuyback2Share;
		rewardBuyback1Share = _newRewardBuyback1Share;
		rewardBuyback2Share = _newRewardBuyback2Share;
		emit ChangeRewardSplit(_oldRewardBuyback1Share, _oldRewardBuyback2Share, _newRewardBuyback1Share, _newRewardBuyback2Share);
	}

	/// @dev Implements token saving by sending to the treasury address
	function _save(address _token, uint256 _amount) internal
	{
		Transfers._pushFunds(_token, treasury, _amount);
	}

	/// @dev Implements token burning by sending to a dead address
	function _burn(address _token, uint256 _amount) internal
	{
		Transfers._pushFunds(_token, FURNACE, _amount);
	}

	// events emitted by this contract
	event ChangeExchange(address _oldExchange, address _newExchange);
	event ChangeMinimalGulpFactor(uint256 _oldMinimalGulpFactor, uint256 _newMinimalGulpFactor);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeRewardSplit(uint256 _oldRewardBuyback1Share, uint256 _oldRewardBuyback2Share, uint256 _newRewardBuyback1Share, uint256 _newRewardBuyback2Share);
}
