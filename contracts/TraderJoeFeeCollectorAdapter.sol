// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IExchange } from "./IExchange.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";
import { DelayedActionGuard } from "./DelayedActionGuard.sol";

import { Transfers } from "./modules/Transfers.sol";

/*
	80% of JOE converted to USDC.e and injected in a PSM.
	20% of JOE sent to another contract to split amongst the different collectors
		50% AVAX/JOE with TraderJoe
		20% AVAX with Banker
		20% WETH.e with Banker
		10% WBTC.e with Banker
 */
contract TraderJoeFeeCollectorAdapter is ReentrancyGuard, /*WhitelistGuard,*/ DelayedActionGuard
{
	uint256 constant DEFAULT_MINIMAL_GULP_FACTOR = 80e16; // 80%

	// adapter token configuration
	address public immutable sourceToken;
	address public immutable bonusToken;
	address[] public targetTokens;

	// addresses receiving tokens
	address public psm;
	address public treasury;
	mapping (address => address) public collectors;

	// exchange contract address
	address public exchange;

	// minimal gulp factor
	uint256 public minimalGulpFactor = DEFAULT_MINIMAL_GULP_FACTOR;

	constructor (address _sourceToken, address _bonusToken,
		address _psm, address _treasury, address _exchange) public
	{
		sourceToken = _sourceToken;
		bonusToken = _bonusToken;
		psm = _psm;
		treasury = _treasury;
		exchange = _exchange;
	}

	function gulp() external /*onlyEOAorWhitelist*/ nonReentrant
	{
		require(_gulp(), "unavailable");
	}

	function _gulp() internal returns (bool _success)
	{
		require(exchange != address(0), "exchange not set");
		uint256 _totalSource = Transfers._getBalance(sourceToken);
		for (uint256 _i = 0; _i < targetTokens.length; _i++) {
			address _targetToken = targetTokens[_i];
			uint256 _factor = IExchange(exchange).oracleAveragePriceFactorFromInput(sourceToken, _targetToken, _totalSource);
			if (_factor < minimalGulpFactor) return false;
			Transfers._approveFunds(sourceToken, exchange, _totalSource);
			IExchange(exchange).convertFundsFromInput(sourceToken, _targetToken, _totalSource, 1);
			uint256 _totalTarget = Transfers._getBalance(_targetToken);
			Transfers._pushFunds(_targetToken, collectors[_targetToken], _totalTarget);
		}
		{
			uint256 _totalBonus = Transfers._getBalance(bonusToken);
			Transfers._pushFunds(bonusToken, collectors[bonusToken], _totalBonus);
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
	 * @notice Updates the fee collector address used to collect the performance fee.
	 *         This is a privileged function.
	 * @param _newCollector The new fee collector address.
	 */
	function setCollector(address _token, address _newCollector) external onlyOwner
		delayed(this.setCollector.selector, keccak256(abi.encode(_token, _newCollector)))
	{
		require(_newCollector != address(0), "invalid address");
		address _oldCollector = collectors[_token];
		collectors[_token] = _newCollector;
		emit ChangeCollector(_token, _oldCollector, _newCollector);
	}

	/**
	 * @notice Updates the peg stability module address used to collect
	 *         lending fees. This is a privileged function.
	 * @param _newPsm The new peg stability module address.
	 */
	function setPsm(address _newPsm) external onlyOwner
		delayed(this.setPsm.selector, keccak256(abi.encode(_newPsm)))
	{
		address _oldPsm = psm;
		psm = _newPsm;
		emit ChangePsm(_oldPsm, _newPsm);
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

	event ChangePsm(address _oldPsm, address _newPsm);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeCollector(address indexed _token, address _oldCollector, address _newCollector);
	event ChangeExchange(address _oldExchange, address _newExchange);
	event ChangeMinimalGulpFactor(uint256 _oldMinimalGulpFactor, uint256 _newMinimalGulpFactor);
}
