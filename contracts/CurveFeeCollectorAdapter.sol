// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

/*
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
*/
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IExchange } from "./IExchange.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";
import { DelayedActionGuard } from "./DelayedActionGuard.sol";

import { Transfers } from "./modules/Transfers.sol";
import { Wrapping } from "./modules/Wrapping.sol";

/**
 * This is the reward collector adapter for Curve strategies.
 * It converts the reward token (CURVE) into WAVAX and sends WAVAX to the
 * actual fee collector. The additional AVAX/WAVAX sent as reward is sent along.
 */
contract CurveFeeCollectorAdapter is ReentrancyGuard, /*WhitelistGuard,*/ DelayedActionGuard
{
	uint256 constant DEFAULT_MINIMAL_GULP_FACTOR = 80e16; // 80%

	// adapter token configuration
	address public immutable sourceToken;
	address public immutable targetToken;

	// addresses receiving tokens
	address public treasury;
	address public collector;

	// exchange contract address
	address public exchange;

	// minimal gulp factor
	uint256 public minimalGulpFactor = DEFAULT_MINIMAL_GULP_FACTOR;

	constructor (address _sourceToken, address _targetToken,
		address _collector, address _treasury, address _exchange) public
	{
		require(_targetToken != _sourceToken, "invalid token");
		sourceToken = _sourceToken;
		targetToken = _targetToken;
		collector = _collector;
		treasury = _treasury;
		exchange = _exchange;
	}

	function gulp() external /*onlyEOAorWhitelist*/ nonReentrant
	{
		require(_gulp(), "unavailable");
	}

	function _gulp() internal returns (bool _success)
	{
		{
			uint256 _totalSource = Transfers._getBalance(sourceToken);
			if (_totalSource > 0) {
				require(exchange != address(0), "exchange not set");
				uint256 _factor = IExchange(exchange).oracleAveragePriceFactorFromInput(sourceToken, targetToken, _totalSource);
				if (_factor < minimalGulpFactor) return false;
				Transfers._approveFunds(sourceToken, exchange, _totalSource);
				IExchange(exchange).convertFundsFromInput(sourceToken, targetToken, _totalSource, 1);
			}
		}
		Wrapping._wrap(targetToken, address(this).balance);
		{
			uint256 _totalTarget = Transfers._getBalance(targetToken);
			Transfers._pushFunds(targetToken, collector, _totalTarget);
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
		require(_token != sourceToken, "invalid token");
		require(_token != targetToken, "invalid token");
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
	 * @notice Updates the fee collector address used to collect the converted rewards.
	 *         This is a privileged function.
	 * @param _newCollector The new fee collector address.
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
	 *         for gulping when below the average price. Default is 80%,
	 *         which implies accepting up to 20% below the average price.
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

	/// @dev Allows for receiving the native token
	receive() external payable
	{
	}

	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeCollector(address _oldCollector, address _newCollector);
	event ChangeExchange(address _oldExchange, address _newExchange);
	event ChangeMinimalGulpFactor(uint256 _oldMinimalGulpFactor, uint256 _newMinimalGulpFactor);
}
