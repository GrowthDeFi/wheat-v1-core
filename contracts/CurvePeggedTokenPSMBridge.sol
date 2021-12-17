// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { CurvePeggedToken } from "./CurvePeggedToken.sol";
import { DelayedActionGuard } from "./DelayedActionGuard.sol";

import { Transfers } from "./modules/Transfers.sol";

import { CurveSwap } from "./interop/Curve.sol";
import { PSM } from "./interop/Mor.sol";

contract CurvePeggedTokenPSMBridge is ReentrancyGuard, DelayedActionGuard
{
	using SafeMath for uint256;

	uint256 constant DEFAULT_SLIPPAGE = 1e16; // 1%

	// adapter token configuration
	address public immutable peggedToken;
	uint256 public immutable i;
	address public immutable reserveToken;
	address public immutable underlyingToken;
	address public immutable liquidityPool;

	// addresses receiving tokens
	address public psm;
	address public treasury;

	// tolerable slippage
	uint256 public slippage = DEFAULT_SLIPPAGE;

	constructor (address _peggedToken, uint256 _i) public
	{
		(address _reserveToken,, address _liquidityPool, address _psm, address _treasury,,) = CurvePeggedToken(_peggedToken).state();
		address _underlyingToken = _getUnderlyingToken(_liquidityPool, _i);
		peggedToken = _peggedToken;
		i = _i;
		reserveToken = _reserveToken;
		underlyingToken = _underlyingToken;
		liquidityPool = _liquidityPool;
		psm = _psm;
		treasury = _treasury;
	}

	function deposit(uint256 _underlyingAmount) external
	{
		deposit(_underlyingAmount, _underlyingAmount.mul(100e16 - slippage) / 100e16, false);
	}

	function withdraw(uint256 _daiAmount) external
	{
		withdraw(_daiAmount, _daiAmount.mul(100e16 - slippage) / 100e16, true);
	}

	function deposit(uint256 _underlyingAmount, uint256 _minDaiAmount, bool _execGulp) public nonReentrant
	{
		Transfers._pullFunds(underlyingToken, msg.sender, _underlyingAmount);
		_deposit(_underlyingAmount);
		uint256 _reserveAmount = Transfers._getBalance(reserveToken);
		Transfers._approveFunds(reserveToken, peggedToken, _reserveAmount);
		CurvePeggedToken(peggedToken).deposit(_reserveAmount, 0, _execGulp);
		uint256 _sharesAmount = Transfers._getBalance(peggedToken);
		Transfers._approveFunds(peggedToken, PSM(psm).gemJoin(), _sharesAmount);
		PSM(psm).sellGem(address(this), _sharesAmount);
		address _dai = PSM(psm).dai();
		uint256 _daiAmount = Transfers._getBalance(_dai);
		Transfers._pushFunds(_dai, msg.sender, _daiAmount);
		require(_daiAmount >= _minDaiAmount, "high slippage");
	}

	function withdraw(uint256 _daiAmount, uint256 _minUnderlyingAmount, bool _execGulp) public nonReentrant
	{
		address _dai = PSM(psm).dai();
		Transfers._pullFunds(_dai, msg.sender, _daiAmount);
		Transfers._approveFunds(_dai, psm, _daiAmount);
		uint256 _sharesAmount = _calcPsmWithdrawal(_daiAmount);
		PSM(psm).buyGem(address(this), _sharesAmount);
		CurvePeggedToken(peggedToken).withdraw(_sharesAmount, 0, _execGulp);
		uint256 _reserveAmount = Transfers._getBalance(reserveToken);
		_withdraw(_reserveAmount);
		uint256 _underlyingAmount = Transfers._getBalance(underlyingToken);
		Transfers._pushFunds(underlyingToken, msg.sender, _underlyingAmount);
		require(_underlyingAmount >= _minUnderlyingAmount, "high slippage");
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
	 * @notice Updates the peg stability module address used to collect
	 *         lending fees. This is a privileged function.
	 * @param _newPsm The new peg stability module address.
	 */
	function setPsm(address _newPsm) external onlyOwner
		delayed(this.setPsm.selector, keccak256(abi.encode(_newPsm)))
	{
		require(_newPsm != address(0), "invalid address");
		address _oldPsm = psm;
		psm = _newPsm;
		emit ChangePsm(_oldPsm, _newPsm);
	}

	function setSlippage(uint256 _newSlippage) external onlyOwner
		delayed(this.setSlippage.selector, keccak256(abi.encode(_newSlippage)))
	{
		require(_newSlippage <= 1e18, "invalid rate");
		uint256 _oldSlippage = slippage;
		slippage = _oldSlippage;
		emit ChangeSlippage(_oldSlippage, _newSlippage);
	}

	// ----- BEGIN: underlying contract abstraction

	function _getUnderlyingToken(address _liquidityPool, uint256 _i) internal view returns (address _underlyingToken)
	{
		return CurveSwap(_liquidityPool).underlying_coins(_i);
	}

	function _calcPsmWithdrawal(uint256 _daiAmount) internal view returns (uint256 _sharesAmount)
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

	// ----- END: underlying contract abstraction

	event ChangePsm(address _oldPsm, address _newPsm);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeSlippage(uint256 _oldSlippage, uint256 _newSlippage);
}
