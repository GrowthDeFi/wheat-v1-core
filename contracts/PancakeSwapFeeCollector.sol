// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IExchange } from "./IExchange.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";
import { DelayedActionGuard } from "./DelayedActionGuard.sol";

import { Transfers } from "./modules/Transfers.sol";

import { MasterChef } from "./interop/MasterChef.sol";
import { Pair } from "./interop/UniswapV2.sol";

/**
 * @notice This contract implements a fee collector strategy for PancakeSwap MasterChef.
 *         It accumulates the reward token sent from strategies (CAKE) and converts it
 *         into reserve funds which are deposited into MasterChef. The rewards accumulated
 *         on MasterChed from reserve funds are, on the other hand, collected and sent to
 *         the buyback contract. These operations happen via the gulp function.
 */
contract PancakeSwapFeeCollector is ReentrancyGuard, /*WhitelistGuard,*/ DelayedActionGuard
{
	uint256 constant DEFAULT_MINIMAL_GULP_FACTOR = 99e16; // 99%

	// underlying contract configuration
	address private immutable masterChef;
	uint256 private immutable pid;

	// strategy token configuration
	address public immutable rewardToken;
	address public immutable routingToken;
	address public immutable reserveToken;

	// addresses receiving tokens
	address public treasury;
	address public buyback;

	// exchange contract address
	address public exchange;

	// minimal gulp factor
	uint256 public minimalGulpFactor = DEFAULT_MINIMAL_GULP_FACTOR;

	/**
	 * @dev Constructor for this fee collector contract.
	 * @param _masterChef The MasterChef contract address.
	 * @param _pid The MasterChef Pool ID (pid).
	 * @param _routingToken The ERC-20 token address to be used as routing
	 *                      token, must be either the reserve token itself
	 *                      or one of the tokens that make up a liquidity pool.
	 * @param _treasury The treasury address used to recover lost funds.
	 * @param _buyback The buyback contract address to send collected rewards.
	 * @param _exchange The exchange contract used to convert funds.
	 */
	constructor (address _masterChef, uint256 _pid, address _routingToken,
		address _treasury, address _buyback, address _exchange) public
	{
		(address _reserveToken, address _rewardToken) = _getTokens(_masterChef, _pid);
		require(_routingToken == _reserveToken || _routingToken == Pair(_reserveToken).token0() || _routingToken == Pair(_reserveToken).token1(), "invalid token");
		masterChef = _masterChef;
		pid = _pid;
		rewardToken = _rewardToken;
		routingToken = _routingToken;
		reserveToken = _reserveToken;
		treasury = _treasury;
		buyback = _buyback;
		exchange = _exchange;
	}

	/**
	 * @notice Allows for the beforehand calculation of the amount of
	 *         reserve token, converted from the reward token deposited
	 *         from strategies, to be incorporated into the reserve on the
	 *         next gulp call.
	 * @return _depositAmount The amount of the reserve token to be deposited.
	 */
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

	/**
	 * @notice Allows for the beforehand calculation of the amount of
	 *         reward token currently pending for collection.
	 * @return _pendingReward The amount of the reward token pending collection.
	 */
	function pendingReward() external view returns (uint256 _pendingReward)
	{
		return _getPendingReward();
	}

	/**
	 * Performs the conversion of the reward token received from strategies
	 * into the reserve token. Also collects the rewards from its deposits
	 * and sent it to the buyback contract.
	 */
	function gulp() external /*onlyEOAorWhitelist*/ nonReentrant
	{
		require(_gulp(), "gulp unavailable");
	}

	/// @dev Actual gulp implementation
	function _gulp() internal returns (bool _success)
	{
		if (rewardToken != routingToken) {
			require(exchange != address(0), "exchange not set");
			uint256 _totalReward = Transfers._getBalance(rewardToken);
			uint256 _factor = IExchange(exchange).oracleAveragePriceFactorFromInput(rewardToken, routingToken, _totalReward);
			if (_factor < minimalGulpFactor) return false;
			Transfers._approveFunds(rewardToken, exchange, _totalReward);
			IExchange(exchange).convertFundsFromInput(rewardToken, routingToken, _totalReward, 1);
		}
		if (routingToken != reserveToken) {
			require(exchange != address(0), "exchange not set");
			uint256 _totalRouting = Transfers._getBalance(routingToken);
			uint256 _factor = IExchange(exchange).oraclePoolAveragePriceFactorFromInput(reserveToken, routingToken, _totalRouting);
			if (_factor < minimalGulpFactor || _factor > 2e18 - minimalGulpFactor) return false;
			Transfers._approveFunds(routingToken, exchange, _totalRouting);
			IExchange(exchange).joinPoolFromInput(reserveToken, routingToken, _totalRouting, 1);
		}
		uint256 _totalBalance = Transfers._getBalance(reserveToken);
		_deposit(_totalBalance);
		uint256 _totalReward = Transfers._getBalance(rewardToken);
		Transfers._pushFunds(rewardToken, buyback, _totalReward);
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
		require(_token != routingToken, "invalid token");
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
	function _getTokens(address _masterChef, uint256 _pid) internal view returns (address _reserveToken, address _rewardToken)
	{
		uint256 _poolLength = MasterChef(_masterChef).poolLength();
		require(_pid < _poolLength, "invalid pid");
		(_reserveToken,,,) = MasterChef(_masterChef).poolInfo(_pid);
		_rewardToken = MasterChef(_masterChef).cake();
		return (_reserveToken, _rewardToken);
	}

	/// @dev Retrieves the current pending reward for the MasterChef pool
	function _getPendingReward() internal view returns (uint256 _pendingReward)
	{
		return MasterChef(masterChef).pendingCake(pid, address(this));
	}

	/// @dev Retrieves the deposited reserve for the MasterChef pool
	function _getReserveAmount() internal view returns (uint256 _reserveAmount)
	{
		(_reserveAmount,) = MasterChef(masterChef).userInfo(pid, address(this));
		return _reserveAmount;
	}

	/// @dev Performs a deposit into the MasterChef pool
	function _deposit(uint256 _amount) internal
	{
		Transfers._approveFunds(reserveToken, masterChef, _amount);
		if (pid == 0) {
			MasterChef(masterChef).enterStaking(_amount);
		} else {
			MasterChef(masterChef).deposit(pid, _amount);
		}
	}

	/// @dev Performs an withdrawal from the MasterChef pool
	function _withdraw(uint256 _amount) internal
	{
		if (pid == 0) {
			MasterChef(masterChef).leaveStaking(_amount);
		} else {
			MasterChef(masterChef).withdraw(pid, _amount);
		}
	}

	/// @dev Performs an emergency withdrawal from the MasterChef pool
	function _emergencyWithdraw() internal
	{
		MasterChef(masterChef).emergencyWithdraw(pid);
	}

	// ----- END: underlying contract abstraction

	// events emitted by this contract
	event ChangeBuyback(address _oldBuyback, address _newBuyback);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeExchange(address _oldExchange, address _newExchange);
	event ChangeMinimalGulpFactor(uint256 _oldMinimalGulpFactor, uint256 _newMinimalGulpFactor);
	event Migrate(address indexed _migrationRecipient);
}
