// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { DelayedActionGuard } from "./DelayedActionGuard.sol";

import { Transfers } from "./modules/Transfers.sol";

import { PSM } from "./interop/Mor.sol";

// this contract is to work around a bug when injecting funds into the PSM in the original code
contract MorPSMInjector is ReentrancyGuard, /*WhitelistGuard,*/ DelayedActionGuard
{
	// adapter token configuration
	address payable public immutable peggedToken;

	// addresses receiving tokens
	address public psm;
	address public treasury;

	constructor (address payable _peggedToken, address _psm, address _treasury) public
	{
		peggedToken = _peggedToken;
		psm = _psm;
		treasury = _treasury;
	}

	function gulp() external /*onlyEOAorWhitelist*/ nonReentrant
	{
		require(_gulp(), "unavailable");
	}

	function _gulp() internal returns (bool _success)
	{
		uint256 _totalBalance = Transfers._getBalance(peggedToken);
		if (psm == address(0)) {
			Transfers._pushFunds(peggedToken, treasury, _totalBalance);
		} else {
			Transfers._approveFunds(peggedToken, PSM(psm).gemJoin(), _totalBalance);
			PSM(psm).sellGem(treasury, _totalBalance);
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

	event ChangePsm(address _oldPsm, address _newPsm);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
}
