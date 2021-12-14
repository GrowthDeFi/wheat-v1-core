// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IExchange } from "./IExchange.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";
import { DelayedActionGuard } from "./DelayedActionGuard.sol";

import { Transfers } from "./modules/Transfers.sol";

import { MasterChef } from "./interop/MasterChef.sol";
import { Pair } from "./interop/UniswapV2.sol";

/**
 * @notice This contract implements a compounding strategy for ApeSwap MasterChef.
 *         It basically deposits and withdraws funds from MasterChef and collects the
 *         reward token (CAKE). The compounding happens by calling the gulp function;
 *         it converts the reward into more funds which are further deposited into
 *         MasterChef. A performance fee is deducted from the converted funds and sent
 *         to the fee collector contract. This contract also allows for charging a
 *         deposit fee deducted from deposited funds.
 */
contract ApeSwapCompoundingStrategyToken is ERC20, ReentrancyGuard, /*WhitelistGuard,*/ DelayedActionGuard
{
	using SafeMath for uint256;

	uint256 constant DEFAULT_MINIMAL_GULP_FACTOR = 80e16; // 80%
	uint256 constant DEFAULT_FORCE_GULP_RATIO = 1e15; // 0.1%

	uint256 constant MAXIMUM_PERFORMANCE_FEE = 50e16; // 50%
	uint256 constant DEFAULT_PERFORMANCE_FEE = 5e16; // 5%

	uint256 constant MAXIMUM_BURNING_TAX = 20e16; // 20%
	uint256 constant DEFAULT_BURNING_TAX = 2e16; // 2%

	// dead address to receive "burnt" tokens
	address constant public FURNACE = 0x000000000000000000000000000000000000dEaD;

	// underlying contract configuration
	address private immutable masterChef;
	uint256 private immutable pid;

	// strategy token configuration
	address private immutable rewardToken;
	address private immutable routingToken;
	address private immutable reserveToken;

	// addresses receiving tokens
	// address private treasury;
	address private collector;

	// exchange contract address
	address private exchange;

	// minimal gulp factor
	uint256 private minimalGulpFactor = DEFAULT_MINIMAL_GULP_FACTOR;

	// force gulp ratio
	uint256 private forceGulpRatio = DEFAULT_FORCE_GULP_RATIO;

	// fee configuration
	uint256 private performanceFee = DEFAULT_PERFORMANCE_FEE;
	uint256 private burningTax = DEFAULT_BURNING_TAX;

	// emergency mode flag
	bool private emergencyMode;

	/// @dev Single public function to expose the private state, saves contract space
	function state() external view returns (
		address _masterChef,
		uint256 _pid,
		address _rewardToken,
		address _routingToken,
		address _reserveToken,
		// address _treasury,
		address _collector,
		address _exchange,
		uint256 _minimalGulpFactor,
		uint256 _forceGulpRatio,
		uint256 _performanceFee,
		uint256 _burningTax,
		bool _emergencyMode
	)
	{
		return (
			masterChef,
			pid,
			rewardToken,
			routingToken,
			reserveToken,
			// treasury,
			collector,
			exchange,
			minimalGulpFactor,
			forceGulpRatio,
			performanceFee,
			burningTax,
			emergencyMode
		);
	}

	/**
	 * @dev Constructor for this strategy contract.
	 * @param _name The ERC-20 token name.
	 * @param _symbol The ERC-20 token symbol.
	 * @param _decimals The ERC-20 token decimals.
	 * @param _masterChef The MasterChef contract address.
	 * @param _pid The MasterChef Pool ID (pid).
	 * @param _routingToken The ERC-20 token address to be used as routing
	 *                      token, must be either the reserve token itself
	 *                      or one of the tokens that make up a liquidity pool.
	 * @param _treasury The treasury address used to recover lost funds.
	 * @param _collector The fee collector address to collect the performance fee.
	 * @param _exchange The exchange contract used to convert funds.
	 */
	constructor (string memory _name, string memory _symbol, uint8 _decimals,
		address _masterChef, uint256 _pid, address _routingToken,
		address _treasury, address _collector, address _exchange)
		ERC20(_name, _symbol) public
	{
		_setupDecimals(_decimals);
		(address _reserveToken, address _rewardToken) = _getTokens(_masterChef, _pid);
		require(_routingToken == _reserveToken || _routingToken == Pair(_reserveToken).token0() || _routingToken == Pair(_reserveToken).token1(), "invalid token");
		masterChef = _masterChef;
		pid = _pid;
		rewardToken = _rewardToken;
		routingToken = _routingToken;
		reserveToken = _reserveToken;
		/*treasury =*/ _treasury;
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
		_totalReserve = emergencyMode ? Transfers._getBalance(reserveToken) : _getReserveAmount();
		if (_totalReserve == uint256(-1)) return _totalReserve;
		return _totalReserve + 1; // avoids division by zero
	}

	/**
	 * @notice Allows for the beforehand calculation of shares to be
	 *         received/minted upon depositing to the contract.
	 * @param _amount The amount of reserve token being deposited.
	 * @return _shares The net amount of shares being received.
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
	 * @notice Allows for the beforehand calculation of the amount of
	 *         reward token to be collected as performance fee on the next
	 *         gulp call.
	 * @return _feeReward The amount of the reward token to be collected.
	 */
	/*
	function pendingPerformanceFee() external view returns (uint256 _feeReward)
	{
		uint256 _pendingReward = _getPendingReward();
		uint256 _balanceReward = Transfers._getBalance(rewardToken);
		uint256 _totalReward = _pendingReward.add(_balanceReward);
		_feeReward = _totalReward.mul(performanceFee) / 1e18;
		return _feeReward;
	}
	*/

	/**
	 * @notice Allows for the beforehand calculation of the amount of
	 *         reward token to be burnt as tax on the next gulp call.
	 * @return _taxReward The amount of the reward token to be burnt.
	 */
	/*
	function pendingBurningTax() external view returns (uint256 _taxReward)
	{
		uint256 _pendingReward = _getPendingReward();
		uint256 _balanceReward = Transfers._getBalance(rewardToken);
		uint256 _totalReward = _pendingReward.add(_balanceReward);
		_taxReward = _totalReward.mul(burningTax) / 1e18;
		return _taxReward;
	}
	*/

	/**
	 * @notice Allows for the beforehand calculation of the amount of
	 *         reserve token, converted from the reward token accumulated,
	 *         to be incorporated into the reserve on the next gulp call.
	 * @return _rewardAmount The amount of the reserve token to be collected.
	 */
	/*
	function pendingReward() external view returns (uint256 _rewardAmount)
	{
		uint256 _pendingReward = _getPendingReward();
		uint256 _balanceReward = Transfers._getBalance(rewardToken);
		uint256 _totalReward = _pendingReward.add(_balanceReward);
		uint256 _feeReward = _totalReward.mul(performanceFee) / 1e18;
		uint256 _taxReward = _totalReward.mul(burningTax) / 1e18;
		uint256 _netReward = _totalReward - (_feeReward + _taxReward);
		uint256 _totalRouting = _netReward;
		if (rewardToken != routingToken) {
			require(exchange != address(0), "exchange not set");
			_totalRouting = IExchange(exchange).calcConversionFromInput(rewardToken, routingToken, _netReward);
		}
		uint256 _totalBalance = _totalRouting;
		if (routingToken != reserveToken) {
			require(exchange != address(0), "exchange not set");
			_totalBalance = IExchange(exchange).calcJoinPoolFromInput(reserveToken, routingToken, _totalRouting);
		}
		return _totalBalance;
	}
	*/

	/**
	 * @notice Performs the minting of shares upon the deposit of the
	 *         reserve token. The actual number of shares being minted can
	 *         be calculated using the calcSharesFromAmount function.
	 *         In every deposit, a portion of the shares is retained in
	 *         terms of deposit fee and sent to the dev address.
	 * @param _amount The amount of reserve token being deposited in the
	 *                operation.
	 * @param _minShares The minimum number of shares expected to be
	 *                   received in the operation.
	 */
	function deposit(uint256 _amount, uint256 _minShares, bool _execGulp) external /*onlyEOAorWhitelist*/ nonReentrant
	{
		require(!emergencyMode, "not allowed");
		if (_execGulp || _amount.mul(1e18) / totalReserve() > forceGulpRatio) {
			require(_gulp(), "unavailable");
		}
		address _from = msg.sender;
		uint256 _shares = _calcSharesFromAmount(_amount);
		require(_shares >= _minShares, "high slippage");
		Transfers._pullFunds(reserveToken, _from, _amount);
		_deposit(_amount);
		_mint(_from, _shares);
	}

	/**
	 * @notice Performs the burning of shares upon the withdrawal of
	 *         the reserve token. The actual amount of the reserve token to
	 *         be received can be calculated using the
	 *         calcAmountFromShares function.
	 * @param _shares The amount of this shares being redeemed in the operation.
	 * @param _minAmount The minimum amount of the reserve token expected
	 *                   to be received in the operation.
	 */
	function withdraw(uint256 _shares, uint256 _minAmount, bool _execGulp) external /*onlyEOAorWhitelist*/ nonReentrant
	{
		if (_execGulp) {
			require(!emergencyMode, "not allowed");
			require(_gulp(), "unavailable");
		}
		address _from = msg.sender;
		uint256 _amount = _calcAmountFromShares(_shares);
		require(_amount >= _minAmount, "high slippage");
		_burn(_from, _shares);
		if (!emergencyMode) {
			_withdraw(_amount);
		}
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
		require(!emergencyMode, "not allowed");
		require(_gulp(), "unavailable");
	}

	/// @dev Actual gulp implementation
	function _gulp() internal returns (bool _success)
	{
		uint256 _pendingReward = _getPendingReward();
		if (_pendingReward > 0) {
			_withdraw(0);
		}
		{
			uint256 _totalReward = Transfers._getBalance(rewardToken);
			if (_totalReward == 0) return true;
			uint256 _feeReward = _totalReward.mul(performanceFee) / 1e18;
			Transfers._pushFunds(rewardToken, collector, _feeReward);
			uint256 _taxReward = _totalReward.mul(burningTax) / 1e18;
			Transfers._pushFunds(rewardToken, FURNACE, _taxReward);
		}
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
		return true;
	}

	/**
	 * @notice Allows withdrawing funds from the underlying protocol using
	 *         the emergency withdrawal functionality. It halts the
	 *         contract for deposits and gulp, only allowing withdrawals
	 *         to take place.
	 *         This is a privileged function.
	 */
	function enterEmergencyMode() external onlyOwner
	{
		emergencyMode = true;
		_emergencyWithdraw();
	}

	/**
	 * @notice Allows the recovery of tokens sent by mistake to this
	 *         contract, excluding tokens relevant to its operations.
	 *         The full balance is sent to the treasury address.
	 *         This is a privileged function.
	 * @param _token The address of the token to be recovered.
	 */
	/*
	function recoverLostFunds(address _token) external onlyOwner nonReentrant
		delayed(this.recoverLostFunds.selector, keccak256(abi.encode(_token)))
	{
		require(_token != reserveToken, "invalid token");
		require(_token != routingToken, "invalid token");
		require(_token != rewardToken, "invalid token");
		uint256 _balance = Transfers._getBalance(_token);
		Transfers._pushFunds(_token, treasury, _balance);
	}
	*/

	/**
	 * @notice Updates the treasury address used to recover lost funds.
	 *         This is a privileged function.
	 * @param _newTreasury The new treasury address.
	 */
	/*
	function setTreasury(address _newTreasury) external onlyOwner
		delayed(this.setTreasury.selector, keccak256(abi.encode(_newTreasury)))
	{
		require(_newTreasury != address(0), "invalid address");
		address _oldTreasury = treasury;
		treasury = _newTreasury;
		emit ChangeTreasury(_oldTreasury, _newTreasury);
	}
	*/

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

	/**
	 * @notice Updates the burning tax rate.
	 *         This is a privileged function.
	 * @param _newBurningTax The new burning tax rate.
	 */
	function setBurningTax(uint256 _newBurningTax) external onlyOwner
		delayed(this.setBurningTax.selector, keccak256(abi.encode(_newBurningTax)))
	{
		require(_newBurningTax <= MAXIMUM_BURNING_TAX, "invalid rate");
		uint256 _oldBurningTax = burningTax;
		burningTax = _newBurningTax;
		emit ChangeBurningTax(_oldBurningTax, _newBurningTax);
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
	// event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeCollector(address _oldCollector, address _newCollector);
	event ChangeExchange(address _oldExchange, address _newExchange);
	event ChangeMinimalGulpFactor(uint256 _oldMinimalGulpFactor, uint256 _newMinimalGulpFactor);
	event ChangeForceGulpRatio(uint256 _oldForceGulpRatio, uint256 _newForceGulpRatio);
	event ChangeDepositFee(uint256 _oldDepositFee, uint256 _newDepositFee);
	event ChangePerformanceFee(uint256 _oldPerformanceFee, uint256 _newPerformanceFee);
	event ChangeBurningTax(uint256 _oldBurningTax, uint256 _newBurningTax);
}