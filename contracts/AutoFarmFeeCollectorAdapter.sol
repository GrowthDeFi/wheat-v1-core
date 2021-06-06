// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IExchange } from "./IExchange.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";

import { Transfers } from "./modules/Transfers.sol";

contract AutoFarmFeeCollectorAdapter is ReentrancyGuard, WhitelistGuard
{
	address public immutable sourceToken;
	address public immutable targetToken;

	address public treasury;
	address public collector;

	address public exchange;

	constructor (address _sourceToken, address _targetToken,
		address _treasury, address _collector, address _exchange) public
	{
		require(_sourceToken != _targetToken, "invalid token");
		sourceToken = _sourceToken;
		targetToken = _targetToken;
		treasury = _treasury;
		collector = _collector;
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
		_totalTarget = IExchange(exchange).calcConversionFromInput(sourceToken, targetToken, _totalSource);
		return _totalTarget;
	}

	function gulp(uint256 _minTotalTarget) external onlyEOAorWhitelist nonReentrant
	{
		require(exchange != address(0), "exchange not set");
		uint256 _totalSource = Transfers._getBalance(sourceToken);
		Transfers._approveFunds(sourceToken, exchange, _totalSource);
		IExchange(exchange).convertFundsFromInput(sourceToken, targetToken, _totalSource, 1);
		uint256 _totalTarget = Transfers._getBalance(targetToken);
		require(_totalTarget >= _minTotalTarget, "high slippage");
		Transfers._pushFunds(targetToken, collector, _totalTarget);
	}

	function recoverLostFunds(address _token) external onlyOwner
	{
		require(_token != sourceToken, "invalid token");
		uint256 _balance = Transfers._getBalance(_token);
		Transfers._pushFunds(_token, treasury, _balance);
	}

	function setCollector(address _newCollector) external onlyOwner
	{
		require(_newCollector != address(0), "invalid address");
		address _oldCollector = collector;
		collector = _newCollector;
		emit ChangeCollector(_oldCollector, _newCollector);
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

	event ChangeCollector(address _oldCollector, address _newCollector);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeExchange(address _oldExchange, address _newExchange);
}
