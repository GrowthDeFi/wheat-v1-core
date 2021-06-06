// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IExchange } from "./IExchange.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";

import { Transfers } from "./modules/Transfers.sol";

import { PantherToken } from "./interop/PantherSwap.sol";

contract PantherSwapBuybackAdapter is ReentrancyGuard, WhitelistGuard
{
	address public immutable sourceToken;
	address public immutable targetToken;

	address public treasury;
	address public buyback;

	address public exchange;

	constructor (address _sourceToken, address _targetToken,
		address _treasury, address _buyback, address _exchange) public
	{
		require(_sourceToken != _targetToken, "invalid token");
		sourceToken = _sourceToken;
		targetToken = _targetToken;
		treasury = _treasury;
		buyback = _buyback;
		exchange = _exchange;
	}

	function pendingSource() external view returns (uint256 _totalSource)
	{
		return Transfers._getBalance(sourceToken);
	}

	function pendingTarget() external view returns (uint256 _totalTarget)
	{
		require(exchange != address(0), "exchange not set");
		uint256 _totalSource = Transfers._getBalance(sourceToken);
		uint256 _limitSource = _calcMaxRewardTransferAmount();
		if (_totalSource > _limitSource) {
			_totalSource = _limitSource;
		}
		_totalTarget = IExchange(exchange).calcConversionFromInput(sourceToken, targetToken, _totalSource);
		return _totalTarget;
	}

	function gulp(uint256 _minTotalTarget) external onlyEOAorWhitelist nonReentrant
	{
		require(exchange != address(0), "exchange not set");
		uint256 _totalSource = Transfers._getBalance(sourceToken);
		uint256 _limitSource = _calcMaxRewardTransferAmount();
		if (_totalSource > _limitSource) {
			_totalSource = _limitSource;
		}
		Transfers._approveFunds(sourceToken, exchange, _totalSource);
		IExchange(exchange).convertFundsFromInput(sourceToken, targetToken, _totalSource, 1);
		uint256 _totalTarget = Transfers._getBalance(targetToken);
		require(_totalTarget >= _minTotalTarget, "high slippage");
		Transfers._pushFunds(targetToken, buyback, _totalTarget);
	}

	function recoverLostFunds(address _token) external onlyOwner
	{
		require(_token != sourceToken, "invalid token");
		uint256 _balance = Transfers._getBalance(_token);
		Transfers._pushFunds(_token, treasury, _balance);
	}

	function setBuyback(address _newBuyback) external onlyOwner
	{
		require(_newBuyback != address(0), "invalid address");
		address _oldBuyback = buyback;
		buyback = _newBuyback;
		emit ChangeBuyback(_oldBuyback, _newBuyback);
	}

	function setTreasury(address _newTreasury) external onlyOwner
	{
		require(_newTreasury != address(0), "invalid address");
		address _oldTreasury = treasury;
		treasury = _newTreasury;
		emit ChangeTreasury(_oldTreasury, _newTreasury);
	}

	function setExchange(address _newExchange) external onlyOwner
	{
		address _oldExchange = exchange;
		exchange = _newExchange;
		emit ChangeExchange(_oldExchange, _newExchange);
	}

	function _calcMaxRewardTransferAmount() internal view returns (uint256 _maxRewardTransferAmount)
	{
		return PantherToken(sourceToken).maxTransferAmount();
	}

	event ChangeBuyback(address _oldBuyback, address _newBuyback);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeExchange(address _oldExchange, address _newExchange);
}
