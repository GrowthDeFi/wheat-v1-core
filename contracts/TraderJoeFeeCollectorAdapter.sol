// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IExchange } from "./IExchange.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";
import { DelayedActionGuard } from "./DelayedActionGuard.sol";
import { BankerJoePeggedToken } from "./BankerJoePeggedToken.sol";

import { Transfers } from "./modules/Transfers.sol";

import { PSM } from "./interop/Mor.sol";

/**
 * This is the fee collector splitting contract for TraderJoe strategies.
 * By default it splits the reward token (JOE) converting 80% to stkUSDCv3 and injecting
 * in the PSM; 10% converted into AVAX/JOE shares and sent to the associated
 * fee collector; 4% converted into WAVAX and sent to the associated fee collector;
 * 4% converted into WETH and sent to the associated collector; and 2% converted into
 * WBTC and sent to the associated collector.
 */
contract TraderJoeFeeCollectorAdapter is ReentrancyGuard, /*WhitelistGuard,*/ DelayedActionGuard
{
	using SafeMath for uint256;

	uint256 constant DEFAULT_MINIMAL_GULP_FACTOR = 80e16; // 80%

	// adapter token configuration
	address public immutable sourceToken;
	address public immutable bonusToken;
	address payable public immutable peggedToken;
	address[] public targetTokens;

	// splitting scheme
	mapping (address => bool) public pools;
	mapping (address => uint256) public percents;

	// addresses receiving tokens
	address public psm;
	address public treasury;
	mapping (address => address) public collectors;

	// exchange contract address
	address public exchange;

	// minimal gulp factor
	uint256 public minimalGulpFactor = DEFAULT_MINIMAL_GULP_FACTOR;

	constructor (address _sourceToken, address _bonusToken, address payable _peggedToken,
		address[] memory _targetTokens, bool[] memory _pools, uint256[] memory _percents, address[] memory _collectors,
		address _psm, address _treasury, address _exchange) public
	{
		require(_pools.length == _targetTokens.length && _percents.length == _targetTokens.length && _collectors.length == _targetTokens.length, "invalid length");
		sourceToken = _sourceToken;
		bonusToken = _bonusToken;
		peggedToken = _peggedToken;
		uint256 _accPercent = 0;
		for (uint256 _i = 0; _i < _targetTokens.length; _i++) {
			address _targetToken = _targetTokens[_i];
			require(_targetToken != _sourceToken, "invalid token");
			require(percents[_targetToken] <= 1e18, "invalid percents");
			targetTokens.push(_targetToken);
			pools[_targetToken] = _pools[_i];
			percents[_targetToken] = _percents[_i];
			collectors[_targetToken] = _collectors[_i];
			_accPercent += _percents[_i];
		}
		require(_accPercent <= 1e18, "invalid percents");
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
		{
			uint256 _totalBonus = Transfers._getBalance(bonusToken);
			Transfers._pushFunds(bonusToken, collectors[bonusToken], _totalBonus);
		}
		{
			uint256 _totalSource = Transfers._getBalance(sourceToken);
			for (uint256 _i = 0; _i < targetTokens.length; _i++) {
				address _targetToken = targetTokens[_i];
				uint256 _partialSource = _totalSource.mul(percents[_targetToken]) / 1e18;
				{
					require(exchange != address(0), "exchange not set");
					if (!pools[_targetToken]) {
						uint256 _factor = IExchange(exchange).oracleAveragePriceFactorFromInput(sourceToken, _targetToken, _partialSource);
						if (_factor < minimalGulpFactor) return false;
						Transfers._approveFunds(sourceToken, exchange, _partialSource);
						IExchange(exchange).convertFundsFromInput(sourceToken, _targetToken, _partialSource, 1);
					} else {
						uint256 _factor = IExchange(exchange).oraclePoolAveragePriceFactorFromInput(_targetToken, sourceToken, _partialSource);
						if (_factor < minimalGulpFactor || _factor > 2e18 - minimalGulpFactor) return false;
						Transfers._approveFunds(sourceToken, exchange, _partialSource);
						IExchange(exchange).joinPoolFromInput(_targetToken, sourceToken, _partialSource, 1);
					}
				}
				uint256 _totalTarget = Transfers._getBalance(_targetToken);
				Transfers._pushFunds(_targetToken, collectors[_targetToken], _totalTarget);
			}
		}
		{
			uint256 _totalSource = Transfers._getBalance(sourceToken);
			(,,address _targetToken,,,,) = BankerJoePeggedToken(peggedToken).state();
			{
				require(exchange != address(0), "exchange not set");
				uint256 _factor = IExchange(exchange).oracleAveragePriceFactorFromInput(sourceToken, _targetToken, _totalSource);
				if (_factor < minimalGulpFactor) return false;
				Transfers._approveFunds(sourceToken, exchange, _totalSource);
				IExchange(exchange).convertFundsFromInput(sourceToken, _targetToken, _totalSource, 1);
			}
			uint256 _totalTarget = Transfers._getBalance(_targetToken);
			Transfers._approveFunds(_targetToken, peggedToken, _totalTarget);
			BankerJoePeggedToken(peggedToken).deposit(_totalTarget);
			if (psm == address(0)) {
				Transfers._pushFunds(peggedToken, treasury, _totalTarget);
			} else {
				Transfers._approveFunds(peggedToken, PSM(psm).gemJoin(), _totalTarget);
				PSM(psm).sellGem(treasury, _totalTarget);
			}
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
		require(_token != sourceToken, "invalid token");
		require(_token != peggedToken, "invalid token");
		for (uint256 _i = 0; _i < targetTokens.length; _i++) {
			address _targetToken = targetTokens[_i];
			require(_token != _targetToken, "invalid token");
		}
		uint256 _balance = Transfers._getBalance(_token);
		Transfers._pushFunds(_token, treasury, _balance);
	}

	/**
	 * @notice Adds a new target token.
	 *         This is a privileged function.
	 * @param _newTargetToken The new target token address.
	 * @param _pool whether or not the new target token is a liquidity pool share.
	 * @param _percent The new target token percentual allocation.
	 * @param _collector The new target token collector address.
	 */
	function addTargetToken(address _newTargetToken, bool _pool, uint256 _percent, address _collector) external onlyOwner
		delayed(this.addTargetToken.selector, keccak256(abi.encode(_newTargetToken, _pool, _percent, _collector)))
	{
		require(_newTargetToken != sourceToken, "invalid token");
		uint256 _accPercent = _percent;
		for (uint256 _i = 0; _i < targetTokens.length; _i++) {
			address _targetToken = targetTokens[_i];
			require(_targetToken != _newTargetToken, "invalid token");
			_accPercent += percents[_targetToken];
		}
		require(_accPercent <= 1e18, "invalid percent");
		targetTokens.push(_newTargetToken);
		pools[_newTargetToken] = _pool;
		percents[_newTargetToken] = _percent;
		collectors[_newTargetToken] = _collector;
		emit AddTargetToken(_newTargetToken);
	}

	/**
	 * @notice Removes an existing target token.
	 *         This is a privileged function.
	 * @param _oldTargetToken The address for the target token being removed.
	 */
	function dropTargetToken(address _oldTargetToken) external onlyOwner
		delayed(this.dropTargetToken.selector, keccak256(abi.encode(_oldTargetToken)))
	{
		uint256 _index = uint256(-1);
		for (uint256 _i = 0; _i < targetTokens.length; _i++) {
			address _targetToken = targetTokens[_i];
			if (_targetToken == _oldTargetToken) {
				_index = _i;
				break;
			}
		}
		require(_index < targetTokens.length, "invalid token");
		targetTokens[_index] = targetTokens[targetTokens.length - 1];
		targetTokens.pop();
		pools[_oldTargetToken] = false;
		percents[_oldTargetToken] = 0;
		if (_oldTargetToken != bonusToken) collectors[_oldTargetToken] = address(0);
		emit DropTargetToken(_oldTargetToken);
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
	function setCollector(address _targetToken, address _newCollector) external onlyOwner
		delayed(this.setCollector.selector, keccak256(abi.encode(_targetToken, _newCollector)))
	{
		require(_newCollector != address(0), "invalid address");
		address _oldCollector = collectors[_targetToken];
		collectors[_targetToken] = _newCollector;
		emit ChangeCollector(_targetToken, _oldCollector, _newCollector);
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

	/**
	 * @notice Updates the split share for a given target token.
	 *         This is a privileged function.
	 * @param _oldTargetToken The given target token address.
	 * @param _newPercent The new target token split share.
	 */
	function setRewardSplit(address _oldTargetToken, uint256 _newPercent) external onlyOwner
		delayed(this.setRewardSplit.selector, keccak256(abi.encode(_oldTargetToken, _newPercent)))
	{
		uint256 _oldPercent = percents[_oldTargetToken];
		percents[_oldTargetToken] = _newPercent;
		uint256 _accPercent = 0;
		uint256 _index = uint256(-1);
		for (uint256 _i = 0; _i < targetTokens.length; _i++) {
			address _targetToken = targetTokens[_i];
			_accPercent += percents[_targetToken];
			if (_targetToken == _oldTargetToken) _index = _i;
		}
		require(_index < targetTokens.length, "invalid token");
		require(_accPercent <= 1e18, "invalid percent");
		emit ChangeRewardSplit(_oldTargetToken, _oldPercent, _newPercent);
	}

	event AddTargetToken(address indexed _newTargetToken);
	event DropTargetToken(address indexed _oldTargetToken);
	event ChangePsm(address _oldPsm, address _newPsm);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeCollector(address indexed _targetToken, address _oldCollector, address _newCollector);
	event ChangeExchange(address _oldExchange, address _newExchange);
	event ChangeMinimalGulpFactor(uint256 _oldMinimalGulpFactor, uint256 _newMinimalGulpFactor);
	event ChangeRewardSplit(address indexed _oldTargetToken, uint256 _oldPercent, uint256 _newPercent);
}
