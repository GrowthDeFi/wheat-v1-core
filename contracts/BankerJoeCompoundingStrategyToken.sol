// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IExchange } from "./IExchange.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";
import { DelayedActionGuard } from "./DelayedActionGuard.sol";

import { Transfers } from "./modules/Transfers.sol";
import { Wrapping } from "./modules/Wrapping.sol";

import { Joetroller, JRewardDistributor, JToken } from "./interop/BankerJoe.sol";

/**
 * @notice This contract implements a compounding strategy for BankerJoe.
 *         It basically allows depositing and withdrawing jToken funds and
 *         collects the reward/bonus token (JOE/AVAX). Rewards are converted
 *         to more of the jToken and incorporated into the reserve, after a
 *         performance fee is deducted. The bonus is also deducted in full as
 *         performance fee.
 */
contract BankerJoeCompoundingStrategyToken is ERC20, ReentrancyGuard, /*WhitelistGuard,*/ DelayedActionGuard
{
	using SafeMath for uint256;

	uint256 constant DEFAULT_MINIMAL_GULP_FACTOR = 80e16; // 80%
	uint256 constant DEFAULT_FORCE_GULP_RATIO = 1e15; // 0.1%

	uint256 constant MAXIMUM_PERFORMANCE_FEE = 100e16; // 100%
	uint256 constant DEFAULT_PERFORMANCE_FEE = 50e16; // 50%

	// strategy token configuration
	address private immutable bonusToken;
	address private immutable rewardToken;
	address private immutable routingToken;
	address private immutable reserveToken;

	// addresses receiving tokens
	address private treasury;
	address private collector;

	// exchange contract address
	address private exchange;

	// minimal gulp factor
	uint256 private minimalGulpFactor = DEFAULT_MINIMAL_GULP_FACTOR;

	// force gulp ratio
	uint256 private forceGulpRatio = DEFAULT_FORCE_GULP_RATIO;

	// fee configuration
	uint256 private performanceFee = DEFAULT_PERFORMANCE_FEE;

	/// @dev Single public function to expose the private state, saves contract space
	function state() external view returns (
		address _bonusToken,
		address _rewardToken,
		address _routingToken,
		address _reserveToken,
		address _treasury,
		address _collector,
		address _exchange,
		uint256 _minimalGulpFactor,
		uint256 _forceGulpRatio,
		uint256 _performanceFee
	)
	{
		return (
			bonusToken,
			rewardToken,
			routingToken,
			reserveToken,
			treasury,
			collector,
			exchange,
			minimalGulpFactor,
			forceGulpRatio,
			performanceFee
		);
	}

	/**
	 * @dev Constructor for this strategy contract.
	 * @param _name The ERC-20 token name.
	 * @param _symbol The ERC-20 token symbol.
	 * @param _decimals The ERC-20 token decimals.
	 * @param _reserveToken The jToken address to be used as reserve.
	 * @param _bonusToken The token address to be collected as bonus (WAVAX).
	 * @param _treasury The treasury address used to recover lost funds.
	 * @param _collector The fee collector address to collect the performance fee.
	 * @param _exchange The exchange contract used to convert funds.
	 */
	constructor (string memory _name, string memory _symbol, uint8 _decimals,
		address _reserveToken, address _bonusToken,
		address _treasury, address _collector, address _exchange)
		ERC20(_name, _symbol) public
	{
		_setupDecimals(_decimals);
		(address _routingToken, address _rewardToken) = _getTokens(_reserveToken);
		require(_decimals == ERC20(_reserveToken).decimals(), "invalid decimals");
		bonusToken = _bonusToken;
		rewardToken = _rewardToken;
		routingToken = _routingToken;
		reserveToken = _reserveToken;
		treasury = _treasury;
		collector = _collector;
		exchange = _exchange;
		_mint(address(1), 1); // avoids division by zero
	}

	/**
	 * @notice Provides the amount of reserve tokens currently being help by
	 *         this contract.
	 * @return _totalReserve The amount of the reserve token corresponding
	 *                       to this contract's balance.
	 */
	function totalReserve() public view returns (uint256 _totalReserve)
	{
		_totalReserve = _getReserveAmount();
		if (_totalReserve == uint256(-1)) return _totalReserve;
		return _totalReserve + 1; // avoids division by zero
	}

	/**
	 * @notice Allows for the beforehand calculation of shares to be
	 *         received/minted upon depositing to the contract.
	 * @param _amount The amount of reserve token being deposited.
	 * @return _shares The amount of shares being received.
	 */
	function calcSharesFromAmount(uint256 _amount) external view returns (uint256 _shares)
	{
		return _calcSharesFromAmount(_amount);
	}

	/**
	 * @notice Allows for the beforehand calculation of the amount of
	 *         reserve token to be withdrawn given the desired amount of
	 *         shares.
	 * @param _shares The amount of shares to provide.
	 * @return _amount The amount of the reserve token to be received.
	 */
	function calcAmountFromShares(uint256 _shares) external view returns (uint256 _amount)
	{
		return _calcAmountFromShares(_shares);
	}

	/**
	 * @notice Performs the minting of shares upon the deposit of the
	 *         reserve token. The actual number of shares being minted can
	 *         be calculated using the calcSharesFromAmount() function.
	 * @param _amount The amount of reserve token being deposited in the
	 *                operation.
	 * @param _minShares The minimum number of shares expected to be
	 *                   received in the operation.
	 * @param _execGulp Whether or not gulp() is called prior to the deposit.
	 *                  If the deposit is percentually larger than forceGulpRatio,
	 *                  gulp() execution is compulsory.
	 */
	function deposit(uint256 _amount, uint256 _minShares, bool _execGulp) external /*onlyEOAorWhitelist*/ nonReentrant
	{
		if (_execGulp || _amount.mul(1e18) / totalReserve() > forceGulpRatio) {
			require(_gulp(), "unavailable");
		}
		address _from = msg.sender;
		uint256 _shares = _calcSharesFromAmount(_amount);
		require(_shares >= _minShares, "high slippage");
		Transfers._pullFunds(reserveToken, _from, _amount);
		_mint(_from, _shares);
	}

	/**
	 * @notice Performs the burning of shares upon the withdrawal of
	 *         the reserve token. The actual amount of the reserve token to
	 *         be received can be calculated using the
	 *         calcAmountFromShares() function.
	 * @param _shares The amount of this shares being redeemed in the operation.
	 * @param _minAmount The minimum amount of the reserve token expected
	 *                   to be received in the operation.
	 * @param _execGulp Whether or not gulp() is called prior to the withdrawal.
	 */
	function withdraw(uint256 _shares, uint256 _minAmount, bool _execGulp) external /*onlyEOAorWhitelist*/ nonReentrant
	{
		if (_execGulp) {
			require(_gulp(), "unavailable");
		}
		address _from = msg.sender;
		uint256 _amount = _calcAmountFromShares(_shares);
		require(_amount >= _minAmount, "high slippage");
		_burn(_from, _shares);
		Transfers._pushFunds(reserveToken, _from, _amount);
	}

	/**
	 * Performs the conversion of the accumulated reward token into more of
	 * the reserve token. This function allows the compounding of rewards.
	 * Part of the reward accumulated is collected and sent to the fee collector
	 * contract as performance fee.
	 */
	function gulp() external /*onlyEOAorWhitelist*/ nonReentrant
	{
		require(_gulp(), "unavailable");
	}

	/// @dev Actual gulp implementation
	function _gulp() internal returns (bool _success)
	{
		_claim();
		{
			uint256 _totalBonus = Transfers._getBalance(bonusToken);
			Transfers._pushFunds(bonusToken, collector, _totalBonus);
		}
		{
			uint256 _totalReward = Transfers._getBalance(rewardToken);
			if (_totalReward == 0) return true;
			uint256 _feeReward = _totalReward.mul(performanceFee) / 1e18;
			Transfers._pushFunds(rewardToken, collector, _feeReward);
		}
		if (rewardToken != routingToken) {
			require(exchange != address(0), "exchange not set");
			uint256 _totalReward = Transfers._getBalance(rewardToken);
			uint256 _factor = IExchange(exchange).oracleAveragePriceFactorFromInput(rewardToken, routingToken, _totalReward);
			if (_factor < minimalGulpFactor) return false;
			Transfers._approveFunds(rewardToken, exchange, _totalReward);
			IExchange(exchange).convertFundsFromInput(rewardToken, routingToken, _totalReward, 1);
		}
		uint256 _totalBalance = Transfers._getBalance(routingToken);
		_deposit(_totalBalance);
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
		// delayed(this.recoverLostFunds.selector, keccak256(abi.encode(_token)))
	{
		require(_token != reserveToken, "invalid token");
		require(_token != routingToken, "invalid token");
		require(_token != rewardToken, "invalid token");
		require(_token != bonusToken, "invalid token");
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

	/**
	 * @notice Updates the force gulp ratio. Any deposit larger then the
	 *         ratio, relative to the reserve, forces gulp.
	 *         This is a privileged function.
	 * @param _newForceGulpRatio The new force gulp ratio.
	 */
	function setForceGulpRatio(uint256 _newForceGulpRatio) external onlyOwner
		delayed(this.setForceGulpRatio.selector, keccak256(abi.encode(_newForceGulpRatio)))
	{
		require(_newForceGulpRatio <= 1e18, "invalid rate");
		uint256 _oldForceGulpRatio = forceGulpRatio;
		forceGulpRatio = _newForceGulpRatio;
		emit ChangeForceGulpRatio(_oldForceGulpRatio, _newForceGulpRatio);
	}

	/**
	 * @notice Updates the performance fee rate.
	 *         This is a privileged function.
	 * @param _newPerformanceFee The new performance fee rate.
	 */
	function setPerformanceFee(uint256 _newPerformanceFee) external onlyOwner
		delayed(this.setPerformanceFee.selector, keccak256(abi.encode(_newPerformanceFee)))
	{
		require(_newPerformanceFee <= MAXIMUM_PERFORMANCE_FEE, "invalid rate");
		uint256 _oldPerformanceFee = performanceFee;
		performanceFee = _newPerformanceFee;
		emit ChangePerformanceFee(_oldPerformanceFee, _newPerformanceFee);
	}

	/// @dev Calculation of shares from amount given the share price (ratio between reserve and supply)
	function _calcSharesFromAmount(uint256 _amount) internal view returns (uint256 _shares)
	{
		return _amount.mul(totalSupply()) / totalReserve();
	}

	/// @dev Calculation of amount from shares given the share price (ratio between reserve and supply)
	function _calcAmountFromShares(uint256 _shares) internal view returns (uint256 _amount)
	{
		return _shares.mul(totalReserve()) / totalSupply();
	}

	// ----- BEGIN: underlying contract abstraction

	/// @dev Lists the reserve and reward tokens of the lending pool
	function _getTokens(address _reserveToken) internal view returns (address _routingToken, address _rewardToken)
	{
		address _joetroller = JToken(_reserveToken).joetroller();
		address _distributor = Joetroller(_joetroller).rewardDistributor();
		_routingToken = JToken(_reserveToken).underlying();
		_rewardToken = JRewardDistributor(_distributor).joeAddress();
		return (_routingToken, _rewardToken);
	}

	/// @dev Retrieves the current pending reward for the lending pool
	function _getPendingReward() internal view returns (uint256 _pendingReward, uint256 _pendingBonus)
	{
		address _joetroller = JToken(reserveToken).joetroller();
		address _distributor = Joetroller(_joetroller).rewardDistributor();
		_pendingReward = JRewardDistributor(_distributor).rewardAccrued(0, address(this));
		_pendingBonus = JRewardDistributor(_distributor).rewardAccrued(1, address(this));
		return (_pendingReward, _pendingBonus);
	}

	/// @dev Retrieves the deposited reserve for the lengding pool
	function _getReserveAmount() internal view returns (uint256 _reserveAmount)
	{
		return Transfers._getBalance(reserveToken);
	}

	/// @dev Performs a deposit into the lending pool
	function _deposit(uint256 _amount) internal
	{
		if (routingToken == bonusToken) {
			Wrapping._unwrap(bonusToken, _amount);
			JToken(reserveToken).mint{value: _amount}();
		} else {
			Transfers._approveFunds(routingToken, reserveToken, _amount);
			uint256 _errorCode = JToken(reserveToken).mint(_amount);
			require(_errorCode == 0, "lend unavailable");
		}
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
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeCollector(address _oldCollector, address _newCollector);
	event ChangeExchange(address _oldExchange, address _newExchange);
	event ChangeMinimalGulpFactor(uint256 _oldMinimalGulpFactor, uint256 _newMinimalGulpFactor);
	event ChangeForceGulpRatio(uint256 _oldForceGulpRatio, uint256 _newForceGulpRatio);
	event ChangePerformanceFee(uint256 _oldPerformanceFee, uint256 _newPerformanceFee);
}

contract BakerJoeCompoundingStrategyBridge
{
	using SafeMath for uint256;

	address payable public immutable strategy;
	address public immutable bonusToken;
	address public immutable routingToken;
	address public immutable reserveToken;

	constructor (address payable _strategy) public
	{
		(address _bonusToken,,address _routingToken,address _reserveToken,,,,,,) = BankerJoeCompoundingStrategyToken(_strategy).state();
		strategy = _strategy;
		bonusToken = _bonusToken;
		routingToken = _routingToken;
		reserveToken = _reserveToken;
	}

	function calcSharesFromAmount(uint256 _amount) external view returns (uint256 _shares)
	{
		uint256 _value = _calcDepositAmount(_amount);
		return BankerJoeCompoundingStrategyToken(strategy).calcSharesFromAmount(_value);
	}

	function calcAmountFromShares(uint256 _shares) external view returns (uint256 _amount)
	{
		uint256 _value = BankerJoeCompoundingStrategyToken(strategy).calcAmountFromShares(_shares);
		return _calcWithdrawalAmount(_value);
	}

	function deposit(uint256 _amount, uint256 _minShares, bool _execGulp) external
	{
		address _from = msg.sender;
		Transfers._pullFunds(routingToken, _from, _amount);
		_deposit(_amount);
		uint256 _value = Transfers._getBalance(reserveToken);
		Transfers._approveFunds(reserveToken, strategy, _value);
		BankerJoeCompoundingStrategyToken(strategy).deposit(_value, 0, _execGulp);
		uint256 _shares = Transfers._getBalance(strategy);
		require(_shares >= _minShares, "high slippage");
		Transfers._pushFunds(strategy, _from, _shares);
	}

	function withdraw(uint256 _shares, uint256 _minAmount, bool _execGulp) external
	{
		address _from = msg.sender;
		Transfers._pullFunds(strategy, _from, _shares);
		BankerJoeCompoundingStrategyToken(strategy).withdraw(_shares, 0, _execGulp);
		uint256 _value = Transfers._getBalance(reserveToken);
		_withdraw(_value);
		uint256 _amount = Transfers._getBalance(routingToken);
		require(_amount >= _minAmount, "high slippage");
		Transfers._pushFunds(routingToken, _from, _amount);
	}

	// ----- BEGIN: underlying contract abstraction

	/// @dev Calculates the amount of jToken to be minted from underlying
	function _calcDepositAmount(uint256 _amount) internal view returns (uint256 _value)
	{
		uint256 _exchangeRate = JToken(reserveToken).exchangeRateStored();
		return _amount.mul(1e18).div(_exchangeRate);
	}

	/// @dev Calculates the amount of underlying upon redeemeing jToken
	function _calcWithdrawalAmount(uint256 _value) internal view returns (uint256 _amount)
	{
		uint256 _exchangeRate = JToken(reserveToken).exchangeRateStored();
		return _value.mul(_exchangeRate).div(1e18);
	}

	/// @dev Performs a deposit into the lending pool
	function _deposit(uint256 _amount) internal
	{
		if (routingToken == bonusToken) {
			Wrapping._unwrap(bonusToken, _amount);
			JToken(reserveToken).mint{value: _amount}();
		} else {
			Transfers._approveFunds(routingToken, reserveToken, _amount);
			uint256 _errorCode = JToken(reserveToken).mint(_amount);
			require(_errorCode == 0, "lend unavailable");
		}
	}

	/// @dev Performs a withdrawal from the lending pool
	function _withdraw(uint256 _amount) internal
	{
		uint256 _errorCode = JToken(reserveToken).redeem(_amount);
		require(_errorCode == 0, "redeem unavailable");
		if (routingToken == bonusToken) {
			Wrapping._wrap(bonusToken, _amount);
		}
	}

	// ----- END: underlying contract abstraction

	/// @dev Allows for receiving the native token
	receive() external payable
	{
	}
}
