// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IExchange } from "./IExchange.sol";

import { Transfers } from "./modules/Transfers.sol";
import { UniswapV2ExchangeAbstraction } from "./modules/UniswapV2ExchangeAbstraction.sol";
import { UniswapV2LiquidityPoolAbstraction } from "./modules/UniswapV2LiquidityPoolAbstraction.sol";

contract Exchange is IExchange, Ownable
{
	address public router;
	address public treasury;

	constructor (address _router, address _treasury) public
	{
		router = _router;
		treasury = _treasury;
	}

	function calcConversionFromInput(address _from, address _to, uint256 _inputAmount) external view override returns (uint256 _outputAmount)
	{
		return UniswapV2ExchangeAbstraction._calcConversionFromInput(router, _from, _to, _inputAmount);
	}

	function calcConversionFromOutput(address _from, address _to, uint256 _outputAmount) external view override returns (uint256 _inputAmount)
	{
		return UniswapV2ExchangeAbstraction._calcConversionFromOutput(router, _from, _to, _outputAmount);
	}

	function calcJoinPoolFromInput(address _pool, address _token, uint256 _inputAmount) external view override returns (uint256 _outputShares)
	{
		return UniswapV2LiquidityPoolAbstraction._calcJoinPoolFromInput(router, _pool, _token, _inputAmount);
	}

	function convertFundsFromInput(address _from, address _to, uint256 _inputAmount, uint256 _minOutputAmount) external override returns (uint256 _outputAmount)
	{
		address _sender = msg.sender;
		Transfers._pullFunds(_from, _sender, _inputAmount);
		_outputAmount = UniswapV2ExchangeAbstraction._convertFundsFromInput(router, _from, _to, _inputAmount, _minOutputAmount);
		Transfers._pushFunds(_to, _sender, _outputAmount);
		return _outputAmount;
	}

	function convertFundsFromOutput(address _from, address _to, uint256 _outputAmount, uint256 _maxInputAmount) external override returns (uint256 _inputAmount)
	{
		address _sender = msg.sender;
		Transfers._pullFunds(_from, _sender, _maxInputAmount);
		_inputAmount = UniswapV2ExchangeAbstraction._convertFundsFromOutput(router, _from, _to, _outputAmount, _maxInputAmount);
		Transfers._pushFunds(_from, _sender, _maxInputAmount - _inputAmount);
		Transfers._pushFunds(_to, _sender, _outputAmount);
		return _inputAmount;
	}

	function joinPoolFromInput(address _pool, address _token, uint256 _inputAmount, uint256 _minOutputShares) external override returns (uint256 _outputShares)
	{
		address _sender = msg.sender;
		Transfers._pullFunds(_token, _sender, _inputAmount);
		_outputShares = UniswapV2LiquidityPoolAbstraction._joinPoolFromInput(router, _pool, _token, _inputAmount, _minOutputShares);
		Transfers._pushFunds(_pool, _sender, _outputShares);
		return _outputShares;
	}

	function recoverLostFunds(address _token) external onlyOwner
	{
		uint256 _balance = Transfers._getBalance(_token);
		Transfers._pushFunds(_token, treasury, _balance);
	}

	function setRouter(address _newRouter) external onlyOwner
	{
		require(_newRouter != address(0), "invalid address");
		address _oldRouter = router;
		router = _newRouter;
		emit ChangeRouter(_oldRouter, _newRouter);
	}

	function setTreasury(address _newTreasury) external onlyOwner
	{
		require(_newTreasury != address(0), "invalid address");
		address _oldTreasury = treasury;
		treasury = _newTreasury;
		emit ChangeTreasury(_oldTreasury, _newTreasury);
	}

	event ChangeRouter(address _oldRouter, address _newRouter);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
}
