// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { CurvePeggedToken } from "./CurvePeggedToken.sol";
import { DelayedActionGuard } from "./DelayedActionGuard.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";

import { Transfers } from "./modules/Transfers.sol";

import { CurveSwap } from "./interop/Curve.sol";
import { PSM } from "./interop/Mor.sol";

// this contract is to work around a bug when injecting funds into the PSM in the original code
contract CurvePSMInjector is ReentrancyGuard, /*WhitelistGuard,*/ DelayedActionGuard
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
	uint256 private slippage = DEFAULT_SLIPPAGE;

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

	function gulp() external /*onlyEOAorWhitelist*/ nonReentrant
	{
		require(_gulp(), "unavailable");
	}

	function _gulp() internal returns (bool _success)
	{
		uint256 _underlyingAmount = Transfers._getBalance(underlyingToken);
		if (_underlyingAmount > 0) {
			_deposit(_underlyingAmount);
			uint256 _reserveAmount = Transfers._getBalance(reserveToken);
			Transfers._approveFunds(reserveToken, peggedToken, _reserveAmount);
			CurvePeggedToken(peggedToken).deposit(_reserveAmount, _underlyingAmount.mul(100e16 - slippage) / 100e16, false);
		}
		uint256 _peggedAmount = Transfers._getBalance(peggedToken);
		if (_peggedAmount > 0) {
			if (psm == address(0)) {
				Transfers._pushFunds(peggedToken, treasury, _peggedAmount);
			} else {
				Transfers._approveFunds(peggedToken, PSM(psm).gemJoin(), _peggedAmount);
				PSM(psm).sellGem(treasury, _peggedAmount);
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
		require(_token != underlyingToken, "invalid token");
		require(_token != peggedToken, "invalid token");
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

	/// @dev Adds liquidity to the pool
	function _deposit(uint256 _amount) internal
	{
		Transfers._approveFunds(underlyingToken, liquidityPool, _amount);
		uint256[3] memory _amounts;
		_amounts[i] = _amount;
		CurveSwap(liquidityPool).add_liquidity(_amounts, 0, true);
	}

	// ----- END: underlying contract abstraction

	event ChangePsm(address _oldPsm, address _newPsm);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeSlippage(uint256 _oldSlippage, uint256 _newSlippage);
}
