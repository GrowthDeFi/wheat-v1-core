// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { WhitelistGuard } from "./WhitelistGuard.sol";
import { DelayedActionGuard } from "./DelayedActionGuard.sol";

import { Transfers } from "./modules/Transfers.sol";

import { CurveSwap, CurveGauge } from "./interop/Curve.sol";
import { PSM } from "./interop/Mor.sol";

contract CurvePeggedToken is ERC20, ReentrancyGuard, /*WhitelistGuard,*/ DelayedActionGuard
{
	uint256 constant DEFAULT_FORCE_GULP_RATIO = 1e15; // 0.1%

	// strategy token configuration
	address private immutable reserveToken;
	address private immutable stakingToken;
	address private immutable liquidityPool;

	// addresses receiving tokens
	address private psm;
	address private treasury;
	address private collector;

	// force gulp ratio
	uint256 private forceGulpRatio = DEFAULT_FORCE_GULP_RATIO;

	constructor (string memory _name, string memory _symbol, uint8 _decimals,
		address _curveSwap, address _curveToken, address _curveGauge,
		address _psm, address _treasury, address _collector)
		ERC20(_name, _symbol) public
	{
		(address _reserveToken, address _stakingToken, address _liquidityPool) = _getTokens(_curveSwap, _curveToken, _curveGauge);
		require(_decimals == ERC20(_stakingToken).decimals(), "invalid decimals");
		_setupDecimals(_decimals);
		reserveToken = _reserveToken;
		stakingToken = _stakingToken;
		liquidityPool = _liquidityPool;
		psm = _psm;
		treasury = _treasury;
		collector = _collector;
		_mint(address(1), 1); // avoids division by zero
	}

	/// @dev Single public function to expose the private state, saves contract space
	function state() external view returns (
		address _reserveToken,
		address _stakingToken,
		address _liquidityPool,
		address _psm,
		address _treasury,
		address _collector,
		uint256 _forceGulpRatio
	)
	{
		return (
			reserveToken,
			stakingToken,
			liquidityPool,
			psm,
			treasury,
			collector,
			forceGulpRatio
		);
	}

	/**
	 * @notice Provides the amount of reserve tokens currently being help by
	 *         this contract.
	 * @return _totalReserve The amount of the reserve token corresponding
	 *                       to this contract's balance.
	 */
	function totalReserve() public view returns (uint256 _totalReserve)
	{
		_totalReserve = Transfers._getBalance(stakingToken);
		if (_totalReserve == uint256(-1)) return _totalReserve;
		return _totalReserve + 1; // avoids division by zero
	}

	/**
	 * @notice Allows for the beforehand calculation of shares to be
	 *         received/minted upon depositing to the contract.
	 *         May not be precise due to gulping which may shift it slightly.
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
	 *         May not be precise due to gulping which may shift it slightly.
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
		_deposit(_amount);
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
		_withdraw(_amount);
		Transfers._pushFunds(reserveToken, _from, _amount);
	}

	/**
	 * Deposits excess reserve into the PSM and sends reward/bonus tokens to the collector.
	 */
	function gulp() external /*onlyEOAorWhitelist*/ nonReentrant
	{
		require(_gulp(), "unavailable");
	}

	/// @dev Actual gulp implementation
	function _gulp() internal returns (bool _success)
	{
		uint256 _balance = _getUnderlyingBalance();
		uint256 _supply = totalSupply();
		if (_balance > _supply) {
			uint256 _excess = _balance - _supply;
			if (psm == address(0)) {
				_mint(treasury, _excess);
			} else {
				_mint(address(this), _excess);
				Transfers._approveFunds(address(this), PSM(psm).gemJoin(), _excess);
				PSM(psm).sellGem(treasury, _excess);
			}
		}
		_claim();
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
		require(_token != stakingToken, "invalid token");
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
	 * @notice Updates the fee collector address used to collect the rewards.
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

	/// @dev Lists the reserve and reward tokens of the liquidity pool
	function _getTokens(address _curveSwap, address _curveToken, address _curveGauge) internal view returns (address _reserveToken, address _stakingToken, address _liquidityPool)
	{
		require(CurveSwap(_curveSwap).lp_token() == _curveToken, "invalid swap");
		require(CurveGauge(_curveGauge).lp_token() == _curveToken, "invalid gauge");
		return (_curveToken, _curveGauge, _curveSwap);
	}

	/// @dev Retrieves the underlying balance on the liquidity pool
	function _getUnderlyingBalance() internal view returns (uint256 _amount)
	{
		return Transfers._getBalance(stakingToken) * CurveSwap(liquidityPool).get_virtual_price() / 1e18;
	}

	/// @dev Performs a deposit into the gauge
	function _deposit(uint256 _amount) internal
	{
		Transfers._approveFunds(reserveToken, stakingToken, _amount);
		CurveGauge(stakingToken).deposit(_amount, address(this), false);
	}

	/// @dev Performs a withdrawal from the gauge
	function _withdraw(uint256 _amount) internal
	{
		CurveGauge(stakingToken).withdraw(_amount, false);
	}

	/// @dev Claims the current pending reward from the gauge to the collector
	function _claim() internal
	{
		CurveGauge(stakingToken).claim_rewards(address(this), collector);
	}

	// ----- END: underlying contract abstraction

	// events emitted by this contract
	event ChangePsm(address _oldPsm, address _newPsm);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeCollector(address _oldCollector, address _newCollector);
	event ChangeForceGulpRatio(uint256 _oldForceGulpRatio, uint256 _newForceGulpRatio);
}

contract CurvePeggedTokenPSMBridge
{
	address public immutable peggedToken;
	uint256 public immutable i;
	address public immutable reserveToken;
	address public immutable underlyingToken;
	address public immutable liquidityPool;
	address public immutable psm;
	address public immutable dai;
	address public immutable gemJoin;

	constructor (address _peggedToken, uint256 _i) public
	{
		(address _reserveToken,, address _liquidityPool, address _psm,,,) = CurvePeggedToken(_peggedToken).state();
		address _underlyingToken = _getUnderlyingToken(_liquidityPool, _i);
		address _dai = PSM(_psm).dai();
		address _gemJoin = PSM(_psm).gemJoin();
		peggedToken = _peggedToken;
		i = _i;
		reserveToken = _reserveToken;
		underlyingToken = _underlyingToken;
		liquidityPool = _liquidityPool;
		psm = _psm;
		dai = _dai;
		gemJoin = _gemJoin;
	}

	function deposit(uint256 _underlyingAmount, uint256 _minDaiAmount, bool _execGulp) external
	{
		Transfers._pullFunds(underlyingToken, msg.sender, _underlyingAmount);
		_deposit(_underlyingAmount);
		uint256 _reserveAmount = Transfers._getBalance(reserveToken);
		Transfers._approveFunds(reserveToken, peggedToken, _reserveAmount);
		CurvePeggedToken(peggedToken).deposit(_reserveAmount, 0, _execGulp);
		uint256 _sharesAmount = Transfers._getBalance(peggedToken);
		Transfers._approveFunds(peggedToken, gemJoin, _sharesAmount);
		PSM(psm).sellGem(address(this), _sharesAmount);
		uint256 _daiAmount = Transfers._getBalance(dai);
		Transfers._pushFunds(dai, msg.sender, _daiAmount);
		require(_daiAmount >= _minDaiAmount, "high slippage");
	}

	function withdraw(uint256 _daiAmount, uint256 _minUnderlyingAmount, bool _execGulp) external
	{
		Transfers._pullFunds(dai, msg.sender, _daiAmount);
		Transfers._approveFunds(dai, psm, _daiAmount);
		uint256 _sharesAmount = _calcWithdrawal(_daiAmount);
		PSM(psm).buyGem(address(this), _sharesAmount);
		CurvePeggedToken(peggedToken).withdraw(_sharesAmount, 0, _execGulp);
		uint256 _reserveAmount = Transfers._getBalance(reserveToken);
		_withdraw(_reserveAmount);
		uint256 _underlyingAmount = Transfers._getBalance(underlyingToken);
		Transfers._pushFunds(underlyingToken, msg.sender, _underlyingAmount);
		require(_underlyingAmount >= _minUnderlyingAmount, "high slippage");
	}

	function _getUnderlyingToken(address _liquidityPool, uint256 _i) internal view returns (address _underlyingToken)
	{
		return CurveSwap(_liquidityPool).underlying_coins(_i);
	}

	function _calcWithdrawal(uint256 _daiAmount) internal view returns (uint256 _sharesAmount)
	{
		uint256 _denominator = 1e18 + PSM(psm).tout();
		return (_daiAmount * 1e18 + (_denominator - 1)) / _denominator;
	}

	/// @dev Adds liquidity to the pool
	function _deposit(uint256 _amount) internal
	{
		Transfers._approveFunds(underlyingToken, liquidityPool, _amount);
		uint256[3] memory _amounts;
		_amounts[i] = _amount;
		CurveSwap(liquidityPool).add_liquidity(_amounts, 0, true);
	}

	/// @dev Removes liquidity from the pool
	function _withdraw(uint256 _amount) internal
	{
		CurveSwap(liquidityPool).remove_liquidity_one_coin(_amount, int128(i), 0, true);
	}
}
